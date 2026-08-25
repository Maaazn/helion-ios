# Puck 1.8.0

Pointer for iPhone, and a small real Linux computer inside the app.

## Pointer

iPhone has no system mouse pointer unless AssistiveTouch is on. Turn it on
once, then turn **Always Show Menu** off so the floating button hides. That
setting stays until you turn AssistiveTouch off — Home Screen included.

Puck keeps the USB mouse claimed (Game Controller). Truth that the system
pointer is live: two HID devices (`Mouse` + your USB mouse) or hover. The
public AssistiveTouch flag from a sideload is not reliable.

## Linux computer

The guest is **Tiny Core Linux 11.0** (real kernel 5.4.3-tinycore, Xvesa /
FLWM desktop). It runs in **v86**, an open-source x86 emulator
(WebAssembly). We announce this in-app (تراخيص) and in [NOTICE.md](NOTICE.md).

iPhone silicon is ARM64. iOS does not allow a Linux kernel in EL1 on the
SoC. We do not claim native ARM64 Linux. The allowed product is Linux
**inside Puck** via emulation.

| Piece | License | Source |
| --- | --- | --- |
| Linux kernel (in Tiny Core 11) | GPL-2.0 | [tinycorelinux.net/11.x](https://www.tinycorelinux.net/11.x/) · [kernel.org](https://www.kernel.org/) |
| Tiny Core Linux 11.0 | mixed OSI (see upstream) | [tinycorelinux.net](https://tinycorelinux.net/) |
| v86 | BSD-2-Clause | [github.com/copy/v86](https://github.com/copy/v86) |
| SeaBIOS / VGA BIOS | LGPL | shipped with v86 |
| Puck shell + iPhone pointer | original | this repo |

ISO in `computer/TinyCore.iso` (TinyCore-11.0, 19 922 944 bytes).

## Build (macOS, signed sideload)

```
HELION_VERSION=1.8.0 ./scripts/build-ipa.sh
```

GitHub Actions on this repo signs `Helion.ipa` with the Apple development
certificate and publishes it on the matching GitHub Release.

Bundle id: `com.maaazn.helion`. Display name: **Puck**.
