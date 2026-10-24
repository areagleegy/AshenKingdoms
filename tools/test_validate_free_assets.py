from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from tools import validate_free_assets


def manifest_entry(path: str = "assets/test.svg", **overrides: object) -> dict[str, object]:
    entry: dict[str, object] = {
        "path": path,
        "author": "Test Author",
        "source_url": "https://example.org/source",
        "license": "CC0-1.0",
        "license_url": "https://example.org/license",
        "attribution": "No attribution required under verified CC0 terms",
        "commercial_use": True,
        "redistribution_allowed": True,
    }
    entry.update(overrides)
    return entry


class ValidateFreeAssetsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        (self.root / "assets").mkdir()
        (self.root / "assets" / "test.svg").write_text("<svg/>", encoding="utf-8")

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def write_manifest(self, assets: object, **overrides: object) -> None:
        document: dict[str, object] = {
            "schema_version": 1,
            "policy": {
                "require_verified_license": True,
                "require_commercial_permission": True,
                "require_redistribution_permission": True,
            },
            "assets": assets,
        }
        document.update(overrides)
        (self.root / "assets" / "asset_manifest.json").write_text(
            json.dumps(document), encoding="utf-8"
        )

    def test_accepts_complete_manifest_for_existing_asset(self) -> None:
        self.write_manifest([manifest_entry()])
        self.assertEqual(validate_free_assets.validate(self.root), [])

    def test_reports_missing_manifest(self) -> None:
        errors = validate_free_assets.validate(self.root)
        self.assertTrue(any("Manifest not found" in error for error in errors))

    def test_rejects_asset_without_manifest_entry(self) -> None:
        self.write_manifest([])
        errors = validate_free_assets.validate(self.root)
        self.assertTrue(any("Asset has no manifest entry: assets/test.svg" in error for error in errors))

    def test_rejects_path_traversal_outside_assets(self) -> None:
        self.write_manifest([manifest_entry("../outside.svg")])
        errors = validate_free_assets.validate(self.root)
        self.assertTrue(any("must stay inside assets/" in error for error in errors))

    def test_rejects_duplicate_manifest_paths(self) -> None:
        self.write_manifest([manifest_entry(), manifest_entry()])
        errors = validate_free_assets.validate(self.root)
        self.assertTrue(any("Duplicate manifest path: assets/test.svg" in error for error in errors))

    def test_rejects_non_https_or_malformed_source_urls(self) -> None:
        self.write_manifest([manifest_entry(source_url="file:///tmp/source", license_url="not-a-url")])
        errors = validate_free_assets.validate(self.root)
        self.assertTrue(any("source_url must be a valid http(s) URL" in error for error in errors))
        self.assertTrue(any("license_url must be a valid http(s) URL" in error for error in errors))

    def test_rejects_assets_without_commercial_and_redistribution_permissions(self) -> None:
        self.write_manifest([manifest_entry(commercial_use=False, redistribution_allowed=False)])
        errors = validate_free_assets.validate(self.root)
        self.assertTrue(any("commercial_use must be true" in error for error in errors))
        self.assertTrue(any("redistribution_allowed must be true" in error for error in errors))

    def test_rejects_missing_license_metadata_fields(self) -> None:
        entry = manifest_entry()
        del entry["license"]
        self.write_manifest([entry])
        errors = validate_free_assets.validate(self.root)
        self.assertTrue(any("assets[0] is missing fields: license" in error for error in errors))

    def test_rejects_stale_manifest_entries(self) -> None:
        self.write_manifest([manifest_entry("assets/missing.svg")])
        errors = validate_free_assets.validate(self.root)
        self.assertTrue(any("Asset file does not exist: assets/missing.svg" in error for error in errors))
        self.assertTrue(any("Manifest entry is not a recognized existing asset: assets/missing.svg" in error for error in errors))

    def test_rejects_invalid_manifest_root(self) -> None:
        (self.root / "assets" / "asset_manifest.json").write_text("[]", encoding="utf-8")
        errors = validate_free_assets.validate(self.root)
        self.assertIn("Manifest root must be a JSON object.", errors)


if __name__ == "__main__":
    unittest.main(verbosity=2)
