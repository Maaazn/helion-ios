# Helion Architecture

**Independent system emulator for iOS.**  
Not a UTM fork. Inspired by the same technical path every serious emulator takes, then raised further.

---

## Goal

Run real guest operating systems (Windows, macOS, Linux, and more) on iPhone/iPad with:

- SPICE display path → Metal rendering
- Full device management (disks, network, USB, audio, boot)
- Deep configuration and customization
- Multi-architecture support (x86_64 + aarch64 guests first)
- Clean, maintainable host code (not a single 1000-line file)

---

## Layers

```
┌─────────────────────────────────────────────┐
│  UI (UIKit / later SwiftUI)                 │
│  Home · Session · Settings · Device Manager │
├─────────────────────────────────────────────┤
│  Host Services                              │
│  Config · Storage · ISO/Disk · JIT helper   │
├─────────────────────────────────────────────┤
│  Display + Input                            │
│  SPICE client → Metal textures              │
│  Touch / pointer / keyboard                 │
├─────────────────────────────────────────────┤
│  Engine                                     │
│  In-process QEMU (dylib / weak symbols)     │
│  argv builder · lifecycle · logging         │
├─────────────────────────────────────────────┤
│  QEMU (utm-edition base + our patches)      │
│  TCG · SPICE · system targets               │
└─────────────────────────────────────────────┘
```

---

## Display path (target)

1. QEMU runs with SPICE enabled (`-spice ...` or equivalent).
2. Host connects via CocoaSpice (or a leaner SPICE client we control).
3. Framebuffer / IOSurface lands in Metal textures.
4. `MTKView` presents at 60 fps with proper scaling.

VNC is **deprecated** as the primary path. It remains only as a temporary fallback while SPICE lands.

---

## Engine rules

- QEMU never runs as a separate process (iOS blocks `posix_spawn` of MH_EXECUTE).
- Always in-process via dylib + `qemu_init` / main loop on a dedicated pthread.
- One active instance at a time (QEMU does not clean up perfectly).
- All guest I/O stays inside the app sandbox.
- JIT requires external activation (StikDebug / get-task-allow) on current iOS.

---

## Configuration model (upcoming)

Each VM is a directory + `config.json`:

```json
{
  "name": "Windows 11",
  "arch": "x86_64",
  "machine": "q35",
  "cpu": "qemu64",
  "memoryMB": 2048,
  "smp": 2,
  "display": "spice",
  "drives": [ ... ],
  "bootOrder": "dc",
  "network": { "type": "user" }
}
```

This opens the door to full customization without hard-coding argv.

---

## Principles

1. **Independent identity** — Helion is its own project.
2. **Honest progress** — no fake “working” screens. Status and logs are real.
3. **Raise the baseline** — we study existing patches (UTM, OSX-KVM, etc.) and improve them, we do not copy-paste blindly.
4. **Modular code** — engine, display, storage, and UI live in clear modules.
5. **User control** — settings and device management are first-class, not afterthoughts.
