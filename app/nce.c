/* Helion NCE — original ARM64 native-code host for iOS.
 * Horizon SVC is patched to BRK and trapped (iOS uses SVC itself).
 * Not MeloNX, not Ryujinx, not Yuzu. No Nintendo code. */

#include "nce.h"
#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <mach/mach.h>

#if defined(__APPLE__)
#include <libkern/OSCacheControl.h>
#ifndef MAP_JIT
#define MAP_JIT 0x800
#endif
#endif

struct HelionNCE {
    uint32_t *fb;
    void *jit;
    size_t jit_sz;
    pthread_t th;
    volatile int running;
    volatile int stop;
    char log[4096];
};

static HelionNCE *G = NULL;
static struct sigaction g_old_trap;

static void nlog(HelionNCE *n, const char *fmt, ...) {
    char b[512];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(b, sizeof b, fmt, ap);
    va_end(ap);
    size_t used = strlen(n->log);
    if (used + strlen(b) + 2 < sizeof n->log)
        snprintf(n->log + used, sizeof n->log - used, "%s\n", b);
}

int helion_nce_jit_ok(void) {
    void *p = mmap(NULL, 16384, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE | MAP_JIT, -1, 0);
    if (p == MAP_FAILED) return 0;
    int ok = 1;
    /* write then try exec */
    ((uint32_t *)p)[0] = 0xD65F03C0; /* ret */
#if defined(__APPLE__)
    sys_icache_invalidate(p, 4);
#endif
    if (mprotect(p, 16384, PROT_READ | PROT_EXEC) != 0) ok = 0;
    munmap(p, 16384);
    return ok;
}

uint32_t *helion_nce_fb(HelionNCE *n) { return n ? n->fb : NULL; }
int helion_nce_running(HelionNCE *n) { return n ? n->running : 0; }
const char *helion_nce_log(HelionNCE *n) { return n ? n->log : ""; }

HelionNCE *helion_nce_create(void) {
    HelionNCE *n = calloc(1, sizeof *n);
    size_t fbsz = (size_t)HELION_FB_W * HELION_FB_H * 4;
    n->fb = mmap(NULL, fbsz, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
    if (n->fb == MAP_FAILED) n->fb = calloc(1, fbsz);
    for (int i = 0; i < HELION_FB_W * HELION_FB_H; i++) n->fb[i] = 0xFF101018;
    G = n;
    return n;
}

void helion_nce_destroy(HelionNCE *n) {
    if (!n) return;
    helion_nce_stop(n);
    if (n->fb) munmap(n->fb, (size_t)HELION_FB_W * HELION_FB_H * 4);
    if (n->jit) munmap(n->jit, n->jit_sz);
    if (G == n) G = NULL;
    free(n);
}

static void patch_svc_to_brk(uint8_t *p, size_t n) {
    for (size_t i = 0; i + 4 <= n; i += 4) {
        uint32_t ins;
        memcpy(&ins, p + i, 4);
        /* SVC: 1101 0100 000 iiii iiii iiii iiii 00001 */
        if ((ins & 0xFFE0001F) == 0xD4000001) {
            uint32_t imm = (ins >> 5) & 0xFFFF;
            uint32_t brk = 0xD4200000 | (imm << 5); /* BRK #imm */
            memcpy(p + i, &brk, 4);
        }
    }
}

static void trap_handler(int sig, siginfo_t *si, void *ucontext) {
    (void)sig; (void)si;
    ucontext_t *uc = ucontext;
#if defined(__arm64__) || defined(__aarch64__)
    uint64_t pc = uc->uc_mcontext->__ss.__pc;
    uint32_t ins = 0;
    memcpy(&ins, (void *)pc, 4);
    uint32_t imm = (ins >> 5) & 0xFFFF;
    uint64_t *x = (uint64_t *)uc->uc_mcontext->__ss.__x;
    HelionNCE *n = G;
    switch (imm) {
    case 0x11: { /* SleepThread — x0 ns */
        uint64_t ns = x[0];
        if (ns > 1000000000ull) ns = 1000000000ull;
        if (ns < 1000000ull) ns = 1000000ull;
        usleep((useconds_t)(ns / 1000ull));
        break;
    }
    case 0x27: { /* OutputDebugString */
        if (n && x[0]) nlog(n, "guest: %s", (char *)(uintptr_t)x[0]);
        break;
    }
    case 0x1B: /* GetInfo — return 0 */
        x[0] = 0;
        break;
    case 0x01: /* SetHeapSize — pretend ok */
        x[0] = 0;
        break;
    default:
        if (n) nlog(n, "svc 0x%x x0=%llx", imm, (unsigned long long)x[0]);
        x[0] = 0;
        break;
    }
    uc->uc_mcontext->__ss.__pc = pc + 4;
#else
    (void)uc;
#endif
}

static void install_trap(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = trap_handler;
    sa.sa_flags = SA_SIGINFO | SA_RESTART;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGTRAP, &sa, &g_old_trap);
}

