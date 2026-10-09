#!/usr/bin/env python3
"""Apply required engine integration patches without discarding local engine work."""
from pathlib import Path
import subprocess
import sys


def apply_patch(engine: Path, patch: Path) -> None:
    command = ["patch", "--silent", "--batch", "--fuzz=0", "-p1", "-i", str(patch.resolve())]
    # Reverse dry run also recognizes a previously patched tree.
    # --forward also disables patch's automatic fallback to the opposite direction.
    reverse = subprocess.run(command + ["--dry-run", "--reverse", "--forward"], cwd=engine, capture_output=True)
    if reverse.returncode == 0:
        print(f"Already applied: {patch.name}")
        return
    check = subprocess.run(command + ["--dry-run", "--forward"], cwd=engine, capture_output=True, text=True)
    if check.returncode:
        raise RuntimeError(f"Cannot apply {patch.name}; preserve and review the engine changes.\n{check.stdout}{check.stderr}")
    subprocess.run(command + ["--forward"], cwd=engine, check=True)
    print(f"Applied: {patch.name}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: apply-engine-patches.py /path/to/godot")
    root = Path(__file__).resolve().parents[2]
    apply_patch(Path(sys.argv[1]).resolve(), root / "patches/godot-ornament-hosting.patch")
