#!/bin/bash
# Build QEMU (GPL-2.0) + pixman + GLib for iphoneos.
# Named engines, never rebranded. Always emit QEMU-COPYING + qemu-build.log.
set -u
OUT="${1:-$PWD/qemu-ios}"
LOG="$OUT/qemu-build.log"
PREFIX="$OUT/prefix"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
MIN="${VZ_IPHONE_MIN_VERSION:-16.0}"
CC="$(xcrun --sdk iphoneos --find clang)"
AR="$(xcrun --sdk iphoneos --find ar)"
STRIP="$(xcrun --sdk iphoneos --find strip)"
IOSCFLAGS="-arch arm64 -isysroot $SDK -miphoneos-version-min=$MIN -fPIC"
NCPU="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

mkdir -p "$OUT" "$PREFIX"
: > "$LOG"
exec > >(tee -a "$LOG") 2>&1

echo "HELION QEMU iphoneos 0.1.0 (utmapp/qemu + OSX-KVM layout)"
echo "host=$(uname -a)"
echo "sdk=$SDK"
echo "date=$(date -u +%FT%TZ)"

cp "$(dirname "$0")/QEMU-COPYING" "$OUT/QEMU-COPYING"

command -v meson >/dev/null || brew install meson ninja pkg-config python3 || true
command -v meson >/dev/null || { echo "NO_MESON"; exit 0; }
HOST_PKG="$(command -v pkg-config)"

TOOLBIN="$OUT/ios-bin"
mkdir -p "$TOOLBIN"
cat > "$TOOLBIN/iphoneos-pkg-config" <<EOF
#!/bin/bash
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig"
export PKG_CONFIG_PATH="\$PKG_CONFIG_LIBDIR"
unset PKG_CONFIG_SYSROOT_DIR
exec "$HOST_PKG" "\$@"
EOF
chmod +x "$TOOLBIN/iphoneos-pkg-config"
cp "$TOOLBIN/iphoneos-pkg-config" "$TOOLBIN/iphoneos-pkgconfig"
cp "$TOOLBIN/iphoneos-pkg-config" "$TOOLBIN/pkg-config"

CROSS="$OUT/ios.cross"
cat > "$CROSS" <<EOF
[binaries]
c = ['$CC']
cpp = ['$(xcrun --sdk iphoneos --find clang++)']
objc = ['$CC']
ar = '$AR'
strip = '$STRIP'
pkg-config = ['$TOOLBIN/iphoneos-pkg-config']
pkgconfig = ['$TOOLBIN/iphoneos-pkg-config']

[host_machine]
system = 'darwin'
subsystem = 'ios'
kernel = 'xnu'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[properties]
needs_exe_wrapper = true

[built-in options]
c_args = ['-arch', 'arm64', '-isysroot', '$SDK', '-miphoneos-version-min=$MIN', '-fPIC']
cpp_args = ['-arch', 'arm64', '-isysroot', '$SDK', '-miphoneos-version-min=$MIN', '-fPIC']
objc_args = ['-arch', 'arm64', '-isysroot', '$SDK', '-miphoneos-version-min=$MIN', '-fPIC']
c_link_args = ['-arch', 'arm64', '-isysroot', '$SDK', '-miphoneos-version-min=$MIN']
cpp_link_args = ['-arch', 'arm64', '-isysroot', '$SDK', '-miphoneos-version-min=$MIN']
default_library = 'static'
EOF

export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig"
export PKG_CONFIG_PATH="$PKG_CONFIG_LIBDIR"
export PKG_CONFIG_SYSROOT_DIR=""
export PKG_CONFIG="$TOOLBIN/iphoneos-pkg-config"
export PATH="$TOOLBIN:$PREFIX/bin:$PATH"

build_meson_proj() {
  local name="$1" url="$2" extra="$3"
  local src="$OUT/src-$name"
  echo "=== $name ==="
  rm -rf "$src"
  if ! git clone --depth 1 --filter=blob:none "$url" "$src"; then
    echo "${name}_CLONE_FAILED"
    return 1
  fi
  echo "${name}_sha=$(git -C "$src" rev-parse HEAD)"
  if [[ -f "$src/COPYING" ]]; then cp "$src/COPYING" "$OUT/${name}-COPYING"; fi
  if [[ -f "$src/COPYING.LIB" ]]; then cp "$src/COPYING.LIB" "$OUT/${name}-COPYING.LIB"; fi
  rm -rf "$src/mbuild"
  set +e
  meson setup "$src/mbuild" "$src" --prefix="$PREFIX" --cross-file="$CROSS" \
    --buildtype=release --default-library=static $extra
  local st=$?
  if [[ $st -ne 0 && -n "$extra" ]]; then
    echo "${name}_retry_without_extra"
    rm -rf "$src/mbuild"
    meson setup "$src/mbuild" "$src" --prefix="$PREFIX" --cross-file="$CROSS" \
      --buildtype=release --default-library=static
    st=$?
  fi
  echo "${name}_meson_setup=$st"
  if [[ $st -eq 0 ]]; then
    meson compile -C "$src/mbuild" -j "$NCPU"
    echo "${name}_compile=$?"
    meson install -C "$src/mbuild"
    echo "${name}_install=$?"
  fi
  set -e
  return 0
}

