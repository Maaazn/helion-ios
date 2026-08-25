#!/bin/bash
# Package qemu-x86_64-softmmu as an iOS framework (UTM layout, one target only).
set -euo pipefail
OUT="${1:?qemu-ios dir}"
BDIR="$OUT/src-qemu/build"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PY="$ROOT/scripts/link-qemu-inprocess.py"
FW="$OUT/Frameworks/qemu-x86_64-softmmu.framework"
mkdir -p "$FW"
if [[ ! -d "$BDIR" ]]; then
  echo "RELIRK_NO_BUILDDIR"; exit 0
fi
python3 "$PY" "$BDIR" "$FW/qemu-x86_64-softmmu" dylib
# overwrite install name to @rpath like UTM
if [[ -f "$FW/qemu-x86_64-softmmu" ]]; then
  xcrun install_name_tool -id \
    "@rpath/qemu-x86_64-softmmu.framework/qemu-x86_64-softmmu" \
    "$FW/qemu-x86_64-softmmu" || true
fi
cat > "$FW/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>qemu-x86_64-softmmu</string>
  <key>CFBundleIdentifier</key><string>com.maaazn.helion.qemu-x86-64-softmmu</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>MinimumOSVersion</key><string>16.0</string>
</dict></plist>
PLIST
# firmware — QEMU pc-bios (GPL), not Apple OS
BIOS="$OUT/bios"
mkdir -p "$BIOS"
for src in "$OUT/src-qemu/pc-bios" "$BDIR/pc-bios"; do
  [[ -d "$src" ]] || continue
  for f in edk2-x86_64-code.fd edk2-i386-vars.fd edk2-x86_64-secure-code.fd \
           vgabios-stdvga.bin vgabios.bin kvmvapic.bin efi-e1000.rom efi-virtio.rom; do
    [[ -f "$src/$f" ]] && cp "$src/$f" "$BIOS/"
  done
done
ls -lh "$FW/qemu-x86_64-softmmu" "$BIOS" || true
file "$FW/qemu-x86_64-softmmu" || true