static int emit_probe(uint32_t *o) {
    int i = 0;
    /* x0 = fb, x1 = pixel count */
    o[i++] = 0x5280CBE2; /* movz w2, #0x65F */
    o[i++] = 0x72A7E642; /* movk w2, #0x3F32, lsl #16  → ice-ish */
    o[i++] = 0xB8004402; /* str w2, [x0], #4 */
    o[i++] = 0xF1000421; /* subs x1, x1, #1 */
    o[i++] = 0x54FFFFA1; /* b.ne fill */
    o[i++] = 0xD28F4000; /* movz x0, #0x7A00 */
    o[i++] = 0xF2A00180; /* movk x0, #0xC, lsl #16  ~ 800000 ns */
    o[i++] = 0xD4200160; /* brk #0x11 SleepThread */
    o[i++] = 0x17FFFFFD; /* b sleep */
    o[i++] = 0xD65F03C0; /* ret */
    return i;
}

static int map_jit(HelionNCE *n, size_t sz) {
    if (n->jit) { munmap(n->jit, n->jit_sz); n->jit = NULL; }
    sz = (sz + 16383) & ~16383ull;
    void *p = mmap(NULL, sz, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE | MAP_JIT, -1, 0);
    if (p == MAP_FAILED) {
        p = mmap(NULL, sz, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_ANON | MAP_PRIVATE, -1, 0);
        if (p == MAP_FAILED) return -1;
    }
    n->jit = p;
    n->jit_sz = sz;
    return 0;
}

struct RunArg {
    HelionNCE *n;
    void (*entry)(void *, uint64_t);
    void *fb;
    uint64_t count;
};

static void *guest_thread(void *a) {
    struct RunArg *r = a;
    r->n->running = 1;
    nlog(r->n, "NCE enter %p", (void *)r->entry);
#if defined(__APPLE__)
    pthread_jit_write_protect_np(1);
#endif
    r->entry(r->fb, r->count);
    nlog(r->n, "NCE returned");
    r->n->running = 0;
    free(r);
    return NULL;
}

static int start_guest(HelionNCE *n, void *entry) {
    install_trap();
#if defined(__APPLE__)
    sys_icache_invalidate(n->jit, n->jit_sz);
    pthread_jit_write_protect_np(1);
#endif
    if (mprotect(n->jit, n->jit_sz, PROT_READ | PROT_EXEC) != 0)
        nlog(n, "mprotect exec errno=%d (JIT?)", errno);
    struct RunArg *r = calloc(1, sizeof *r);
    r->n = n;
    r->entry = (void (*)(void *, uint64_t))entry;
    r->fb = n->fb;
    r->count = (uint64_t)HELION_FB_W * (uint64_t)HELION_FB_H;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setstacksize(&attr, 8u << 20);
    int rc = pthread_create(&n->th, &attr, guest_thread, r);
    pthread_attr_destroy(&attr);
    if (rc) { n->running = 0; free(r); return -1; }
    pthread_detach(n->th);
    return 0;
}

