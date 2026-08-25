# Helion

Helion is a **system emulator for iPhone** (sideload IPA).

It is **not** UTM, **not** Virtual Mac, and **not** a rebrand of those apps.
The CPU/machine engine is **[QEMU](https://www.qemu.org/)** (GPL-2.0), built for
`iphoneos` from [utmapp/qemu](https://github.com/utmapp/qemu) `utm-edition`
(QEMU with iOS host support) plus Helion’s own patches in [`patches/`](patches/).

You add your own disk or ISO. Helion does not torrent or ship an operating system.

## What 0.1 is

- Original Helion UI (Add ISO, Start, serial console)
- `qemu-system-aarch64` and `qemu-system-x86_64` when CI links them
- TCG only (no KVM on iOS). JIT: `get-task-allow` + StikDebug
- Serial output. No Cocoa GUI in 0.1

## License

GPL-2.0-only — because the IPA contains QEMU. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).

## Build

GitHub Actions (macOS runner, your `p12` secrets). Workflow: **Build Helion IPA**.
