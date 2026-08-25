#!/bin/bash
set -euo pipefail
APP="${1:-}"
OUT="${2:-./PROOF.txt}"
fail() { echo "PROOF_FAIL $*" | tee -a "$OUT"; exit 1; }
: > "$OUT"
echo "HELION SWITCH PROOF $(date -u +%FT%TZ)" | tee -a "$OUT"
[[ -d "$APP" ]] || fail "Helion.app missing"
BIN="$APP/Helion"
[[ -f "$BIN" ]] || fail "Helion binary missing"
sz=$(stat -f%z "$BIN" 2>/dev/null || stat -c%s "$BIN")
echo "size=$sz" | tee -a "$OUT"
[[ "$sz" -gt 20000 ]] || fail "binary too small"
otool -hv "$BIN" 2>/dev/null | tee -a "$OUT" || true
echo "PROOF_OK all" | tee -a "$OUT"
