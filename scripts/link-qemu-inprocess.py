#!/usr/bin/env python3
"""Turn meson's qemu-system-x86_64 link line into a Helion exe or dylib."""
import os, re, shlex, subprocess, sys
from pathlib import Path

def ninja_link(bdir: Path, target: str) -> list[str]:
    r = subprocess.run(
        ["ninja", "-C", str(bdir), "-t", "commands", target],
        capture_output=True, text=True)
    raw = r.stdout
    Path("/tmp/ninja-commands.txt").write_text(raw[:8000] + "\n---stderr---\n" + (r.stderr or "")[:2000])
    print("ninja_commands_bytes", len(raw), "lines", len(raw.splitlines()))
    print("ninja_commands_tail", repr(raw[-500:]))
    lines = [l.strip() for l in raw.splitlines() if l.strip()]
    if not lines:
        return []
    cmd = lines[-1]
    while True:
        m = re.match(r"^[A-Za-z0-9_]+=\S+\s+(.*)$", cmd)
        if not m:
            break
        cmd = m.group(1)
    if cmd.startswith("env "):
        parts = shlex.split(cmd)
        while parts and (parts[0] == "env" or "=" in parts[0]):
            parts.pop(0)
        return parts
    return shlex.split(cmd)

def expand_rsp(parts: list[str], bdir: Path) -> list[str]:
    out = []
    for p in parts:
        if p.startswith("@") and not p.startswith("@rpath"):
            rsp = Path(p[1:])
            if not rsp.is_absolute():
                rsp = bdir / rsp
            if rsp.is_file():
                print("expand_rsp", rsp, "bytes", rsp.stat().st_size)
                out.extend(shlex.split(rsp.read_text()))
                continue
        out.append(p)
    return out

def is_main_obj(path: str) -> bool:
    if not path.endswith(".o"):
        return False
    if not os.path.isfile(path):
        return False
    base = os.path.basename(path)
    if "main.c.o" in base:
        return True
    try:
        n = subprocess.check_output(["nm", "-g", path], text=True, stderr=subprocess.DEVNULL)
    except Exception:
        return False
    return bool(re.search(r"\sT _main$", n, re.M))

def drop_undefined_lookup(parts: list[str]) -> list[str]:
    out, i = [], 0
    while i < len(parts):
        p = parts[i]
        if p in ("-undefined",) and i + 1 < len(parts):
            i += 2
            continue
        if "dynamic_lookup" in p:
            i += 1
            continue
        out.append(p)
        i += 1
    return out

def replace_output(parts: list[str], new_out: str) -> list[str]:
    out, i, replaced = [], 0, False
    while i < len(parts):
        if parts[i] == "-o" and i + 1 < len(parts):
            out += ["-o", new_out]
            i += 2
            replaced = True
            continue
        out.append(parts[i])
        i += 1
    if not replaced:
        out += ["-o", new_out]
    return out

def ensure_compiler(parts: list[str]) -> list[str]:
    if not parts:
        return parts
    head = os.path.basename(parts[0])
    if "clang" in head or head.endswith("ld") or head in ("cc", "c++"):
        return parts
    # ninja gave a script; keep it
    return parts

def main():
    bdir = Path(sys.argv[1])
    dest = Path(sys.argv[2])
    mode = sys.argv[3]
    extra = sys.argv[4:]
    parts = ninja_link(bdir, "qemu-system-x86_64")
    if not parts:
        print("NO_NINJA_COMMAND")
        sys.exit(2)
    parts = expand_rsp(parts, bdir)
    parts = drop_undefined_lookup(parts)
    parts = ensure_compiler(parts)
    print("nparts_expanded", len(parts), "head", parts[:8])
    if mode == "dylib":
        parts = replace_output(parts, str(dest))
        # insert -dynamiclib after compiler
        parts[1:1] = ["-dynamiclib", "-install_name", "@executable_path/" + dest.name]
    else:
        filtered = []
        for p in parts:
            cand = p if os.path.isabs(p) else str(bdir / p)
            if p.endswith(".o") and is_main_obj(cand):
                print("drop_qemu_main", p)
                continue
            filtered.append(p)
        parts = replace_output(filtered, str(dest))
        parts += extra
        parts += [
            "-framework", "Foundation", "-framework", "UIKit",
            "-framework", "UniformTypeIdentifiers", "-framework", "GameController",
            "-framework", "CoreGraphics", "-framework", "QuartzCore", "-lobjc",
        ]
    print("link", dest, "nparts", len(parts))
    dest.parent.mkdir(parents=True, exist_ok=True)
    r = subprocess.run(parts, cwd=str(bdir))
    print("link_exit", r.returncode, dest)
    if r.returncode == 0:
        subprocess.run(["file", str(dest)], check=False)
        subprocess.run(["ls", "-lh", str(dest)], check=False)
    sys.exit(r.returncode)

if __name__ == "__main__":
    main()
