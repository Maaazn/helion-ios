Puck Linux is original. Not an exploit. Not a hypervisor.

The computer inside the app is real Linux: Tiny Core 16, kernel
6.12.11-tinycore (GPL-2.0). It runs in v86 (BSD-2-Clause). SeaBIOS is LGPL.

iPhone silicon can run a hypervisor in principle. iOS 27 does not give that
to sideloaded apps. hv_vm_create / Virtualization.framework stay unavailable
on iPhone. VirtualMac is iPad. We ship in-app emulation.

Inside Puck Linux the host mouse is hidden (prefersPointerLocked + CSS
cursor:none). The visible pointer is the Linux guest cursor.
