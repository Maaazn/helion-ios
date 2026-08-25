#pragma once
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

enum { HELION_FB_W = 1280, HELION_FB_H = 720 };

typedef struct HelionNCE HelionNCE;

HelionNCE *helion_nce_create(void);
void helion_nce_destroy(HelionNCE *n);
uint32_t *helion_nce_fb(HelionNCE *n);
int helion_nce_running(HelionNCE *n);
const char *helion_nce_log(HelionNCE *n);
int helion_nce_jit_ok(void);

/* Built-in original ARM64 probe (not Nintendo). Fills the framebuffer via NCE. */
int helion_nce_run_probe(HelionNCE *n, char *err, size_t errlen);

/* User NRO (homebrew). */
int helion_nce_run_nro(HelionNCE *n, const char *path, char *err, size_t errlen);

void helion_nce_stop(HelionNCE *n);
