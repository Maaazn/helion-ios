#!/bin/bash
set -euo pipefail
dotnet restore src/Ryujinx.Headless.SDL2/Ryujinx.Headless.SDL2.csproj
dotnet publish -c Release -r ios-arm64 -p:ExtraDefineConstants=DISABLE_UPDATER src/Ryujinx.Headless.SDL2 --self-contained true
ls -lh src/Ryujinx.Headless.SDL2/bin/Release/net8.0/ios-arm64/publish/Ryujinx.Headless.SDL2.dylib \
      src/Ryujinx.Headless.SDL2/bin/Release/net8.0/ios-arm64/native/Ryujinx.Headless.SDL2.dylib 2>/dev/null || true
