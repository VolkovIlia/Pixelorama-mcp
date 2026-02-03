#!/usr/bin/env python3
import os
import pathlib
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent
SRC = ROOT / "PixeloramaMCP"
DIST = ROOT / "dist"
DIST.mkdir(parents=True, exist_ok=True)

out_path = DIST / "PixeloramaMCP.zip"

with zipfile.ZipFile(out_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for path in SRC.rglob("*"):
        if path.is_dir():
            continue
        arcname = path.relative_to(SRC)
        zf.write(path, arcname.as_posix())

print(out_path)
