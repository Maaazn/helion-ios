#!/usr/bin/env python3
"""Copy UTM's working iOS QEMU x86_64 stack (GPL-2.0) into Helion.

Source of the binaries: utmapp/UTM iOS IPA (QEMU + UTM patches).
Corresponding source: https://github.com/utmapp/qemu
We do not copy UTM's UI.
"""
import os, sys, struct, shutil
from pathlib import Path

NEEDED = [
    "bios.bin", "bios-256k.bin", "bios-microvm.bin",
    "vgabios.bin", "vgabios-stdvga.bin", "vgabios-virtio.bin",
    "vgabios-qxl.bin", "vgabios-ramfb.bin", "kvmvapic.bin",
    "edk2-x86_64-code.fd", "edk2-x86_64-secure-code.fd",
    "edk2-i386-vars.fd", "edk2-i386-code.fd",
    "efi-virtio.rom", "efi-e1000.rom",
]


def macho_dylibs(path: Path):
    data = path.read_bytes()
    if data[:4] != b"\xcf\xfa\xed\xfe":
        return []
    ncmds = struct.unpack_from("<I", data, 16)[0]
    off = 32
    out = []
    for _ in range(ncmds):
        if off + 8 > len(data):
            break
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        if cmd in (0x0C, 0x18, 0x80000018):
            stroff = struct.unpack_from("<I", data, off + 8)[0]
            s = data[off + stroff : off + cmdsize].split(b"\x00", 1)[0].decode("utf-8", "replace")
            out.append(s)
        off += cmdsize
    return out


def fw_name(load: str):
    # @rpath/pixman-1.0.framework/pixman-1.0
    if not load.startswith("@rpath/"):
        return None
    rest = load[len("@rpath/") :]
    return rest.split("/")[0]


def copy_fw(src_fw_dir: Path, dst_fw_dir: Path, name: str):
    src = src_fw_dir / name
    dst = dst_fw_dir / name
    if not src.exists():
        print("MISS", name)
        return None
    if dst.exists():
        return dst
    shutil.copytree(src, dst, dirs_exist_ok=True)
    print("COPY", name)
    return dst


def binary_in_fw(fw: Path):
    # Prefer executable matching framework name
    cands = [p for p in fw.rglob("*") if p.is_file() and p.stat().st_size > 10000]
    for p in cands:
        if p.name == fw.name.replace(".framework", "") or p.parent == fw:
            if p.suffix not in {".plist", ".h"}:
                return p
    cands.sort(key=lambda p: -p.stat().st_size)
    return cands[0] if cands else None


def main():
    utm = Path(sys.argv[1])
    out = Path(sys.argv[2])
    src_fw = utm / "Frameworks"
    dst_fw = out / "Frameworks"
    dst_bios = out / "bios"
    dst_fw.mkdir(parents=True, exist_ok=True)
    dst_bios.mkdir(parents=True, exist_ok=True)

    seed = "qemu-x86_64-softmmu.framework"
    queue = [seed]
    seen = set()
    while queue:
        name = queue.pop(0)
        if name in seen:
            continue
        seen.add(name)
        copied = copy_fw(src_fw, dst_fw, name)
        if not copied:
            continue
        binp = binary_in_fw(copied)
        if not binp:
            continue
        for load in macho_dylibs(binp):
            n = fw_name(load)
            if n and n not in seen:
                queue.append(n)

    src_qemu = utm / "qemu"
    for f in NEEDED:
        p = src_qemu / f
        if p.is_file():
            shutil.copy2(p, dst_bios / f)
            print("BIOS", f, p.stat().st_size)
    # keymaps optional
    km = src_qemu / "keymaps"
    if km.is_dir():
        shutil.copytree(km, dst_bios / "keymaps", dirs_exist_ok=True)

    notice = out / "QEMU-COPYING"
    for cand in [utm / "qemu" / "edk2-licenses.txt", utm / "LICENSE.QEMU"]:
        if cand.is_file():
            shutil.copy2(cand, notice)
            break
    else:
        notice.write_text("QEMU GPL-2.0. Source: https://github.com/utmapp/qemu\n")

    x86 = dst_fw / seed / "qemu-x86_64-softmmu"
    print("FRAMEWORKS", len(list(dst_fw.iterdir())))
    print("X86", x86.exists(), x86.stat().st_size if x86.exists() else 0)
    if not x86.exists() or x86.stat().st_size < 5_000_000:
        sys.exit("vendor-utm-qemu: qemu-x86_64-softmmu missing")


if __name__ == "__main__":
    main()
