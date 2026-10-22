import base64
import json
import pathlib
import shutil
import subprocess
import tempfile
import unittest

from tools import package_content


class PackageContentTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp_dir.name)
        self.source = self.root / "source"
        self.source.mkdir()

    def tearDown(self):
        self.temp_dir.cleanup()

    def _write_provenance(self, filenames):
        manifest_path = self.root / "provenance.json"
        manifest = {
            "schema_version": 1,
            "assets": [
                {
                    "path": name,
                    "author": "Test author",
                    "source_url": f"https://assets.example.invalid/{name}",
                    "license": "CC0-1.0",
                    "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
                    "attribution": "Fixture asset",
                    "commercial_use": True,
                    "redistribution_allowed": True,
                }
                for name in filenames
            ],
        }
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        return manifest_path

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
                asset_manifest_path=self.root / "provenance.json",
                pack_id="test_pack",
                version="1.0.0",
                pack_type="character",
                url="https://content.example.invalid/test_pack.zip",
                output_zip=self.root / "test_pack.zip",
                output_envelope=self.root / "catalog.json",
                private_key=self.root / "missing-private-key.pem",
            )

    def test_rejects_reserved_installer_manifest(self):
        (self.source / "installed_manifest.json").write_text("{}", encoding="utf-8")
        with self.assertRaises(package_content.PackageError):
            package_content.collect_files(self.source)

    def test_rejects_duplicate_case_insensitive_paths(self):
        (self.source / "Hero.glb").write_bytes(b"one")
        (self.source / "hero.glb").write_bytes(b"two")
        with self.assertRaises(package_content.PackageError):
            package_content.collect_files(self.source)

    @unittest.skipUnless(shutil.which("openssl"), "OpenSSL is required for signature integration test")
    def test_builds_deterministic_archive_and_valid_signed_catalog(self):
        key_path = self.root / "private.pem"
        generated = subprocess.run(
            ["openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048", "-out", str(key_path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(generated.returncode, 0)
        (self.source / "hero.glb").write_bytes(b"tiny-glb-fixture")
        zip_one = self.root / "one.zip"
        catalog_one = self.root / "one.json"
        provenance_path = self._write_provenance(["hero.glb"])
        result = package_content.build_package(
            source_dir=self.source,
            asset_manifest_path=provenance_path,
            pack_id="test_character",
            version="1.0.0",
            pack_type="character",
            url="https://cdn.example.invalid/test_character.zip",
            output_zip=zip_one,
            output_envelope=catalog_one,
            private_key=key_path,
        )
        self.assertTrue(zip_one.is_file())
        envelope = json.loads(catalog_one.read_text(encoding="utf-8"))
        payload = base64.b64decode(envelope["payload_base64"], validate=True)
        catalog_payload = json.loads(payload.decode("utf-8"))
        file_record = catalog_payload["packs"][0]["files"][0]
        for provenance_field in ("author", "source_url", "license", "license_url", "attribution"):
            self.assertTrue(file_record[provenance_field])
        self.assertIs(file_record["commercial_use"], True)
        self.assertIs(file_record["redistribution_allowed"], True)
        signature = base64.b64decode(envelope["signature_base64"], validate=True)
        payload_path = self.root / "payload.json"
        signature_path = self.root / "signature.bin"
        payload_path.write_bytes(payload)
        signature_path.write_bytes(signature)
        verification = subprocess.run(
            ["openssl", "dgst", "-sha256", "-verify", result["public_key"], "-signature", str(signature_path), str(payload_path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(verification.returncode, 0, verification.stderr.decode("utf-8", errors="replace"))
        zip_two = self.root / "two.zip"
        package_content.create_archive(self.source, zip_two, package_content.collect_files(self.source))
        self.assertEqual(zip_one.read_bytes(), zip_two.read_bytes())

    def test_provenance_manifest_must_cover_every_packaged_file(self):
        (self.source / "hero.glb").write_bytes(b"glb-fixture")
        records = package_content.collect_files(self.source)
        manifest_path = self.root / "provenance.json"
        manifest_path.write_text(json.dumps({"schema_version": 1, "assets": []}), encoding="utf-8")
        with self.assertRaises(package_content.PackageError):
            package_content.validate_provenance_manifest(manifest_path, self.source, records)

    def test_provenance_manifest_rejects_unconfirmed_redistribution(self):
        (self.source / "hero.glb").write_bytes(b"glb-fixture")
        records = package_content.collect_files(self.source)
        manifest_path = self._write_provenance(["hero.glb"])
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["assets"][0]["redistribution_allowed"] = False
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        with self.assertRaises(package_content.PackageError):
            package_content.validate_provenance_manifest(manifest_path, self.source, records)

    def test_provenance_manifest_rejects_path_outside_package(self):
        (self.source / "hero.glb").write_bytes(b"glb-fixture")
        records = package_content.collect_files(self.source)
        manifest_path = self._write_provenance(["other.glb"])
        with self.assertRaises(package_content.PackageError):
            package_content.validate_provenance_manifest(manifest_path, self.source, records)

    def test_create_archive_detects_asset_changed_after_hashing(self):
        asset_path = self.source / "hero.glb"
        asset_path.write_bytes(b"before")
        records = package_content.collect_files(self.source)
        asset_path.write_bytes(b"after-and-longer")
        archive_path = self.root / "changed.zip"
        with self.assertRaises(package_content.PackageError):
            package_content.create_archive(self.source, archive_path, records)
        self.assertFalse(archive_path.exists())

    def test_rejects_non_https_package_url(self):
        with self.assertRaises(package_content.PackageError):
            package_content.validate_package_url("http://content.example.invalid/test.zip")

    def test_rejects_unsafe_pack_id(self):
        with self.assertRaises(package_content.PackageError):
            package_content.validate_pack_id("../bad-id")


if __name__ == "__main__":
    unittest.main()
