from __future__ import annotations
import json
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from validate_rigged_player_glb import InvalidGLB, validate, read_glb

ROOT = Path(__file__).resolve().parents[1]
STATIC_GENERATOR = ROOT / "tools" / "generate_procedural_player_glb.py"
RIG_GENERATOR = ROOT / "tools" / "generate_rigged_player_glb.py"


class RiggedPlayerCandidateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tempdir = tempfile.TemporaryDirectory(prefix="ashen-rigged-player-test-")
        cls.temp = Path(cls.tempdir.name)
        cls.static = cls.temp / "static_player.glb"
        cls.rigged = cls.temp / "rigged_player.glb"
        subprocess.run(
            [sys.executable, str(STATIC_GENERATOR), "--output", str(cls.static)],
            cwd=ROOT, check=True, capture_output=True, text=True,
        )
        subprocess.run(
            [sys.executable, str(RIG_GENERATOR), "--source", str(cls.static), "--output", str(cls.rigged)],
            cwd=ROOT, check=True, capture_output=True, text=True,
        )

    @classmethod
    def tearDownClass(cls):
        cls.tempdir.cleanup()

    def test_generated_candidate_has_skin_and_required_clips(self):
        report = validate(self.rigged)
        self.assertEqual(report["result"], "PASS")
        self.assertGreaterEqual(report["bone_count"], 15)
        self.assertEqual(
            set(report["animations"]),
            {"Idle_01", "Walking", "Running", "Jump", "HeavyAttack", "Hit", "Death"},
        )
        self.assertGreater(report["skinned_vertex_count"], 0)
        self.assertGreater(report["animation_channel_count"], 10)

    def test_generation_is_deterministic(self):
        other = self.temp / "rigged_player_second.glb"
        subprocess.run(
            [sys.executable, str(RIG_GENERATOR), "--source", str(self.static), "--output", str(other)],
            cwd=ROOT, check=True, capture_output=True, text=True,
        )
        self.assertEqual(self.rigged.read_bytes(), other.read_bytes())

    def test_bad_header_is_rejected(self):
        bad = self.temp / "bad.glb"
        bad.write_bytes(b"not a GLB")
        with self.assertRaises(InvalidGLB):
            read_glb(bad)

    def test_bad_header_fails_validation_cli(self):
        bad = self.temp / "bad-cli.glb"
        bad.write_bytes(b"not a GLB")
        result = subprocess.run(
            [sys.executable, str(ROOT / "tools" / "validate_rigged_player_glb.py"), str(bad)],
            cwd=ROOT, capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("ERROR:", result.stderr)


if __name__ == "__main__":
    unittest.main()