build_meson_proj pixman https://gitlab.freedesktop.org/pixman/pixman.git \
  "-Dtests=disabled"

build_meson_proj glib https://github.com/GNOME/glib.git \
  "-Dtests=false"

echo "prefix libs:"
ls -la "$PREFIX/lib" || true
ls "$PREFIX/lib/pkgconfig" || true
"$PKG_CONFIG" --exists pixman-1 && echo "pkg pixman-1 OK $("$PKG_CONFIG" --modversion pixman-1)" || echo "pkg pixman-1 MISSING"
"$PKG_CONFIG" --exists glib-2.0 && echo "pkg glib-2.0 OK $("$PKG_CONFIG" --modversion glib-2.0)" || echo "pkg glib-2.0 MISSING"

echo "=== qemu ==="
SRC="$OUT/src-qemu"
rm -rf "$SRC"
if ! git clone --depth 1 --filter=blob:none --recurse-submodules --shallow-submodules \
  --branch utm-edition https://github.com/utmapp/qemu.git "$SRC"; then
  echo "QEMU_UTM_FORK_CLONE_FAILED — falling back to qemu/qemu"
  if ! git clone --depth 1 --filter=blob:none --recurse-submodules --shallow-submodules \
    https://github.com/qemu/qemu.git "$SRC"; then
    echo "QEMU_CLONE_FAILED"
    exit 0
  fi
fi
echo "qemu_remote=$(git -C "$SRC" remote get-url origin)"
echo "qemu_sha=$(git -C "$SRC" rev-parse HEAD)"
echo "qemu_describe=$(git -C "$SRC" describe --always --tags)"
if [[ -f "$SRC/COPYING" ]]; then cp "$SRC/COPYING" "$OUT/QEMU-COPYING"; fi

# iPhone SDK marks pthread_jit_write_protect_np unavailable. Stub the Darwin
# helper only; TCG still needs StikDebug MAP_JIT at runtime.
python3 - "$SRC/include/qemu/osdep.h" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
t = p.read_text()
if "VELORA_IOS_JIT_WP" not in t:
    for val, repl in (
        ("true", "((void)0); /* VELORA_IOS_JIT_WP */"),
        ("false", "((void)0); /* VELORA_IOS_JIT_WP */"),
    ):
        old = f"    pthread_jit_write_protect_np({val});"
        new = (
            f"#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE\n"
            f"    {repl}\n"
            f"#else\n"
            f"    pthread_jit_write_protect_np({val});\n"
            f"#endif"
        )
        t = t.replace(old, new)
    p.write_text(t)
    print("patched osdep.h JIT WP for iOS")
else:
    print("osdep.h already patched")
PY

python3 - "$SRC/block/file-posix.c" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
t = p.read_text()
if "VELORA_IOS_STATFS" not in t:
    t = (
        "#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE\n"
        "#include <sys/mount.h>\n"
        "#define VELORA_IOS_STATFS 1\n"
        "#endif\n"
        + t
    )
    p.write_text(t)
    print("patched file-posix.c statfs for iOS")
else:
    print("file-posix.c already patched")
PY



cat > "$TOOLBIN/iphoneos-gcc" <<EOF
#!/bin/bash
exec "$CC" $IOSCFLAGS "\$@"
EOF
cp "$TOOLBIN/iphoneos-gcc" "$TOOLBIN/iphoneos-cc"
cp "$TOOLBIN/iphoneos-gcc" "$TOOLBIN/iphoneos-clang"
cat > "$TOOLBIN/iphoneos-g++" <<EOF
#!/bin/bash
exec "$(xcrun --sdk iphoneos --find clang++)" $IOSCFLAGS "\$@"
EOF
cp "$TOOLBIN/iphoneos-g++" "$TOOLBIN/iphoneos-c++"
cat > "$TOOLBIN/iphoneos-ar" <<EOF
#!/bin/bash
exec "$AR" "\$@"
EOF
cat > "$TOOLBIN/iphoneos-strip" <<EOF
#!/bin/bash
exec "$STRIP" "\$@"
EOF
cat > "$TOOLBIN/iphoneos-ranlib" <<EOF
#!/bin/bash
exec "$(xcrun --sdk iphoneos --find ranlib)" "\$@"
EOF
NM_BIN="$(xcrun --sdk iphoneos --find nm 2>/dev/null || xcrun --find nm)"
cat > "$TOOLBIN/iphoneos-nm" <<EOF
#!/bin/bash
exec "$NM_BIN" "\$@"
EOF
OBJCOPY_BIN="$(xcrun --sdk iphoneos --find llvm-objcopy 2>/dev/null || command -v llvm-objcopy || true)"
if [[ -z "$OBJCOPY_BIN" ]]; then
  brew install llvm 2>/dev/null || true
  OBJCOPY_BIN="$(command -v llvm-objcopy || true)"
