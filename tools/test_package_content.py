import pathlib
import tempfile
import unittest

import package_content


class PackageContentTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp_dir.name)
        self.source = self.root / "source"
        self.source.mkdir()

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_accepts_safe_relative_asset_path(self):
        self.assertTrue(package_content.is_safe_relative_path("characters/hero.glb"))

    def test_rejects_parent_traversal(self):
        self.assertFalse(package_content.is_safe_relative_path("../outside.json"))

    def test_rejects_absolute_path(self):
        self.assertFalse(package_content.is_safe_relative_path("/tmp/outside.json"))

    def test_rejects_backslash_path(self):
        self.assertFalse(package_content.is_safe_relative_path("characters\\..\\outside.json"))

    def test_collects_allowed_data_asset(self):
        (self.source / "hero.glb").write_bytes(b"glb-fixture")
        records = package_content.collect_files(self.source)
        self.assertEqual([record["path"] for record in records], ["hero.glb"])

    def test_rejects_script_file(self):
        (self.source / "remote.gd").write_text("extends Node", encoding="utf-8")
        with self.assertRaises(package_content.PackageError):
            package_content.collect_files(self.source)

    def test_rejects_native_library(self):
        (self.source / "remote.so").write_bytes(b"not a library")
        with self.assertRaises(package_content.PackageError):
            package_content.collect_files(self.source)

    def test_rejects_symlink(self):
        target = self.root / "outside.json"
        target.write_text("{}", encoding="utf-8")
        (self.source / "link.json").symlink_to(target)
        with self.assertRaises(package_content.PackageError):
            package_content.collect_files(self.source)

    def test_missing_signing_key_fails_closed(self):
        (self.source / "hero.glb").write_bytes(b"glb-fixture")
        with self.assertRaises(package_content.PackageError):
            package_content.build_package(
                source_dir=self.source,
                pack_id="test_pack",
                version="1.0.0",
                pack_type="character",
                url="https://content.example.invalid/test_pack.zip",
                output_zip=self.root / "test_pack.zip",
                output_envelope=self.root / "catalog.json",
                private_key=self.root / "missing-private-key.pem",
            )

    def test_rejects_non_https_package_url(self):
        with self.assertRaises(package_content.PackageError):
            package_content.validate_package_url("http://content.example.invalid/test.zip")

    def test_rejects_unsafe_pack_id(self):
        with self.assertRaises(package_content.PackageError):
            package_content.validate_pack_id("../bad-id")


if __name__ == "__main__":
    unittest.main()
