#!/usr/bin/env python3
"""Unit tests for the deterministic offline asset inventory."""
from __future__ import annotations

import json
import struct
import tempfile
import unittest
import wave
from unittest.mock import patch
from pathlib import Path

from audit_assets import build_report, inspect_media, main, render_markdown


def write_manifest(root: Path, entries: list[dict] | None = None) -> None:
    manifest_dir = root / "assets"
    manifest_dir.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema_version": 1,
        "policy": {
            "require_verified_license": True,
            "require_commercial_permission": True,
            "require_redistribution_permission": True,
            "paid_generation_apis_allowed": False,
        },
        "assets": entries or [],
    }
    (manifest_dir / "asset_manifest.json").write_text(
        json.dumps(payload), encoding="utf-8"
    )


def valid_png_header(width: int = 2, height: int = 3) -> bytes:
    return (
        b"\x89PNG\r\n\x1a\n"
        + struct.pack(">I", 13)
        + b"IHDR"
        + struct.pack(">II", width, height)
    )


class AssetInventoryTests(unittest.TestCase):
    def test_lists_media_with_hash_size_and_missing_manifest_status(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            assets = root / "assets"
            assets.mkdir()
            payload = valid_png_header()
            (assets / "scene.png").write_bytes(payload)
            write_manifest(root)

            report = build_report(root)

            self.assertEqual(report["media_file_count"], 1)
            row = report["media_files"][0]
            self.assertEqual(row["path"], "assets/scene.png")
            self.assertEqual(row["size_bytes"], len(payload))
            self.assertEqual(row["manifest_status"], "missing")
            self.assertEqual(row["inspection"]["width_px"], 2)
            self.assertEqual(row["inspection"]["height_px"], 3)
            self.assertEqual(report["missing_manifest_entries"], ["assets/scene.png"])
            self.assertEqual(len(row["sha256"]), 64)

    def test_reports_duplicate_hashes_without_deleting_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            assets = root / "assets"
            assets.mkdir()
            payload = valid_png_header()
            (assets / "one.png").write_bytes(payload)
            (assets / "two.png").write_bytes(payload)
            write_manifest(root)

            report = build_report(root)

            self.assertEqual(len(report["duplicate_file_groups"]), 1)
            self.assertEqual(
                report["duplicate_file_groups"][0]["paths"],
                ["assets/one.png", "assets/two.png"],
            )
            self.assertTrue((assets / "one.png").exists())
            self.assertTrue((assets / "two.png").exists())

    def test_reports_glTF_missing_external_buffer_without_network_fetch(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            assets = root / "assets"
            assets.mkdir()
            (assets / "broken.gltf").write_text(
                json.dumps({
                    "asset": {"version": "2.0"},
                    "buffers": [{"uri": "missing.bin", "byteLength": 12}],
                    "images": [{"uri": "https://example.invalid/texture.png"}],
                }),
                encoding="utf-8",
            )
            write_manifest(root)

            report = build_report(root)
            inspection = report["media_files"][0]["inspection"]

            self.assertEqual(len(inspection["missing_uris"]), 1)
            self.assertEqual(inspection["missing_uris"][0]["uri"], "missing.bin")
            self.assertEqual(inspection["missing_uris"][0]["status"], "missing")
            self.assertEqual(len(inspection["remote_or_absolute_uris"]), 1)
            self.assertEqual(
                inspection["remote_or_absolute_uris"][0]["status"],
                "remote_or_absolute_not_fetched",
            )

    def test_gltf_can_reference_shared_asset_inside_project_root(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            assets = root / "assets"
            (assets / "models").mkdir(parents=True)
            (assets / "shared.bin").write_bytes(b"shared")
            (assets / "models" / "hero.gltf").write_text(
                json.dumps({
                    "asset": {"version": "2.0"},
                    "buffers": [{"uri": "../shared.bin", "byteLength": 6}],
                }),
                encoding="utf-8",
            )
            write_manifest(root)

            report = build_report(root)
            inspection = next(
                row["inspection"] for row in report["media_files"]
                if row["path"] == "assets/models/hero.gltf"
            )

            self.assertEqual(inspection["missing_uris"], [])
            self.assertEqual(inspection["external_uris"][0]["status"], "found")

    def test_remote_gltf_uri_query_is_redacted(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            assets = root / "assets"
            assets.mkdir()
            (assets / "remote.gltf").write_text(
                json.dumps({
                    "asset": {"version": "2.0"},
                    "images": [{"uri": "https://example.invalid/texture.png?token=secret"}],
                }),
                encoding="utf-8",
            )
            write_manifest(root)

            report = build_report(root)
            uri = report["media_files"][0]["inspection"]["external_uris"][0]["uri"]

            self.assertNotIn("secret", uri)
            self.assertIn("query redacted", uri)

    def test_truncated_glb_is_reported_instead_of_crashing(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            assets = root / "assets"
            assets.mkdir()
            path = assets / "broken.glb"
            path.write_bytes(b"glTF")
            write_manifest(root)

            inspection = inspect_media(path)

            self.assertTrue(inspection["inspection_errors"])
            self.assertEqual(inspection["format"], "glb")

    def test_wav_metadata_is_read_from_header(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            assets = root / "assets"
            assets.mkdir()
            audio_path = assets / "short.wav"
            with wave.open(str(audio_path), "wb") as audio:
                audio.setnchannels(1)
                audio.setsampwidth(2)
                audio.setframerate(8000)
                audio.writeframes(b"\x00\x00" * 80)
            write_manifest(root)

            report = build_report(root)
            metadata = report["media_files"][0]["inspection"]

            self.assertEqual(metadata["channels"], 1)
            self.assertEqual(metadata["sample_width_bytes"], 2)
            self.assertEqual(metadata["sample_rate_hz"], 8000)
            self.assertAlmostEqual(metadata["duration_seconds"], 0.01)

    def test_optional_player_and_unexpected_missing_references_are_distinguished(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            scripts = root / "scripts"
            scripts.mkdir()
            (scripts / "sample.gd").write_text(
                'var player = load("res://assets/characters/player/player.glb")\n'
                'var scene = load("res://scenes/missing_scene.tscn")\n',
                encoding="utf-8",
            )
            (root / "assets" / "characters" / "player").mkdir(parents=True)
            write_manifest(root)

            report = build_report(root)
            ref_by_path = {
                item["resource_path"]: item["classification"]
                for item in report["resource_reference_candidates"]
            }

            self.assertEqual(
                ref_by_path["assets/characters/player/player.glb"],
                "known_optional",
            )
            self.assertEqual(
                ref_by_path["scenes/missing_scene.tscn"],
                "missing_reference_candidate",
            )

    def test_markdown_report_states_limits_and_manifest_gate(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "assets").mkdir()
            write_manifest(root)
            report = build_report(root)

            markdown = render_markdown(report)

            self.assertIn("لا يثبت الترخيص القانوني", markdown)
            self.assertIn("validate_free_assets.py", markdown)
            self.assertIn("مرشحات المراجع المفقودة", markdown)

    def test_cli_writes_json_and_markdown_reports(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "assets").mkdir()
            write_manifest(root)
            json_path = root / "out" / "report.json"
            markdown_path = root / "out" / "report.md"
            with patch(
                "sys.argv",
                [
                    "audit_assets.py",
                    "--root", str(root),
                    "--json-output", str(json_path),
                    "--markdown-output", str(markdown_path),
                ],
            ):
                self.assertEqual(main(), 0)

            saved_report = json.loads(json_path.read_text(encoding="utf-8"))
            markdown = markdown_path.read_text(encoding="utf-8")
            self.assertEqual(saved_report["media_file_count"], 0)
            self.assertIn("تقرير الجرد الجنائي الآلي", markdown)

    def test_invalid_manifest_is_reported(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            assets = root / "assets"
            assets.mkdir()
            (assets / "asset_manifest.json").write_text("{ invalid json", encoding="utf-8")

            report = build_report(root)

            self.assertEqual(len(report["manifest_parse_errors"]), 1)
            self.assertIn("could not be parsed", report["manifest_parse_errors"][0])


if __name__ == "__main__":
    unittest.main(verbosity=2)