fi
if [[ -n "$OBJCOPY_BIN" ]]; then
  cat > "$TOOLBIN/iphoneos-objcopy" <<EOF
#!/bin/bash
exec "$OBJCOPY_BIN" "\$@"
EOF
else
  cat > "$TOOLBIN/iphoneos-objcopy" <<'EOF'
#!/bin/bash
echo "iphoneos-objcopy stub: $*" >&2
exit 0
EOF
fi
OBJDUMP_BIN="$(xcrun --sdk iphoneos --find objdump 2>/dev/null || xcrun --find objdump || true)"
cat > "$TOOLBIN/iphoneos-objdump" <<EOF
#!/bin/bash
exec "${OBJDUMP_BIN:-/usr/bin/otool}" "\$@"
EOF
chmod +x "$TOOLBIN"/iphoneos-*
echo "toolbin=$(ls "$TOOLBIN")"

patch_cross() {
  python3 - "$1" "$TOOLBIN/iphoneos-pkg-config" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
pkg = sys.argv[2]
if not p.exists():
    raise SystemExit(0)
t = p.read_text()
line = f"pkg-config = ['{pkg}']\n"
if "pkg-config" in t:
    import re
    t = re.sub(r"^pkg-config\s*=.*$", line.strip(), t, flags=re.M)
    if "pkgconfig =" not in t:
        t = t.replace("[binaries]", "[binaries]\n" + f"pkgconfig = ['{pkg}']")
else:
    if "[binaries]" in t:
        t = t.replace("[binaries]", "[binaries]\n" + line.strip() + "\n" + f"pkgconfig = ['{pkg}']")
    else:
        t = "[binaries]\n" + line + f"pkgconfig = ['{pkg}']\n" + t
if "needs_exe_wrapper" not in t:
    t += "\n[properties]\nneeds_exe_wrapper = true\n"
p.write_text(t)
print("patched", p)
PY
}

cd "$SRC"
set +e
./configure \
  --cross-prefix="$TOOLBIN/iphoneos-" \
  --cc="$TOOLBIN/iphoneos-clang" \
  --host-cc="$(command -v clang)" \
  --cpu=aarch64 \
  --target-list=aarch64-softmmu,x86_64-softmmu \
  --extra-cflags="$IOSCFLAGS" \
  --extra-ldflags="$IOSCFLAGS" \
  --prefix="$PREFIX" \
  --without-default-features \
  --enable-tcg \
  --enable-system \
  --disable-werror \
  --disable-cocoa \
  --disable-hvf \
  --disable-kvm \
  --disable-xen \
  --disable-user \
  --disable-bsd-user \
  --disable-docs \
  --disable-tools \
  --disable-guest-agent \
  --disable-sdl \
  --disable-gtk \
  --enable-vnc \
  --disable-vte \
  --disable-gnutls \
  --disable-nettle \
  --disable-capstone \
  --disable-libusb \
  --disable-curl \
  --disable-libnfs \
  --disable-slirp \
  --enable-fdt \
  --disable-vmnet \
  --disable-coreaudio \
  --disable-pvg \
  --enable-pixman \
  --with-coroutine=sigaltstack
echo "configure_exit=$?"

# Successful configure already has build.ninja. Do not patch the meson
# cross file (duplicate [properties] broke 8.9.9 after configure_exit=0).
if [[ ! -f "$SRC/build/build.ninja" ]]; then
  echo "configure produced no ninja; patch cross + fallback meson"
  for f in \
    "$SRC/config-meson.cross" \
    "$SRC/build/config-meson.cross" \
    "$SRC/build/meson-cross-file.txt"
  do
    [[ -f "$f" ]] && patch_cross "$f"
  done
  echo "retry meson after pkg-config patch"
  if [[ -d "$SRC/build" ]]; then
    meson setup --reconfigure "$SRC/build" --cross-file="$CROSS" || true
  fi
fi

