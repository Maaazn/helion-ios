Puck is original. Not an exploit. Not a jailbreak.

iPhone system cursor: Apple AssistiveTouch. Always Show Menu off hides the
button. That setting is the permanence — it survives closing Puck.

The computer inside Puck is real Linux (Tiny Core 11.0, kernel
5.4.3-tinycore) running in the v86 emulator (x86 in WebAssembly).

- Linux kernel — GPL-2.0. Source: https://www.tinycorelinux.net/11.x/ and https://www.kernel.org/
- Tiny Core Linux 11.0 — https://tinycorelinux.net/
- v86 — BSD-2-Clause. https://github.com/copy/v86
- SeaBIOS + VGA BIOS — LGPL, as shipped by v86

iPhone is ARM64. iOS will not load a Linux kernel on the hardware. The
allowed path is in-app emulation. That is what 1.8.0 ships.
