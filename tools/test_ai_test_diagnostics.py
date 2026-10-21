#!/usr/bin/env python3
"""Unit tests for the deterministic, offline diagnostics layer."""
import json
import os
import unittest
from pathlib import Path
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

    def test_enemy_ai_behavior_failure_has_actionable_category(self):
        findings = classify_text("ERROR: [FAIL] network enemy enters chase state for a target in detection range")
        self.assertEqual(findings[0]["category"], "enemy_ai_behavior")
        self.assertIn("نطاق الكشف", findings[0]["recommended_action"])

    def test_clean_enemy_ai_log_has_no_findings(self):
        log = (
            "[PASS] local enemy chases a target inside detection range\\n"
            "[enemy-ai] checks: 31, failures: 0"
        )
        self.assertEqual(classify_text(log), [])

    def test_pass_assertions_do_not_trigger_missing_asset_diagnostics(self):
        log = (
            "player-character-tests.log: [PASS] missing player.glb selects the documented placeholder path\\n"
            "player-character-tests.log: [PASS] player tolerates missing AnimationPlayer"
        )
        self.assertEqual(classify_text(log), [])

    def test_benign_success_logs_do_not_create_findings(self):
        log = "Godot Engine v4.6; renderer: headless\nENet peer initialized\nLoaded res://assets/hero/player.glb\nAndroid SDK configured\nReimport complete: .godot/imported/hero.glb\n"
        self.assertEqual(classify_text(log), [])

    def test_successful_unittest_name_does_not_create_parse_finding(self):
        log = "test_parse_error_is_ranked_first (test_ai_test_diagnostics.DiagnosticsClassifierTests) ... ok"
        self.assertEqual(classify_text(log), [])

    def test_adb_daemon_refusal_is_not_game_network_error(self):
        log = "cannot connect to daemon at tcp:5037: Connection refused"
        self.assertEqual(classify_text(log), [])

    def test_expected_malformed_json_rejection_is_not_reported(self):
        log = (
            "ERROR: Parse JSON failed. Error at line 0: Expected key\\n"
            "[PASS] malformed JSON is rejected safely\\n"
        )
        self.assertEqual(classify_text(log), [])

    def test_expected_json_error_does_not_hide_another_log_error(self):
        log = (
            "gameplay-tests.log: ERROR: Parse JSON failed. Error at line 0: Expected key\n"
            "gameplay-tests.log: [PASS] malformed JSON is rejected safely\n"
            "other-tests.log: ERROR: Parse JSON failed. Unexpected malformed test fixture\n"
        )
        findings = classify_text(log)
        self.assertTrue(findings)
        self.assertEqual(findings[-1]["category"], "generic_error")
        self.assertTrue(any("other-tests.log" in line for line in findings[-1]["evidence"]))

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


    def test_godot_cli_download_failure_gets_installation_category(self):
        log = (
            "curl: (22) The requested URL returned error: 503\n"
            "unzip: cannot find zipfile directory\n"
            "Godot CLI setup failed\n"
        )
        findings = classify_text(log)
        self.assertEqual(findings[0]["category"], "godot_installation")
        self.assertIn("التنزيل", findings[0]["recommended_action"])

    def test_missing_required_file_has_actionable_category(self):
        findings = classify_text("MISSING REQUIRED FILE: tests/gameplay_smoke_test.gd")
        self.assertEqual(findings[0]["category"], "required_files")
        self.assertIn("الملف", findings[0]["recommended_action"])

    def test_labeled_corpus_distinguishes_known_errors_and_clean_logs(self):
        corpus_path = Path(__file__).with_name("diagnostic_cases.json")
        corpus = json.loads(corpus_path.read_text(encoding="utf-8"))
        cases = corpus["cases"]
        self.assertGreaterEqual(len(cases), 10)
        for case in cases:
            with self.subTest(case=case["id"]):
                findings = classify_text(case["log"])
                categories = {item["category"] for item in findings}
                expected = case["expected_category"]
                if expected is None:
                    self.assertEqual(findings, [], case["id"])
                else:
                    self.assertIn(expected, categories, case["id"])

    def test_remote_ai_is_off_by_default_and_makes_no_request(self):
        report = {"diagnostics": []}
        with patch.dict(os.environ, {"ASHEN_AI_DIAGNOSE": "false", "ASHEN_AI_ENDPOINT": "https://example.invalid/v1"}):
            advice, status = request_ai_advice(report, "ERROR: synthetic failure")
        self.assertIsNone(advice)
        self.assertEqual(status, "disabled")


class DiagnosticBenchmarkTests(unittest.TestCase):
    def test_benchmark_reports_hits_misses_and_false_positives(self):
        from diagnostic_benchmark import evaluate_cases

        cases = [
            {"id": "hit", "expected_category": "network", "log": "ENet connection failed: timed out"},
            {"id": "miss", "expected_category": "android_export", "log": "Android SDK configured"},
            {"id": "false-positive", "expected_category": None, "log": "ERROR: unexpected failure"},
        ]
        result = evaluate_cases(cases, classify_text)
        self.assertEqual(result["total_cases"], 3)
        self.assertEqual(result["positive_cases"], 2)
        self.assertEqual(result["negative_cases"], 1)
        self.assertEqual(result["detected_expected_category"], 1)
        self.assertEqual(result["missed_positive_cases"], ["miss"])
        self.assertEqual(result["false_positive_cases"], ["false-positive"])
        self.assertEqual(result["expected_category_recall_percent"], 50.0)
        self.assertEqual(result["negative_case_specificity_percent"], 0.0)

    def test_benchmark_rejects_duplicate_case_ids(self):
        from diagnostic_benchmark import evaluate_cases

        cases = [
            {"id": "duplicate", "expected_category": None, "log": "clean"},
            {"id": "duplicate", "expected_category": None, "log": "clean"},
        ]
        with self.assertRaisesRegex(ValueError, "duplicate"):
            evaluate_cases(cases, classify_text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
