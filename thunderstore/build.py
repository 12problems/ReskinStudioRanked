"""Builds the Thunderstore package: dist/<name>-<version>.zip

Run from anywhere:  python thunderstore/build.py

The zip has the files at its ROOT (Thunderstore requires that). It carries only
what the mod needs at runtime plus Thunderstore's own files; repo-only files
(positions.json, MALVERK_IMPORT.md, tools/, .gitignore) are left out. Text files
are written with LF line endings so the package is identical on every machine.
"""
import json
import re
import struct
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TS = ROOT / "thunderstore"

# (source, name inside the zip)
FILES = [
    (TS / "manifest.json", "manifest.json"),
    (TS / "README.md", "README.md"),
    (TS / "CHANGELOG.md", "CHANGELOG.md"),
    (TS / "icon.png", "icon.png"),
    (ROOT / "ReskinStudioRanked.json", "ReskinStudioRanked.json"),
    (ROOT / "main.lua", "main.lua"),
    (ROOT / "FORMAT.md", "FORMAT.md"),
]
TEXT = {".json", ".md", ".lua"}


def fail(msg):
    sys.exit(f"build failed: {msg}")


def main():
    for src, _ in FILES:
        if not src.is_file():
            fail(f"missing {src.relative_to(ROOT)}")

    manifest = json.loads((TS / "manifest.json").read_text(encoding="utf-8"))
    meta = json.loads((ROOT / "ReskinStudioRanked.json").read_text(encoding="utf-8"))

    name = manifest.get("name", "")
    if not re.fullmatch(r"[A-Za-z0-9_]{1,128}", name):
        fail("manifest name may only contain a-z A-Z 0-9 _ (max 128)")
    if not re.fullmatch(r"\d+\.\d+\.\d+", manifest.get("version_number", "")):
        fail("version_number must be Major.Minor.Patch")
    if len(manifest.get("description", "")) > 250:
        fail("description is longer than 250 characters")
    if "website_url" not in manifest:
        fail('website_url is required (use "" for none)')
    for dep in manifest.get("dependencies", []):
        if not re.fullmatch(r"[A-Za-z0-9_]+-[A-Za-z0-9_]+-\d+\.\d+\.\d+", dep):
            fail(f"dependency '{dep}' must look like Team-Package-1.2.3")
    if manifest["version_number"] != meta.get("version"):
        fail(
            f"manifest version {manifest['version_number']} != "
            f"ReskinStudioRanked.json version {meta.get('version')}"
        )
    icon = (TS / "icon.png").read_bytes()
    if icon[:8] != b"\x89PNG\r\n\x1a\n" or struct.unpack(">II", icon[16:24]) != (256, 256):
        fail("icon.png must be a 256x256 PNG")

    out_dir = ROOT / "dist"
    out_dir.mkdir(exist_ok=True)
    out = out_dir / f"{name}-{manifest['version_number']}.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for src, arc in FILES:
            data = src.read_bytes()
            if src.suffix in TEXT:
                data = data.replace(b"\r\n", b"\n")
            z.writestr(arc, data)
    print(f"wrote {out.relative_to(ROOT)} ({out.stat().st_size} bytes)")
    with zipfile.ZipFile(out) as z:
        for info in z.infolist():
            print(f"  {info.filename}  {info.file_size}")


main()
