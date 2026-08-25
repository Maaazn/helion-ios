#!/bin/bash
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
  if command -v file >/dev/null; then file "$p" | tee -a "$OUT"; fi
  if command -v otool >/dev/null; then
    otool -hv "$p" 2>/dev/null | tee -a "$OUT" || true
    local hdr
    hdr=$(otool -hv "$p" 2>/dev/null || true)
    echo "$hdr" | grep -q ARM64 || fail "$name not ARM64"
    echo "$hdr" | grep -qE 'EXECUTE|DYLIB' || fail "$name not MH_EXECUTE/DYLIB"
  fi
  echo "PROOF_OK $name" | tee -a "$OUT"
}

FW="$DIR/Frameworks/qemu-x86_64-softmmu.framework/qemu-x86_64-softmmu"
prove_bin "$FW" qemu-x86_64-softmmu.framework 20000000
[[ -f "$DIR/bios/bios.bin" ]] || fail "bios.bin missing"
[[ -f "$DIR/bios/edk2-x86_64-code.fd" ]] || fail "edk2-x86_64-code.fd missing"
echo "PROOF_OK bios" | tee -a "$OUT"

if [[ -n "$APP" ]]; then
  echo "== Helion.app ==" | tee -a "$OUT"
  [[ -d "$APP" ]] || fail "Helion.app missing"
  prove_bin "$APP/Helion" Helion 20000
  FAPP="$APP/Frameworks/qemu-x86_64-softmmu.framework/qemu-x86_64-softmmu"
  prove_bin "$FAPP" app-qemu-framework 20000000
  [[ -f "$APP/qemu/bios.bin" ]] || fail "app bios.bin missing"
  [[ -f "$APP/qemu/edk2-x86_64-code.fd" ]] || fail "app edk2 missing"
  echo "PROOF_OK app" | tee -a "$OUT"
fi

echo "PROOF_OK all" | tee -a "$OUT"
