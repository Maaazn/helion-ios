#!/bin/bash
set -euo pipefail
DEST="src/MeloNX/MeloNX/Dependencies/Dynamic Libraries/Ryujinx.Headless.SDL2.dylib"
dotnet restore
dotnet publish -c Release -r ios-arm64 -p:ExtraDefineConstants=DISABLE_UPDATER src/Ryujinx.Headless.SDL2 --self-contained true
SRC=""
for c in \
  src/Ryujinx.Headless.SDL2/bin/Release/net8.0/ios-arm64/publish/Ryujinx.Headless.SDL2.dylib \
  src/Ryujinx.Headless.SDL2/bin/Release/net8.0/ios-arm64/native/Ryujinx.Headless.SDL2.dylib
do
  if [[ -f "$c" ]]; then SRC="$c"; break; fi
done
test -n "$SRC"
mkdir -p "$(dirname "$DEST")"
cp -f "$SRC" "$DEST"
# overwrite git-lfs stubs with real Mach-O from xcframeworks
DL="src/MeloNX/MeloNX/Dependencies/Dynamic Libraries"
XC="src/MeloNX/MeloNX/Dependencies/XCFrameworks"
cp -f "$XC/libavcodec.xcframework/ios-arm64/libavcodec.framework/libavcodec" "$DL/libavcodec.dylib"
cp -f "$XC/libavutil.xcframework/ios-arm64/libavutil.framework/libavutil" "$DL/libavutil.dylib"
if [[ -f "$DL/libMoltenVK.dylib" ]] && grep -q 'git-lfs' "$DL/libMoltenVK.dylib" 2>/dev/null; then
  echo "MoltenVK is still an LFS pointer" >&2
  exit 1
fi
ls -lh "$DEST" "$DL"/*.dylib
