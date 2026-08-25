#!/bin/bash
# Relink qemu-system MH_EXECUTE → dylib for in-process qemu_init (iOS EPERM on posix_spawn).
set -euo pipefail
OUT="${1:?qemu-ios dir}"
SRC="$OUT/src-qemu"
BDIR="$SRC/build"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
MIN="${HELION_MIN_VERSION:-16.0}"
CC="$(xcrun --sdk iphoneos --find clang)"

relink() {
  local exe="$1" dest="$2"
  echo "relink $exe -> $dest"
  if [[ ! -d "$BDIR" ]]; then
    echo "RELIRK_NO_BUILDDIR"; return 1
  fi
  local list
  list=$(ninja -C "$BDIR" -t inputs "$exe" 2>/dev/null || true)
  if [[ -z "$list" ]]; then
    echo "RELIRK_NO_INPUTS $exe"
    ninja -C "$BDIR" -t targets 2>/dev/null | grep qemu-system | head || true
    return 1
  fi
  python3 - "$CC" "$SDK" "$MIN" "$BDIR" "$dest" "$OUT" <<'PY'
import os, subprocess, sys
cc, sdk, mn, bdir, dest, out = sys.argv[1:7]
raw = os.environ.get("NINJA_INPUTS", "")
# inputs via stdin
PY
  export NINJA_INPUTS="$list"
  python3 - "$CC" "$SDK" "$MIN" "$BDIR" "$dest" "$OUT" "$exe" <<'PY'
import os, subprocess, sys, pathlib
cc, sdk, mn, bdir, dest, out, exe = sys.argv[1:8]
lines = os.environ["NINJA_INPUTS"].splitlines()
files = []
for l in lines:
    l = l.strip()
    if not (l.endswith(".o") or l.endswith(".a")):
        continue
    p = l if os.path.isabs(l) else os.path.join(bdir, l)
    if os.path.isfile(p):
        files.append(p)
pref = pathlib.Path(out) / "prefix" / "lib"
if pref.is_dir():
    for a in pref.glob("*.a"):
        files.append(str(a))
print("nobj", len(files), dest)
cmd = [cc, "-dynamiclib", "-arch", "arm64", "-isysroot", sdk,
       f"-miphoneos-version-min={mn}",
       "-install_name", "@executable_path/" + os.path.basename(dest),
       "-o", dest] + files + ["-lz", "-liconv", "-framework", "Foundation",
       "-framework", "CoreFoundation", "-Wl,-undefined,dynamic_lookup"]
r = subprocess.run(cmd)
print("relink_exit", r.returncode, dest)
if r.returncode == 0:
    subprocess.run(["file", dest], check=False)
sys.exit(r.returncode)
PY
}

relink qemu-system-x86_64 "$OUT/libqemu-system-x86_64.dylib" || echo "relink_x86_fail"
relink qemu-system-aarch64 "$OUT/libqemu-system-aarch64.dylib" || echo "relink_arm_fail"
ls -lh "$OUT"/libqemu-system-*.dylib 2>/dev/null || true
