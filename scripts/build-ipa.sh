#!/bin/bash
# Helion sideload IPA — original app, QEMU binaries copied in.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
MIN="${HELION_MIN_VERSION:-16.0}"
OUT="${HELION_BUILD_ROOT:-$ROOT/build}/ipa"
APP="$OUT/Payload/Helion.app"
BIN="$APP/Helion"
DIST="${HELION_DIST:-$ROOT/dist}"
VER="${HELION_VERSION:-1.1.1}"

rm -rf "$OUT"
mkdir -p "$APP" "$DIST"

cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>Helion</string>
  <key>CFBundleIdentifier</key><string>com.maaazn.helion</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Helion</string>
  <key>CFBundleDisplayName</key><string>Helion</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.1</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
  <key>LSRequiresIPhoneOS</key><true/>
  <key>MinimumOSVersion</key><string>16.0</string>
  <key>UILaunchScreen</key><dict/>
  <key>CFBundleIcons</key>
  <dict>
    <key>CFBundlePrimaryIcon</key>
    <dict>
      <key>CFBundleIconFiles</key>
      <array>
        <string>AppIcon60x60</string>
        <string>AppIcon76x76</string>
        <string>AppIcon83.5x83.5</string>
      </array>
    </dict>
  </dict>
  <key>CFBundleIcons~ipad</key>
  <dict>
    <key>CFBundlePrimaryIcon</key>
    <dict>
      <key>CFBundleIconFiles</key>
      <array>
        <string>AppIcon76x76</string>
        <string>AppIcon83.5x83.5</string>
      </array>
    </dict>
  </dict>
  <key>UIRequiredDeviceCapabilities</key><array><string>arm64</string></array>
  <key>UISupportedInterfaceOrientations</key>
  <array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
  </array>
  <key>UIFileSharingEnabled</key><true/>
  <key>LSSupportsOpeningDocumentsInPlace</key><true/>
  <key>UIStatusBarStyle</key><string>UIStatusBarStyleLightContent</string>
</dict></plist>
PLIST
plutil -replace CFBundleShortVersionString -string "$VER" "$APP/Info.plist"
plutil -replace CFBundleVersion -string "${GITHUB_RUN_NUMBER:-$(date +%Y%m%d%H%M)}" "$APP/Info.plist"
plutil -replace MinimumOSVersion -string "$MIN" "$APP/Info.plist"

cp "$ROOT/NOTICE.md" "$APP/NOTICE.md"
cp "$ROOT/ENGINE.md" "$APP/ENGINE.md"
cp "$ROOT/LICENSE" "$APP/LICENSE"

if [[ -n "${QEMU_DIR:-}" && -d "$QEMU_DIR" ]]; then
  for f in "$QEMU_DIR"/*COPYING*; do [[ -f "$f" ]] && cp "$f" "$APP/"; done
  [[ -f "$QEMU_DIR/qemu-system-aarch64" ]] && cp "$QEMU_DIR/qemu-system-aarch64" "$APP/" && chmod +x "$APP/qemu-system-aarch64"
  [[ -f "$QEMU_DIR/qemu-system-x86_64" ]] && cp "$QEMU_DIR/qemu-system-x86_64" "$APP/" && chmod +x "$APP/qemu-system-x86_64"
  for d in "$QEMU_DIR"/libqemu-system-*.dylib; do
    [[ -f "$d" ]] && cp "$d" "$APP/" && chmod +x "$d"
  done
  [[ -f "$QEMU_DIR/qemu-build.log" ]] && cp "$QEMU_DIR/qemu-build.log" "$APP/"
  if [[ -d "$QEMU_DIR/osxkvm" ]]; then
    mkdir -p "$APP/OSX-KVM"
    cp -R "$QEMU_DIR/osxkvm/"* "$APP/OSX-KVM/" || true
  fi
fi

python3 - "$APP/AppIcon1024x1024.png" <<'PY'
import struct, zlib, sys
w = h = 1024
def chunk(tag, data):
    return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
rows = []
cx, cy, r = 512, 512, 340
for y in range(h):
    row = bytearray(1 + 3 * w)
    row[0] = 0
    for x in range(w):
        dx, dy = x - cx, y - cy
        inside = dx * dx + dy * dy <= r * r
        if inside:
            row[1+3*x:4+3*x] = bytes([40, 210, 255])
        else:
            row[1+3*x:4+3*x] = bytes([12, 18, 36])
    rows.append(bytes(row))
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress(b''.join(rows), 9)) + chunk(b'IEND', b'')
open(sys.argv[1], 'wb').write(png)
PY
for spec in \
  '120:AppIcon60x60@2x.png' \
  '180:AppIcon60x60@3x.png' \
  '152:AppIcon76x76@2x.png' \
  '167:AppIcon83.5x83.5@2x.png' \
  '80:AppIcon40x40@2x.png' \
  '120:AppIcon40x40@3x.png' \
  '58:AppIcon29x29@2x.png' \
  '87:AppIcon29x29@3x.png'
do
  size="${spec%%:*}"; name="${spec##*:}"
  sips -z "$size" "$size" "$APP/AppIcon1024x1024.png" --out "$APP/$name" >/dev/null
done

xcrun --sdk iphoneos clang \
  -arch arm64 -miphoneos-version-min="$MIN" -isysroot "$SDK" \
  -fobjc-arc -fblocks \
  -framework Foundation -framework UIKit -framework UniformTypeIdentifiers \
  -framework GameController -framework CoreGraphics -framework QuartzCore \
  "$ROOT/app/Helion.m" \
  -o "$BIN"

xattr -cr "$APP" || true
ls -lh "$BIN"
mkdir -p "$DIST"
( cd "$OUT" && zip -r -y "$DIST/Helion.ipa" Payload )
ls -lh "$DIST/Helion.ipa"
echo "built $DIST/Helion.ipa"
