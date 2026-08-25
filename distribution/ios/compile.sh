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
ls -lh "$DEST"
