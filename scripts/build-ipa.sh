#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
MIN=16.0
OUT="${HELION_BUILD_ROOT:-$ROOT/build}/ipa"
APP="$OUT/Payload/Helion.app"
FW="$APP/Frameworks"
DIST="${HELION_DIST:-$ROOT/dist}"
VER="${HELION_VERSION:-0.3.0}"
IDENT_ARM=arm64

rm -rf "$OUT"
mkdir -p "$APP" "$FW" "$DIST" "$APP/HelionBridge.framework"

cat > "$APP/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Helion</string>
  <key>CFBundleIdentifier</key><string>com.maaazn.helion</string>
  <key>CFBundleName</key><string>Helion</string>
  <key>CFBundleDisplayName</key><string>Helion</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VER</string>
  <key>CFBundleVersion</key><string>${GITHUB_RUN_NUMBER:-1}</string>
  <key>LSRequiresIPhoneOS</key><true/>
  <key>MinimumOSVersion</key><string>$MIN</string>
  <key>UILaunchScreen</key><dict/>
  <key>UIApplicationSceneManifest</key>
  <dict>
    <key>UIApplicationSupportsMultipleScenes</key><false/>
    <key>UISceneConfigurations</key>
    <dict>
      <key>UIWindowSceneSessionRoleApplication</key>
      <array><dict>
        <key>UISceneConfigurationName</key><string>Default</string>
        <key>UISceneDelegateClassName</key><string>HelionSceneDelegate</string>
      </dict></array>
    </dict>
  </dict>
  <key>UISupportedInterfaceOrientations</key>
  <array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
  </array>
  <key>UIFileSharingEnabled</key><true/>
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
  <key>UIStatusBarStyle</key><string>UIStatusBarStyleLightContent</string>
</dict></plist>
PLIST

python3 - "$APP/AppIcon1024x1024.png" <<'PY'
import struct, zlib, math, sys
w=h=1024
def chunk(tag, data):
    return struct.pack('>I', len(data))+tag+data+struct.pack('>I', zlib.crc32(tag+data)&0xffffffff)
rows=[]
cx=cy=512
for y in range(h):
    row=bytearray([0])
    for x in range(w):
        dx,dy=x-cx,y-cy
        r=math.hypot(dx,dy)/340
        ang=math.atan2(dy,dx)
        ray=abs(math.cos(ang*4))**8
        core=max(0,1-r)
        gold=min(1, core*1.2 + ray*(1-min(1,r))*0.55)
        bg=12
        R=int(bg + gold*230); G=int(bg + gold*170); B=int(bg + gold*55)
        if r<0.12: R=G=B=255
        row += bytes([min(255,R), min(255,G), min(255,B)])
    rows.append(bytes(row))
png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR', struct.pack('>IIBBBBB', w,h,8,2,0,0,0))
png+=chunk(b'IDAT', zlib.compress(b''.join(rows),9))+chunk(b'IEND', b'')
open(sys.argv[1],'wb').write(png)
PY
for spec in '180:AppIcon60x60@3x.png' '120:AppIcon60x60@2x.png' '152:AppIcon76x76@2x.png' '167:AppIcon83.5x83.5@2x.png'
do
  size="${spec%%:*}"; name="${spec##*:}"
  sips -z "$size" "$size" "$APP/AppIcon1024x1024.png" --out "$APP/$name" >/dev/null
done

# engine
chmod +x "$ROOT/distribution/ios/compile.sh"
( cd "$ROOT" && ./distribution/ios/compile.sh )
DYLIB=""
for c in \
  "$ROOT/src/Ryujinx.Headless.SDL2/bin/Release/net8.0/ios-arm64/publish/Ryujinx.Headless.SDL2.dylib" \
  "$ROOT/src/Ryujinx.Headless.SDL2/bin/Release/net8.0/ios-arm64/native/Ryujinx.Headless.SDL2.dylib" \
  "$ROOT/src/MeloNX/MeloNX/Dependencies/Dynamic Libraries/Ryujinx.Headless.SDL2.dylib"
do
  [[ -f "$c" ]] && DYLIB="$c" && break
done
test -n "$DYLIB"
cp -f "$DYLIB" "$FW/Ryujinx.Headless.SDL2.dylib"

# HelionBridge.framework
xcrun --sdk iphoneos clang -arch "$IDENT_ARM" -miphoneos-version-min="$MIN" -isysroot "$SDK" \
  -dynamiclib -install_name @rpath/HelionBridge.framework/HelionBridge \
  "$ROOT/host/HelionBridge.c" -o "$APP/HelionBridge.framework/HelionBridge"
cat > "$APP/HelionBridge.framework/Info.plist" <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>HelionBridge</string>
  <key>CFBundleIdentifier</key><string>com.maaazn.helion.bridge</string>
  <key>CFBundleName</key><string>HelionBridge</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>MinimumOSVersion</key><string>16.0</string>
</dict></plist>
PL
cp -R "$APP/HelionBridge.framework" "$FW/HelionBridge.framework"

# third-party from host/deps if present
if [[ -d "$ROOT/host/deps/XCFrameworks" ]]; then
  for f in SDL2 libavcodec libavutil libavformat libavfilter libswscale libswresample libSPIRV; do
    BIN="$ROOT/host/deps/XCFrameworks/${f}.xcframework/ios-arm64/${f}.framework"
    if [[ -d "$BIN" ]]; then cp -R "$BIN" "$FW/"; fi
  done
fi
if [[ -f "$ROOT/host/deps/libMoltenVK.dylib" ]]; then
  cp -f "$ROOT/host/deps/libMoltenVK.dylib" "$FW/"
fi

xcrun --sdk iphoneos clang -arch "$IDENT_ARM" -miphoneos-version-min="$MIN" -isysroot "$SDK" \
  -fobjc-arc \
  -framework Foundation -framework UIKit -framework Metal -framework MetalKit \
  -framework UniformTypeIdentifiers -framework QuartzCore -framework CoreGraphics \
  -rpath @executable_path/Frameworks \
  "$ROOT/host/Helion.m" -o "$APP/Helion"

ls -lh "$APP/Helion" "$FW/Ryujinx.Headless.SDL2.dylib"
mkdir -p "$DIST"
( cd "$OUT" && zip -r -y "$DIST/Helion.ipa" Payload )
ls -lh "$DIST/Helion.ipa"
