#!/usr/bin/env python3
"""Unit tests for the deterministic, offline diagnostics layer."""
import os
import unittest
from unittest.mock import patch

from ai_test_diagnostics import classify_text, redact_sensitive, request_ai_advice


class DiagnosticsClassifierTests(unittest.TestCase):
    def test_parse_error_is_ranked_first(self):
        findings = classify_text(
            "ERROR: unrelated message\n"
            "SCRIPT ERROR: Parse Error: Unexpected token in script.gd:12\n"
            "Parser error while loading script\n"
        )
        self.assertTrue(findings)
        self.assertEqual(findings[0]["category"], "gdscript_parse")
        self.assertGreaterEqual(findings[0]["confidence_score"], 100 - 1)

    def test_network_error_has_actionable_category(self):
        findings = classify_text("ENet connection failed: timed out waiting for server")
        self.assertEqual(findings[0]["category"], "network")
        self.assertIn("المنفذ", findings[0]["recommended_action"])

    def test_missing_resource_is_detected(self):
        findings = classify_text("Failed loading resource: res://assets/hero/player.glb")
        categories = {item["category"] for item in findings}
        self.assertIn("missing_resource", categories)
        self.assertIn("character_asset", categories)

    def test_evidence_redacts_common_credentials(self):
        text = "Authorization: Bearer abcdefghijklmnop api_key=supersecretvalue"
        cleaned = redact_sensitive(text)
        self.assertNotIn("abcdefghijklmnop", cleaned)
        self.assertNotIn("supersecretvalue", cleaned)
        self.assertIn("[REDACTED]", cleaned)

    def test_remote_ai_is_off_by_default_and_makes_no_request(self):
        report = {"diagnostics": []}
        with patch.dict(os.environ, {"ASHEN_AI_DIAGNOSE": "false", "ASHEN_AI_ENDPOINT": "https://example.invalid/v1"}):
            advice, status = request_ai_advice(report, "ERROR: synthetic failure")
        self.assertIsNone(advice)
        self.assertEqual(status, "disabled")


if __name__ == "__main__":
    unittest.main(verbosity=2)
