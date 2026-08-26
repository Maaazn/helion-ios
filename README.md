# Puck Linux

Full-screen Linux computer inside a sideloaded iPhone app.

Guest: **Arch Linux i686**, kernel **6.13.7-arch1-1.0-ARCH32** (GPL-2.0)
with Xorg, Fluxbox, Firefox, pacman. Tiny Core is not used.
The running system image and the 9p pages needed to reach the desktop
are bundled in the app.
Emulator: [v86](https://github.com/copy/v86) (BSD-2-Clause) — x86 in WebAssembly.
That is the allowed path. iPhone apps do not get Hypervisor.framework.

On launch the host UIKit pointer is hidden (`GCEventViewController` +
`prefersPointerLocked`). You use the Linux X11 cursor.

Tap the top edge for licenses / pointer / reboot.

See NOTICE.md.
