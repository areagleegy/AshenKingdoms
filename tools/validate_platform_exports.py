#!/usr/bin/env python3
"""Structural smoke validation for exported AshenKingdoms platform artifacts.

This validates artifact structure and architecture metadata without claiming that
an executable has been launched on its target OS or device.
"""
from __future__ import annotations

import argparse
import struct
import sys
import zipfile
from pathlib import Path
from typing import Callable


class ArtifactValidationError(RuntimeError):
    """Raised when a platform export is missing required structure."""


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ArtifactValidationError(message)


def _zip_entries(path: Path) -> list[str]:
    _require(path.is_file(), f"Expected ZIP archive at: {path}")
    _require(zipfile.is_zipfile(path), f"Not a valid ZIP archive: {path}")
    try:
        with zipfile.ZipFile(path) as archive:
            broken_member = archive.testzip()
            _require(broken_member is None, f"Corrupt ZIP member: {broken_member}")
            return archive.namelist()
    except (OSError, zipfile.BadZipFile) as exc:
        raise ArtifactValidationError(f"Unable to inspect ZIP archive {path}: {exc}") from exc


def validate_web(path: Path) -> str:
    root = path if path.is_dir() else path.parent
    index_file = root / "index.html" if path.is_dir() else path
    _require(index_file.is_file() and index_file.stat().st_size > 0,
             f"Web export is missing a non-empty index.html: {index_file}")
    files = [item for item in root.rglob("*") if item.is_file()]
    _require(any(item.suffix.lower() == ".wasm" and item.stat().st_size > 0 for item in files),
             f"Web export is missing the non-empty WebAssembly engine binary: {root}")
    _require(any(item.suffix.lower() == ".pck" and item.stat().st_size > 0 for item in files),
             f"Web export is missing the non-empty Godot PCK: {root}")
    return f"Web structure OK: {len(files)} files"


def validate_windows(path: Path) -> str:
    _require(path.is_file() and path.stat().st_size >= 64,
             f"Windows export is missing or too small: {path}")
    with path.open("rb") as stream:
        header = stream.read(64)
        _require(header[:2] == b"MZ", "Windows artifact has no DOS MZ header")
        pe_offset = struct.unpack_from("<I", header, 0x3C)[0]
        _require(pe_offset >= 64 and pe_offset + 4 <= path.stat().st_size,
                 "Windows artifact has an invalid PE header offset")
        stream.seek(pe_offset)
        signature = stream.read(4)
    _require(signature == b"PE\0\0", "Windows artifact has no valid PE signature")
    return f"Windows PE structure OK: {path.stat().st_size} bytes"


def validate_linux(path: Path) -> str:
    _require(path.is_file() and path.stat().st_size >= 20,
             f"Linux export is missing or too small: {path}")
    with path.open("rb") as stream:
        header = stream.read(20)
    _require(header[:4] == b"\x7fELF", "Linux artifact has no ELF signature")
    _require(header[4] == 2, "Linux artifact is not a 64-bit ELF binary")
    _require(header[5] == 1, "Linux artifact is not a little-endian ELF binary")
    machine = struct.unpack_from("<H", header, 18)[0]
    _require(machine == 62, f"Linux artifact is not x86_64 (ELF e_machine={machine})")
    return f"Linux ELF x86_64 structure OK: {path.stat().st_size} bytes"


def validate_macos(path: Path) -> str:
    entries = _zip_entries(path)
    _require(any(name.endswith(".app/Contents/Info.plist") for name in entries),
             "macOS ZIP does not contain an app bundle Info.plist")
    _require(any(".app/Contents/MacOS/" in name and not name.endswith("/")
                for name in entries),
             "macOS ZIP does not contain an app executable")
    return f"macOS app bundle ZIP OK: {len(entries)} entries"


def validate_android(path: Path) -> str:
    entries = _zip_entries(path)
    _require("AndroidManifest.xml" in entries,
             "Android APK is missing AndroidManifest.xml")
    _require(any(name.startswith("lib/arm64-v8a/") and name.endswith(".so")
                 for name in entries),
             "Android APK is missing ARM64 native libraries")
    return f"Android APK structure OK: {len(entries)} entries"


def validate_ios(path: Path) -> str:
    entries = _zip_entries(path)
    _require(any(name.endswith(".xcodeproj/project.pbxproj") for name in entries),
             "iOS ZIP does not contain an Xcode project (project.pbxproj)")
    _require(any(name.endswith(".xcframework/Info.plist") for name in entries),
             "iOS ZIP does not contain the embedded Godot XCFramework metadata")
    _require(not any(name.lower().endswith(".ipa") for name in entries),
             "Project-only iOS artifact unexpectedly contains an IPA")
    return f"iOS Xcode project ZIP OK: {len(entries)} entries; unsigned project-only export"


VALIDATORS: dict[str, Callable[[Path], str]] = {
    "web": validate_web,
    "windows": validate_windows,
    "linux": validate_linux,
    "macos": validate_macos,
    "android": validate_android,
    "ios": validate_ios,
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platform", choices=sorted(VALIDATORS))
    parser.add_argument("path", type=Path, help="Export file or Web export directory")
    args = parser.parse_args()

    try:
        message = VALIDATORS[args.platform](args.path)
    except (ArtifactValidationError, OSError, struct.error) as exc:
        print(f"[FAIL] {args.platform}: {exc}", file=sys.stderr)
        return 1
    print(f"[PASS] {message}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
