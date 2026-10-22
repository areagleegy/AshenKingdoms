"""Unit tests for structural platform export validation."""
from __future__ import annotations

import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

from tools.validate_platform_exports import (
    ArtifactValidationError,
    validate_android,
    validate_ios,
    validate_linux,
    validate_macos,
    validate_web,
    validate_windows,
)


class PlatformExportValidatorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def _write_zip(self, name: str, entries: dict[str, bytes]) -> Path:
        target = self.root / name
        with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for entry_name, payload in entries.items():
                archive.writestr(entry_name, payload)
        return target

    def test_web_requires_html_wasm_and_pck(self) -> None:
        web = self.root / "web"
        web.mkdir()
        (web / "index.html").write_text("<html></html>", encoding="utf-8")
        (web / "game.wasm").write_bytes(b"wasm")
        (web / "game.pck").write_bytes(b"pck")
        self.assertIn("Web structure OK", validate_web(web))

    def test_web_rejects_missing_wasm(self) -> None:
        web = self.root / "web"
        web.mkdir()
        (web / "index.html").write_text("<html></html>", encoding="utf-8")
        (web / "game.pck").write_bytes(b"pck")
        with self.assertRaisesRegex(ArtifactValidationError, "WebAssembly"):
            validate_web(web)

    def test_windows_requires_valid_pe_signature(self) -> None:
        binary = bytearray(128)
        binary[:2] = b"MZ"
        struct.pack_into("<I", binary, 0x3C, 64)
        binary[64:68] = b"PE\0\0"
        path = self.root / "game.exe"
        path.write_bytes(binary)
        self.assertIn("Windows PE structure OK", validate_windows(path))

    def test_windows_rejects_non_pe_file(self) -> None:
        path = self.root / "game.exe"
        path.write_bytes(b"not an executable" + bytes(80))
        with self.assertRaisesRegex(ArtifactValidationError, "MZ"):
            validate_windows(path)

    def test_linux_requires_64bit_x86_64_elf(self) -> None:
        header = bytearray(64)
        header[:4] = b"\x7fELF"
        header[4] = 2
        header[5] = 1
        struct.pack_into("<H", header, 18, 62)
        path = self.root / "game.x86_64"
        path.write_bytes(header)
        self.assertIn("ELF x86_64", validate_linux(path))

    def test_linux_rejects_wrong_architecture(self) -> None:
        header = bytearray(64)
        header[:4] = b"\x7fELF"
        header[4] = 2
        header[5] = 1
        struct.pack_into("<H", header, 18, 183)
        path = self.root / "game"
        path.write_bytes(header)
        with self.assertRaisesRegex(ArtifactValidationError, "not x86_64"):
            validate_linux(path)

    def test_macos_requires_app_bundle_metadata_and_executable(self) -> None:
        path = self._write_zip("game-macos.zip", {
            "AshenKingdoms.app/Contents/Info.plist": b"<plist/>",
            "AshenKingdoms.app/Contents/MacOS/AshenKingdoms": b"binary",
        })
        self.assertIn("app bundle ZIP OK", validate_macos(path))

    def test_android_requires_manifest_and_arm64_library(self) -> None:
        path = self._write_zip("game.apk", {
            "AndroidManifest.xml": b"binary-xml",
            "lib/arm64-v8a/libgodot_android.so": b"native",
        })
        self.assertIn("Android APK structure OK", validate_android(path))

    def test_android_rejects_missing_arm64_library(self) -> None:
        path = self._write_zip("game.apk", {
            "AndroidManifest.xml": b"binary-xml",
            "lib/x86_64/libgodot_android.so": b"native",
        })
        with self.assertRaisesRegex(ArtifactValidationError, "ARM64"):
            validate_android(path)

    def test_ios_requires_xcode_project_and_engine_framework(self) -> None:
        path = self._write_zip("game-ios.zip", {
            "AshenKingdoms.xcodeproj/project.pbxproj": b"pbx",
            "AshenKingdoms.xcframework/Info.plist": b"<plist/>",
        })
        self.assertIn("unsigned project-only export", validate_ios(path))

    def test_ios_rejects_zip_without_xcode_project(self) -> None:
        path = self._write_zip("game-ios.zip", {
            "AshenKingdoms.xcframework/Info.plist": b"<plist/>",
        })
        with self.assertRaisesRegex(ArtifactValidationError, "Xcode project"):
            validate_ios(path)

    def test_corrupt_zip_is_rejected(self) -> None:
        path = self.root / "bad.zip"
        path.write_bytes(b"not a zip")
        with self.assertRaisesRegex(ArtifactValidationError, "Not a valid ZIP"):
            validate_macos(path)


if __name__ == "__main__":
    unittest.main()
