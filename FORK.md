# Fork

Source engine: Ryujinx (C# / ARMeilleure / LightningJit / Vulkan).
iOS: NativeAOT `Ryujinx.Headless.SDL2` + Helion host.

Patch:
- LightningJit cache uses Darwin copy on iOS ARM64 (same ISA, MAP_JIT).
- Helper callbacks go through HelionBridge, not a third-party iOS shell.
