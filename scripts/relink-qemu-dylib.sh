#!/bin/bash
# Relink qemu-system using meson's proven link line (all symbols, no dynamic_lookup).
set -euo pipefail
OUT="${1:?qemu-ios dir}"
BDIR="$OUT/src-qemu/build"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PY="$ROOT/scripts/link-qemu-inprocess.py"
if [[ ! -d "$BDIR" ]]; then
  echo "RELIRK_NO_BUILDDIR"; exit 0
fi
python3 "$PY" "$BDIR" "$OUT/libqemu-system-x86_64.dylib" dylib || echo "relink_x86_fail"
# arm uses a different target name; x86 is the product engine
ls -lh "$OUT"/libqemu-system-*.dylib 2>/dev/null || true
file "$OUT"/libqemu-system-x86_64.dylib 2>/dev/null || true
