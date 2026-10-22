import base64
import json
import pathlib
import shutil
import subprocess
import tempfile
import unittest

from tools import sign_content_catalog


def pack(pack_id, dependencies=None):
    return {
        "id": pack_id,
        "name": pack_id,
        "version": "1.0.0",
        "type": "character",
        "url": f"https://cdn.example.invalid/{pack_id}.zip",
        "download_size": 128,
        "sha256": "a" * 64,
        "files": [{
            "path": "characters/hero.glb",
            "size": 64,
            "sha256": "b" * 64,
            "author": "Test author",
            "source_url": "https://assets.example.invalid/hero.glb",
            "license": "CC0-1.0",
            "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
            "attribution": "Test fixture; no attribution required by this license.",
            "commercial_use": True,
            "redistribution_allowed": True,
        }],
        "dependencies": dependencies or [],
    }


class SignContentCatalogTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp_dir.name)

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_accepts_catalog_with_multiple_packs_and_dependency(self):
        catalog = {"schema_version": 2, "packs": [pack("base_pack"), pack("hero_pack", ["base_pack"])]}
        self.assertEqual(sign_content_catalog.validate_catalog(catalog), catalog)

    def test_rejects_file_missing_provenance_metadata(self):
        catalog = {"schema_version": 2, "packs": [pack("hero_pack")]}
        del catalog["packs"][0]["files"][0]["author"]
        with self.assertRaises(sign_content_catalog.PackageError):
            sign_content_catalog.validate_catalog(catalog)

    def test_rejects_file_without_redistribution_permission(self):
        catalog = {"schema_version": 2, "packs": [pack("hero_pack")]}
        catalog["packs"][0]["files"][0]["redistribution_allowed"] = False
        with self.assertRaises(sign_content_catalog.PackageError):
            sign_content_catalog.validate_catalog(catalog)

    def test_rejects_file_license_url_with_embedded_credentials(self):
        catalog = {"schema_version": 2, "packs": [pack("hero_pack")]}
        catalog["packs"][0]["files"][0]["license_url"] = "https://user:pass@license.example.invalid/text"
        with self.assertRaises(sign_content_catalog.PackageError):
            sign_content_catalog.validate_catalog(catalog)

    def test_rejects_legacy_schema_without_provenance_contract(self):
        catalog = {"schema_version": 1, "packs": [pack("hero_pack")]}
        with self.assertRaises(sign_content_catalog.PackageError):
            sign_content_catalog.validate_catalog(catalog)

    def test_rejects_missing_dependency(self):
        catalog = {"schema_version": 2, "packs": [pack("hero_pack", ["missing_pack"])]}
        with self.assertRaises(sign_content_catalog.PackageError):
            sign_content_catalog.validate_catalog(catalog)

    def test_rejects_dependency_cycle(self):
        catalog = {"schema_version": 2, "packs": [pack("base_pack", ["hero_pack"]), pack("hero_pack", ["base_pack"])]}
        with self.assertRaises(sign_content_catalog.PackageError):
            sign_content_catalog.validate_catalog(catalog)

    def test_rejects_reserved_installer_manifest(self):
        catalog = {"schema_version": 2, "packs": [pack("hero_pack")]}
        catalog["packs"][0]["files"][0]["path"] = "installed_manifest.json"
        with self.assertRaises(sign_content_catalog.PackageError):
            sign_content_catalog.validate_catalog(catalog)

    def test_missing_key_fails_closed(self):
        input_path = self.root / "catalog-input.json"
        input_path.write_text(json.dumps({"schema_version": 2, "packs": [pack("hero_pack")]}), encoding="utf-8")
        with self.assertRaises(sign_content_catalog.PackageError):
            sign_content_catalog.sign_catalog(input_path, self.root / "signed.json", self.root / "missing.pem")

    @unittest.skipUnless(shutil.which("openssl"), "OpenSSL is required for signature integration test")
    def test_signs_valid_multi_pack_catalog(self):
        key_path = self.root / "private.pem"
        generated = subprocess.run(
            ["openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048", "-out", str(key_path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(generated.returncode, 0)
        input_path = self.root / "catalog-input.json"
        input_path.write_text(json.dumps({
            "schema_version": 2,
            "packs": [pack("base_pack"), pack("hero_pack", ["base_pack"])],
        }), encoding="utf-8")
        output_path = self.root / "catalog.json"
        result = sign_content_catalog.sign_catalog(input_path, output_path, key_path)
        envelope = json.loads(output_path.read_text(encoding="utf-8"))
        payload_path = self.root / "payload.json"
        signature_path = self.root / "signature.bin"
        payload_path.write_bytes(base64.b64decode(envelope["payload_base64"], validate=True))
        signature_path.write_bytes(base64.b64decode(envelope["signature_base64"], validate=True))
        verified = subprocess.run(
            ["openssl", "dgst", "-sha256", "-verify", result["public_key"], "-signature", str(signature_path), str(payload_path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(verified.returncode, 0, verified.stderr.decode("utf-8", errors="replace"))


if __name__ == "__main__":
    unittest.main()
