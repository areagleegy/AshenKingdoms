from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from tools import validate_free_assets


class ValidateFreeAssetsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.assets_dir = self.root / "assets"
        self.assets_dir.mkdir()
        (self.assets_dir / "sample.glb").write_bytes(b"fixture-model")
        self.manifest_path = self.assets_dir / "asset_manifest.json"

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def manifest(self) -> dict:
        return {
            "schema_version": 1,
            "policy": {
                "require_verified_license": True,
                "require_commercial_permission": True,
                "require_redistribution_permission": True,
                "offline_first": True,
                "paid_generation_apis_allowed": False,
            },
            "assets": [
                {
                    "path": "assets/sample.glb",
                    "author": "Test author",
                    "source_url": "https://assets.example.invalid/sample.glb",
                    "license": "CC0-1.0",
                    "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
                    "attribution": "Test fixture",
                    "commercial_use": True,
                    "redistribution_allowed": True,
                }
            ],
        }

    def write_manifest(self, manifest: dict) -> None:
        self.manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

    def test_accepts_complete_verified_manifest(self) -> None:
        self.write_manifest(self.manifest())
        self.assertEqual(validate_free_assets.validate(self.root), [])

    def test_rejects_url_with_embedded_credentials(self) -> None:
        self.assertFalse(validate_free_assets.is_http_url("https://user:pass@assets.example.invalid/file.glb"))

    def test_rejects_url_with_whitespace(self) -> None:
        self.assertFalse(validate_free_assets.is_http_url("https://assets.example.invalid/bad path.glb"))

    def test_rejects_url_with_invalid_port(self) -> None:
        self.assertFalse(validate_free_assets.is_http_url("https://assets.example.invalid:notaport/file.glb"))

    def test_rejects_manifest_without_asset_record(self) -> None:
        manifest = self.manifest()
        manifest["assets"] = []
        self.write_manifest(manifest)
        errors = validate_free_assets.validate(self.root)
        self.assertTrue(any("Asset has no manifest entry: assets/sample.glb" in error for error in errors))

    def test_rejects_unconfirmed_redistribution(self) -> None:
        manifest = self.manifest()
        manifest["assets"][0]["redistribution_allowed"] = False
        self.write_manifest(manifest)
        errors = validate_free_assets.validate(self.root)
        self.assertTrue(any("redistribution_allowed must be true" in error for error in errors))

    def test_rejects_enabled_paid_generation_api_policy(self) -> None:
        manifest = self.manifest()
        manifest["policy"]["paid_generation_apis_allowed"] = True
        self.write_manifest(manifest)
        errors = validate_free_assets.validate(self.root)
        self.assertTrue(any("paid_generation_apis_allowed must be false" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
