#!/bin/bash
# Gate: no IPA. Fail if the engine is not a real iphoneos Mach-O.
set -euo pipefail
DIR="${1:-}"
APP="${2:-}"
OUT="${3:-./PROOF.txt}"
: "${DIR:?qemu dir}"
fail() { echo "PROOF_FAIL $*" | tee -a "$OUT"; exit 1; }

: > "$OUT"
echo "HELION PROOF $(date -u +%FT%TZ)" | tee -a "$OUT"

prove_bin() {
  local p="$1" name="$2" min="${3:-5000000}"
  echo "== $name ==" | tee -a "$OUT"
  [[ -f "$p" ]] || fail "$name missing: $p"
  local sz
  sz=$(stat -f%z "$p" 2>/dev/null || stat -c%s "$p")
  echo "size=$sz min=$min" | tee -a "$OUT"
  [[ "$sz" -gt "$min" ]] || fail "$name too small ($sz)"
  chmod +x "$p" || true
  if command -v file >/dev/null; then
    file "$p" | tee -a "$OUT"
  fi
  if command -v otool >/dev/null; then
    otool -hv "$p" 2>/dev/null | tee -a "$OUT" || true
    local hdr
    hdr=$(otool -hv "$p" 2>/dev/null || true)
    echo "$hdr" | grep -q ARM64 || fail "$name not ARM64"
    echo "$hdr" | grep -qE 'EXECUTE|DYLIB' || fail "$name not MH_EXECUTE/DYLIB"
  fi
  if command -v vtool >/dev/null; then
    vtool -show-build "$p" 2>/dev/null | tee -a "$OUT" || true
    local plat
    plat=$(vtool -show-build "$p" 2>/dev/null || true)
    echo "$plat" | grep -Ei 'IOS|iOS|IPHONEOS' >/dev/null \
      || echo "WARN $name: no iOS platform string in vtool" | tee -a "$OUT"
  fi
  echo "PROOF_OK $name" | tee -a "$OUT"
}

prove_bin "$DIR/qemu-system-aarch64" qemu-system-aarch64
prove_bin "$DIR/qemu-system-x86_64" qemu-system-x86_64
# dylib optional when Helion is statically linked with QEMU

if [[ -n "$APP" ]]; then
  echo "== Helion.app ==" | tee -a "$OUT"
  [[ -d "$APP" ]] || fail "Helion.app missing"
  prove_bin "$APP/Helion" Helion 20000
  HELSZ=$(stat -f%z "$APP/Helion" 2>/dev/null || stat -c%s "$APP/Helion")
  if [[ "$HELSZ" -gt 5000000 ]]; then
    echo "PROOF_OK qemu-static-in-helion size=$HELSZ" | tee -a "$OUT"
  else
    [[ -f "$APP/libqemu-system-x86_64.dylib" ]] || fail "libqemu-system-x86_64.dylib not in app"
  fi
  [[ -f "$APP/QEMU-COPYING" ]] || fail "QEMU-COPYING missing"
  echo "PROOF_OK app" | tee -a "$OUT"
fi

echo "PROOF_OK all" | tee -a "$OUT"
