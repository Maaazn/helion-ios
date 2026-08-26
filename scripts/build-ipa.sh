#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
MIN=16.0
VER="${HELION_VERSION:-2.1.0}"
OUT="${HELION_BUILD_ROOT:-$ROOT/build}/ipa"
APP="$OUT/Payload/Helion.app"
DIST="${HELION_DIST:-$ROOT/dist}"

rm -rf "$OUT"
mkdir -p "$APP" "$DIST"

cat > "$APP/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Helion</string>
  <key>CFBundleIdentifier</key><string>com.maaazn.helion</string>
  <key>CFBundleName</key><string>Puck</string>
  <key>CFBundleDisplayName</key><string>Puck</string>
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
        <key>UISceneDelegateClassName</key><string>PuckScene</string>
      </dict></array>
    </dict>
  </dict>
  <key>UISupportedInterfaceOrientations</key>
  <array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
  </array>
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
  <key>UIStatusBarHidden</key><true/>
  <key>UIViewControllerBasedStatusBarAppearance</key><true/>
  <key>UIRequiresFullScreen</key><true/>
  <key>UIStatusBarStyle</key><string>UIStatusBarStyleLightContent</string>
  <key>UIApplicationSupportsIndirectInputEvents</key><true/>
  <key>UISupportsDocumentBrowser</key><false/>
  <key>LSSupportsOpeningDocumentsInPlace</key><true/>
  <key>LSApplicationQueriesSchemes</key>
  <array>
    <string>prefs</string>
    <string>App-prefs</string>
    <string>app-prefs</string>
  </array>
  <key>NSPhotoLibraryUsageDescription</key><string>Pick a cursor image or wallpaper.</string>
  <key>NSLocalNetworkUsageDescription</key><string>Puck advertises itself as a pairable computer so iOS 27 Developer Mode can pair with it.</string>
  <key>NSBonjourServices</key>
  <array>
    <string>_remotepairing-pairable-host._tcp</string>
    <string>_remotepairing-manual-pairing._tcp</string>
    <string>_puckprobe._tcp</string>
  </array>
  <key>UIBackgroundModes</key>
  <array>
    <string>audio</string>
  </array>
  <key>NSMicrophoneUsageDescription</key><string>Not used. Background audio keeps pairing alive while you enter the PIN in Settings.</string>
  <key>UTImportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key><string>com.maaazn.helion.cur</string>
      <key>UTTypeDescription</key><string>Windows Cursor</string>
      <key>UTTypeConformsTo</key><array><string>public.data</string></array>
      <key>UTTypeTagSpecification</key>
      <dict>
        <key>public.filename-extension</key><array><string>cur</string><string>ani</string></array>
      </dict>
    </dict>
  </array>
</dict></plist>
PLIST

python3 - "$APP/AppIcon1024x1024.png" <<'PY'
import struct, zlib, math, sys
w=h=1024
def chunk(tag, data):
    return struct.pack('>I', len(data))+tag+data+struct.pack('>I', zlib.crc32(tag+data)&0xffffffff)
rows=[]
for y in range(h):
    row=bytearray([0])
    for x in range(w):
        # ink field
        R,G,B=10,12,16
        # mouse body (capsule)
        mx,my=512,430
        dx,dy=(x-mx)/180.0,(y-my)/260.0
        body=dx*dx+dy*dy
        if body<1:
            shade=int(28+40*(1-body))
            R,G,B=shade, shade+4, shade+10
        # left/right buttons split
        if body<0.72 and y<430:
            if x<512: R,G,B=36,40,50
            else: R,G,B=42,46,58
        # scroll wheel
        if abs(x-512)<18 and abs(y-400)<36:
            R,G,B=18,22,28
        # mint puck pointer (the missing iPhone cursor)
        px,py=700,300
        pr=math.hypot(x-px,y-py)
        if pr<78:
            t=max(0,1-pr/78)
            glow=int(80*t)
            R=min(255,R+int(120*t)); G=min(255,G+int(255*t)); B=min(255,B+int(200*t))
            if 52<pr<64:
                R,G,B=125,255,204
            if pr<22:
                R,G,B=240,255,248
        # beam from mouse to puck
        # line from (560,360) to (700,300)
        ax,ay,bx,by=560,360,700,300
        vx,vy=bx-ax,by-ay
        llen=math.hypot(vx,vy) or 1
        t=((x-ax)*vx+(y-ay)*vy)/(llen*llen)
        if 0<=t<=1:
            qx,qy=ax+t*vx,ay+t*vy
            d=math.hypot(x-qx,y-qy)
            if d<6:
                R=min(255,R+90); G=min(255,G+160); B=min(255,B+120)
        row += bytes([R,G,B])
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

python3 - "$APP/silence.wav" <<'PY'
import struct, sys
# 1s mono 8kHz silence WAV so pairing can stay alive in Settings
n, rate = 8000, 8000
data = b"\x00\x00" * n
hdr = b"RIFF" + struct.pack("<I", 36+len(data)) + b"WAVEfmt " + struct.pack("<IHHIIHH", 16,1,1,rate,rate*2,2,16) + b"data" + struct.pack("<I", len(data))
open(sys.argv[1],"wb").write(hdr+data)
PY

PAIR_CFLAGS=""
PAIR_LIBS=""
if command -v rustup >/dev/null 2>&1 || [ -x "$HOME/.cargo/bin/cargo" ]; then
  export PATH="$HOME/.cargo/bin:$PATH"
fi
if command -v cargo >/dev/null 2>&1; then
  echo "building puck_pair rust staticlib"
  export IPHONEOS_DEPLOYMENT_TARGET="$MIN"
  export SDKROOT="$SDK"
  if ( cd "$ROOT/pair" && cargo build --release --target aarch64-apple-ios ); then
    PAIR_CFLAGS="-DPUCK_PAIR_LIB -I$ROOT/pair/include"
    PAIR_LIBS="-L$ROOT/pair/target/aarch64-apple-ios/release -lpuck_pair -lc++"
    echo "puck_pair linked"
  else
    echo "puck_pair rust build failed — ObjC Bonjour host only"
  fi
else
  echo "cargo missing — ObjC Bonjour host only"
fi

xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min="$MIN" -isysroot "$SDK" \
  -fobjc-arc \
  $PAIR_CFLAGS \
  -framework Foundation -framework UIKit -framework GameController \
  -framework CoreGraphics -framework QuartzCore -framework UniformTypeIdentifiers \
  -framework WebKit -framework AVFoundation -framework CFNetwork \
  "$ROOT/Puck.m" "$ROOT/PuckPair.m" \
  $PAIR_LIBS \
  -o "$APP/Helion"

ls -lh "$APP/Helion"
( cd "$OUT" && zip -r -y "$DIST/Helion.ipa" Payload )
ls -lh "$DIST/Helion.ipa"
