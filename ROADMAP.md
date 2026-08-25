# Helion Roadmap

Independent multi-system emulator for iOS.  
Target class: UTM-level capability, raised further.

---

## Phase 0 — Reality check (done)

- [x] App installs and launches on device
- [x] QEMU dylib loads in-process
- [x] JIT path exists (StikDebug)
- [x] Basic ISO + disk storage
- [ ] **Display actually shows guest** ← current blocker (VNC path failed)

---

## Phase 1 — Real display foundation (NOW)

Goal: replace fragile VNC primary path with a path that can grow into SPICE + Metal.

1. **QEMU logging** — capture stdout/stderr into the app so we see real startup failures.
2. **Modular host code** — split the single `Helion.m` into:
   - `Engine` (start/stop, argv, lifecycle)
   - `Display` (current interim + future SPICE/Metal)
   - `Store` (ISO, disks, VM configs)
   - `UI` (Home, Session, Settings)
3. **Config model** — introduce `config.json` per VM instead of hard-coded argv.
4. **SPICE enablement in build** — add spice-protocol + spice-server to the iOS QEMU build (hardest dependency work).
5. **Interim display** — keep a working fallback while SPICE lands (improved logging + optional framebuffer pull).

Deliverable: IPA that either shows the guest **or** shows the exact QEMU error instead of infinite “Waiting for VNC”.

---

## Phase 2 — SPICE + Metal

1. Integrate CocoaSpice (or a controlled SPICE client).
2. Metal presentation (`MTKView` + texture upload / IOSurface).
3. Pointer + touch + on-screen keyboard.
4. Remove VNC as primary path.

Deliverable: Guest desktop visible and interactive via Metal.

---

## Phase 3 — Device management & settings

1. VM list + create / edit / delete.
2. Drive manager (add disk, attach ISO, resize).
3. CPU / RAM / SMP / machine type controls.
4. Network options (user, none, …).
5. Boot order and firmware selection (OVMF / OpenCore for macOS guests).

Deliverable: User can fully configure a VM without touching code.

---

## Phase 4 — Multi-system polish

1. Templates (Windows, Linux, macOS, custom).
2. Save / restore state where feasible.
3. Performance passes (TCG, memory, display).
4. Better input (external keyboard, controllers).
5. Documentation and clear identity as an independent project.

---

## Non-goals (for now)

- Jailbreak-only features as the only path
- Rebranding or forking UTM UI
- Claiming “full competitor” before Phase 2 display works

---

## Current focus

**Phase 1 items 1–3 first.**  
Without real logs and modular code, every later step stays blind.
