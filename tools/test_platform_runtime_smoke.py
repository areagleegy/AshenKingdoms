"""Unit tests for the cross-platform exported-runtime smoke harness."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

from platform_runtime_smoke import SmokeTestError, check_runtime_output, run_smoke


BANNER = "Godot Engine v4.6.stable.official.test"


class RuntimeOutputTests(unittest.TestCase):
    def test_clean_runtime_output_passes(self) -> None:
        check_runtime_output(BANNER + "\\n[network] server ready\\n", 0)

    def test_nonzero_exit_fails(self) -> None:
        with self.assertRaisesRegex(SmokeTestError, "status 3"):
            check_runtime_output(BANNER + "\\n", 3)

    def test_missing_engine_banner_fails(self) -> None:
        with self.assertRaisesRegex(SmokeTestError, "version banner"):
            check_runtime_output("started with no runtime banner\\n", 0)

    def test_script_error_fails_even_when_exit_code_is_zero(self) -> None:
        with self.assertRaisesRegex(SmokeTestError, "SCRIPT ERROR"):
            check_runtime_output(BANNER + "\\nSCRIPT ERROR: test\\n", 0)

    def test_engine_error_fails_even_when_exit_code_is_zero(self) -> None:
        with self.assertRaisesRegex(SmokeTestError, "ERROR:"):
            check_runtime_output(BANNER + "\\nERROR: shutdown issue\\n", 0)

    def test_passed_test_name_does_not_trigger_failure(self) -> None:
        check_runtime_output(BANNER + "\\n[PASS] scene loaded\\n", 0)

    def test_run_smoke_writes_combined_output_log(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            log_path = Path(temporary) / "nested" / "runtime.log"
            command = [
                sys.executable,
                "-c",
                "print('Godot Engine v4.6.stable.official.test\\n[network] server ready')",
            ]
            output = run_smoke(command, timeout_seconds=5, log_path=log_path)
            self.assertIn("server ready", output)
            self.assertEqual(log_path.read_text(encoding="utf-8"), output)

    def test_run_smoke_reports_timeout(self) -> None:
        with self.assertRaisesRegex(SmokeTestError, "timeout"):
            run_smoke(
                [sys.executable, "-c", "import time; time.sleep(2)"],
                timeout_seconds=0.1,
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
