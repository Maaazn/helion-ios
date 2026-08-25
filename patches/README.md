# Helion patches on QEMU (iOS host)

Applied at CI after clone. Original Helion, not copied from UTM sources.

| Patch | Why |
|---|---|
| `osdep.h` `pthread_jit_write_protect_np` stub | iPhone SDK marks the symbol unavailable; TCG still needs StikDebug MAP_JIT at runtime |
| `#include <sys/mount.h>` only in `block/file-posix.c` | `fstatfs` / `struct statfs` on iOS |
| `iphoneos-nm` / `objcopy` wrappers | meson `block.syms` (9.3.0 failed without `nm`) |
| `--with-coroutine=sigaltstack` | iOS has no `makecontext` |
| `-Dfdt=internal` | `aarch64-softmmu` needs FDT |
| no global `-include sys/mount.h` | that fed C headers into assembler (9.2.1) |

Upstream: qemu/qemu and utmapp/qemu. We do not vendor their trees in git.
