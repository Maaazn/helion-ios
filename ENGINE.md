# Engine

Helion does not claim to be a from-scratch CPU emulator. A modern
system emulator that boots real ISOs is QEMU-class work.

## QEMU

- Project: QEMU (GPL-2.0)
- iOS-host fork: utmapp/qemu `utm-edition`
- Helion patches: `patches/` (iOS SDK: JIT WP stub, `sys/mount.h` in
  `file-posix.c` only — never as a global `-include` that breaks `.S`)
- Toolchain wrappers: `iphoneos-clang`, `iphoneos-nm`, `iphoneos-ar`, …
- Targets: `aarch64-softmmu`, `x86_64-softmmu`
- Coroutine: `sigaltstack` (no `makecontext` on iOS)
- FDT: internal
- Display 0.1: `-nographic` serial. GUI backends (cocoa/sdl/gtk) off.

## Runtime

StikDebug / SideJIT for TCG speed. Hypervisor.framework is not on iOS.