int helion_nce_run_probe(HelionNCE *n, char *err, size_t errlen) {
    n->log[0] = 0;
    nlog(n, "Helion NCE probe");
    nlog(n, "MAP_JIT probe %s", helion_nce_jit_ok() ? "OK" : "NO — enable StikDebug JIT");
    if (map_jit(n, 4096) != 0) {
        snprintf(err, errlen, "mmap JIT failed — enable StikDebug");
        nlog(n, "%s", err);
        return -1;
    }
#if defined(__APPLE__)
    pthread_jit_write_protect_np(0);
#endif
    uint32_t ins[32];
    int k = emit_probe(ins);
    memcpy(n->jit, ins, (size_t)k * 4);
    nlog(n, "emitted %d A64 insns", k);
    if (start_guest(n, n->jit) != 0) {
        snprintf(err, errlen, "guest thread failed");
        return -1;
    }
    err[0] = 0;
    return 0;
}

#pragma pack(push, 1)
typedef struct {
    uint32_t unused, mod_off;
    uint64_t pad;
    uint32_t magic, version, file_size, flags;
    uint32_t text_off, text_size;
    uint32_t ro_off, ro_size;
    uint32_t data_off, data_size;
    uint32_t bss_size;
} NROHeader;
#pragma pack(pop)

int helion_nce_run_nro(HelionNCE *n, const char *path, char *err, size_t errlen) {
    n->log[0] = 0;
    nlog(n, "NRO %s", path);
    FILE *f = fopen(path, "rb");
    if (!f) { snprintf(err, errlen, "open NRO failed"); return -1; }
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz < 0x80 || sz > 64L << 20) { fclose(f); snprintf(err, errlen, "bad NRO size"); return -1; }
    uint8_t *file = malloc((size_t)sz);
    if (fread(file, 1, (size_t)sz, f) != (size_t)sz) { free(file); fclose(f); snprintf(err, errlen, "read NRO"); return -1; }
    fclose(f);
    NROHeader h;
    memcpy(&h, file, sizeof h);
    if (h.magic != 0x304F524E) { /* NRO0 le */
        /* magic at +0x10 */
        memcpy(&h, file, sizeof h);
    }
    uint32_t magic;
    memcpy(&magic, file + 0x10, 4);
    if (magic != 0x304F524E) {
        snprintf(err, errlen, "not NRO0 (got %08x)", magic);
        nlog(n, "%s", err);
        free(file);
        return -1;
    }
    memcpy(&h, file, sizeof h);
    size_t map = (size_t)h.text_size + h.ro_size + h.data_size + h.bss_size + 0x1000;
    if (map_jit(n, map + 0x10000) != 0) {
        snprintf(err, errlen, "mmap JIT failed — enable StikDebug");
        free(file);
        return -1;
    }
#if defined(__APPLE__)
    pthread_jit_write_protect_np(0);
#endif
    memset(n->jit, 0, n->jit_sz);
    memcpy(n->jit, file, (size_t)sz);
    patch_svc_to_brk((uint8_t *)n->jit, (size_t)sz);
    nlog(n, "mapped %zu patched SVC→BRK", (size_t)sz);
    void *entry = (uint8_t *)n->jit + 0x80; /* text often follows header; homebrew uses start */
    /* Switch NRO entry is file start (mod0) — actually code at text_off */
    entry = (uint8_t *)n->jit + h.text_off;
    free(file);
    if (start_guest(n, entry) != 0) {
        snprintf(err, errlen, "guest thread failed");
        return -1;
    }
    err[0] = 0;
    return 0;
}

void helion_nce_stop(HelionNCE *n) {
    if (!n) return;
    n->stop = 1;
    n->running = 0;
}
