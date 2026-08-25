#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
MIN="${HELION_MIN_VERSION:-16.0}"
OUT="${HELION_BUILD_ROOT:-$ROOT/build}/ipa"
APP="$OUT/Payload/Helion.app"
BIN="$APP/Helion"
DIST="${HELION_DIST:-$ROOT/dist}"
VER="${HELION_VERSION:-0.1.0}"

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
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
  <key>LSRequiresIPhoneOS</key><true/>
  <key>MinimumOSVersion</key><string>16.0</string>
  <key>UILaunchScreen</key><dict/>
  <key>UIApplicationSceneManifest</key>
  <dict>
    <key>UIApplicationSupportsMultipleScenes</key><false/>
    <key>UISceneConfigurations</key>
    <dict>
      <key>UIWindowSceneSessionRoleApplication</key>
      <array>
        <dict>
          <key>UISceneConfigurationName</key><string>Default</string>
          <key>UISceneDelegateClassName</key><string>HelionSceneDelegate</string>
        </dict>
      </array>
    </dict>
  </dict>
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

cp "$ROOT/NOTICE.md" "$APP/NOTICE.md"
cp "$ROOT/LICENSE" "$APP/LICENSE"

python3 - "$APP/AppIcon1024x1024.png" <<'PY'
import struct, zlib, sys
w = h = 1024
def chunk(tag, data):
    return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
rows = []
cx, cy, r = 512, 512, 340
for y in range(h):
    row = bytearray(1 + 3 * w); row[0] = 0
    for x in range(w):
        dx, dy = x - cx, y - cy
        inside = dx * dx + dy * dy <= r * r
        row[1+3*x:4+3*x] = bytes([50, 220, 225] if inside else [12, 18, 36])
    rows.append(bytes(row))
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress(b''.join(rows), 9)) + chunk(b'IEND', b'')
open(sys.argv[1], 'wb').write(png)
PY
for spec in \
  '120:AppIcon60x60@2x.png' '180:AppIcon60x60@3x.png' \
  '152:AppIcon76x76@2x.png' '167:AppIcon83.5x83.5@2x.png' \
  '80:AppIcon40x40@2x.png' '120:AppIcon40x40@3x.png' \
  '58:AppIcon29x29@2x.png' '87:AppIcon29x29@3x.png'
do
  size="${spec%%:*}"; name="${spec##*:}"
  sips -z "$size" "$size" "$APP/AppIcon1024x1024.png" --out "$APP/$name" >/dev/null
done

xcrun --sdk iphoneos clang \
  -arch arm64 -miphoneos-version-min="$MIN" -isysroot "$SDK" \
  -fobjc-arc -fblocks -I"$ROOT/app" \
  -framework Foundation -framework UIKit -framework UniformTypeIdentifiers \
  -framework Metal -framework MetalKit -framework GameController \
  -framework QuartzCore -framework CoreGraphics \
  "$ROOT/app/nce.c" "$ROOT/app/Helion.m" \
  -o "$BIN"

xattr -cr "$APP" || true
ls -lh "$BIN"
mkdir -p "$DIST"
( cd "$OUT" && zip -r -y "$DIST/Helion.ipa" Payload )
ls -lh "$DIST/Helion.ipa"
echo "built $DIST/Helion.ipa"
