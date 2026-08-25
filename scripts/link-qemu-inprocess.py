#!/usr/bin/env python3
"""Turn meson's qemu-system-x86_64 link line into:
  1) a dylib (optional)
  2) Helion executable with QEMU objects (no dlopen)
"""
import os, re, shlex, subprocess, sys
from pathlib import Path

def ninja_link(bdir: Path, target: str) -> list[str]:
    r = subprocess.run(
        ["ninja", "-C", str(bdir), "-t", "commands", target],
        capture_output=True, text=True)
    lines = [l.strip() for l in r.stdout.splitlines() if l.strip()]
    if not lines:
        print("NO_NINJA_COMMAND", target, r.stderr[-400:] if r.stderr else "")
        return []
    cmd = lines[-1]
    if cmd.startswith("PATH=") or cmd.startswith("env "):
        # drop env prefix: PATH=... cmd
        cmd = re.sub(r"^[A-Za-z0-9_]+=\S+\s+", "", cmd)
        if cmd.startswith("env "):
            parts = shlex.split(cmd)
            while parts and (parts[0] == "env" or "=" in parts[0]):
                parts.pop(0)
            return parts
    return shlex.split(cmd)

def is_main_obj(path: str) -> bool:
    if not path.endswith(".o") or not os.path.isfile(path):
        return False
    base = os.path.basename(path)
    if base in ("main.c.o", "system_main.c.o") or base.endswith("_main.c.o"):
        return True
    try:
        n = subprocess.check_output(["nm", "-g", path], text=True, stderr=subprocess.DEVNULL)
    except Exception:
        return False
    return bool(re.search(r"\sT _main$", n, re.M))

def drop_undefined_lookup(parts: list[str]) -> list[str]:
    out = []
    i = 0
    while i < len(parts):
        p = parts[i]
        if p in ("-undefined", "-Wl,-undefined"):
            i += 2
            continue
        if p.startswith("-Wl,-undefined,dynamic_lookup"):
            i += 1
            continue
        out.append(p)
        i += 1
    return out

def replace_output(parts: list[str], new_out: str, extra_before_out: list[str]) -> list[str]:
    out = []
    i = 0
    replaced = False
    while i < len(parts):
        if parts[i] == "-o" and i + 1 < len(parts):
            out += extra_before_out + ["-o", new_out]
            i += 2
            replaced = True
            continue
        out.append(parts[i])
        i += 1
    if not replaced:
        out = extra_before_out + ["-o", new_out] + out
    return out

def main():
    bdir = Path(sys.argv[1])
    dest = Path(sys.argv[2])
    mode = sys.argv[3]  # dylib | exe
    extra = sys.argv[4:]  # extra .o (Helion.o)
    parts = ninja_link(bdir, "qemu-system-x86_64")
    if not parts:
        sys.exit(2)
    parts = drop_undefined_lookup(parts)
    if mode == "dylib":
        parts = replace_output(
            parts, str(dest),
            ["-dynamiclib", "-install_name", "@executable_path/" + dest.name])
    else:
        filtered = []
        for p in parts:
            if p.endswith(".o") and is_main_obj(p if os.path.isabs(p) else str(bdir / p)):
                print("drop_qemu_main", p)
                continue
            filtered.append(p)
        parts = replace_output(filtered, str(dest), extra)
        parts += [
            "-framework", "Foundation",
            "-framework", "UIKit",
            "-framework", "UniformTypeIdentifiers",
            "-framework", "GameController",
            "-framework", "CoreGraphics",
            "-framework", "QuartzCore",
            "-lobjc",
        ]
    print("link", dest, "nparts", len(parts))
    r = subprocess.run(parts, cwd=str(bdir))
    print("link_exit", r.returncode, dest)
    if r.returncode == 0:
        subprocess.run(["file", str(dest)], check=False)
        subprocess.run(["ls", "-lh", str(dest)], check=False)
    sys.exit(r.returncode)

if __name__ == "__main__":
    main()
