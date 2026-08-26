Puck Linux is original. Not an exploit. Not a hypervisor.

The computer inside the app is real Linux: Arch Linux i686, kernel
6.13.7-arch1-1.0-ARCH32 (GPL-2.0) with Xorg, Firefox and pacman. It runs
in v86 (BSD-2-Clause). SeaBIOS is LGPL.

iPhone silicon can run a hypervisor in principle. iOS 27 does not give that
to sideloaded apps. hv_vm_create / Virtualization.framework stay unavailable
on iPhone. VirtualMac is iPad. We ship in-app emulation.

Inside Puck Linux the host UIKit pointer is hidden (GCEventViewController +
prefersPointerLocked + CSS cursor:none). The visible guest pointer is X11.
AssistiveTouch is a system overlay; turn it off while using Linux if you
want a single cursor.