if [[ ! -f "$SRC/build/build.ninja" ]]; then
  echo "fallback: clean meson setup with ios.cross"
  rm -rf "$SRC/build"
  meson setup "$SRC/build" "$SRC" \
    --prefix="$PREFIX" \
    --cross-file="$CROSS" \
    --buildtype=release \
    -Dwerror=false \
    -Ddocs=disabled \
    -Dtools=disabled \
    -Dguest_agent=disabled \
    -Dtcg=enabled \
    -Dcocoa=disabled \
    -Dhvf=disabled \
    -Dkvm=disabled \
    -Dfdt=internal \
    -Dslirp=disabled \
    -Dpixman=enabled \
    -Dgio=disabled \
    -Dvmnet=disabled \
    -Dcoreaudio=disabled \
    -Dpvg=disabled \
    -Dvnc=enabled \
    -Dsdl=disabled \
    -Dgtk=disabled \
    -Dcoroutine_backend=sigaltstack \
    -Ddefault_devices=false \
    -Dinstall_blobs=false
  echo "fallback_meson_setup=$?"
fi

if [[ -f "$SRC/build/build.ninja" ]]; then
  ninja -C "$SRC/build" qemu-system-aarch64 qemu-system-x86_64 -j "$NCPU" -k 20
  echo "ninja_exit=$?"
else
  echo "ninja_exit=no-builddir"
fi
set -e

BIN=""
for c in "$SRC/build/qemu-system-aarch64" "$PREFIX/bin/qemu-system-aarch64"; do
  [[ -f "$c" ]] && BIN="$c"
done
if [[ -n "$BIN" ]]; then
  file "$BIN" || true
  otool -hv "$BIN" 2>/dev/null | head -8 || true
  cp "$BIN" "$OUT/qemu-system-aarch64"
  chmod +x "$OUT/qemu-system-aarch64"
  echo "QEMU_BIN=$OUT/qemu-system-aarch64"
  ls -lh "$OUT/qemu-system-aarch64"
else
  echo "QEMU_BIN_MISSING"
fi
BIN64=""
for c in "$SRC/build/qemu-system-x86_64" "$PREFIX/bin/qemu-system-x86_64"; do
  [[ -f "$c" ]] && BIN64="$c"
done
if [[ -n "$BIN64" ]]; then
  cp "$BIN64" "$OUT/qemu-system-x86_64"
  chmod +x "$OUT/qemu-system-x86_64"
  echo "QEMU_X86=$OUT/qemu-system-x86_64"
  ls -lh "$OUT/qemu-system-x86_64"
else
  echo "QEMU_X86_MISSING"
fi

# UTM path: dylib + qemu_init in-process. iOS posix_spawn of MH_EXECUTE is EPERM.
relink_dylib() {
  local exe="$1" dest="$2"
  local bdir="$SRC/build"
  [[ -f "$bdir/$exe" ]] || return 0
  local cmd
  cmd=$(ninja -C "$bdir" -t commands "$exe" 2>/dev/null | tail -1 || true)
  if [[ -z "$cmd" ]]; then
    echo "RELIRK_NO_CMD $exe"
    return 0
  fi
  python3 - "$cmd" "$bdir" "$dest" <<'PY'
import os, shlex, subprocess, sys
cmd, bdir, dest = sys.argv[1], sys.argv[2], sys.argv[3]
parts = shlex.split(cmd)
out = []
i = 0
while i < len(parts):
    if parts[i] == "-o" and i + 1 < len(parts):
        out += ["-dynamiclib",
                "-install_name", "@executable_path/" + os.path.basename(dest),
                "-o", dest]
        i += 2
        continue
    out.append(parts[i])
    i += 1
print("relink", dest)
r = subprocess.run(out, cwd=bdir)
print("relink_exit", r.returncode, dest)
sys.exit(r.returncode)
PY
}

relink_dylib qemu-system-aarch64 "$OUT/libqemu-system-aarch64.dylib" || echo "relink_arm_fail"
relink_dylib qemu-system-x86_64 "$OUT/libqemu-system-x86_64.dylib" || echo "relink_x86_fail"
ls -lh "$OUT"/libqemu-system-*.dylib 2>/dev/null || true
file "$OUT"/libqemu-system-*.dylib 2>/dev/null || true

echo "=== OSX-KVM firmware (OpenCore/OVMF, not macOS) ==="
KVM="$OUT/src-osxkvm"
rm -rf "$KVM"
if git clone --depth 1 --filter=blob:none https://github.com/kholia/OSX-KVM.git "$KVM"; then
  mkdir -p "$OUT/osxkvm"
  cp "$KVM/README.md" "$OUT/osxkvm/OSX-KVM-README.md" 2>/dev/null || true
  find "$KVM" -iname 'OVMF*.fd' -exec cp {} "$OUT/osxkvm/" \;
  find "$KVM" -iname 'OpenCore*.qcow2' -exec cp {} "$OUT/osxkvm/" \;
  ls -lh "$OUT/osxkvm" || true
  echo "OSX_KVM_FW=ok"
else
  echo "OSX_KVM_CLONE_FAILED"
fi
echo "DONE"
exit 0
