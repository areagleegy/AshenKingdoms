#!/usr/bin/env python3
"""Regression tests for the offline Android QA report analyzer."""
from __future__ import annotations

import json
import unittest
from unittest.mock import patch

from analyze_android_qa_report import analyze_report, request_local_ai, REPORT_TYPE


def valid_report() -> dict:
    return {
        "schema_version": 1,
        "report_type": REPORT_TYPE,
        "session_duration_seconds": 180,
        "build": {
            "commit": "a" * 40,
            "project_version": "0.1.0-qa",
            "godot_version": "4.6.stable",
            "android": True,
            "qa_tools": True,
        },
        "test_results": [
            {"id": "combat_health_lifecycle", "status": "pass", "duration_ms": 5, "error_code": 0},
            {"id": "dialogue_choice_branch", "status": "pass", "duration_ms": 8, "error_code": 0},
            {"id": "quest_reward_once", "status": "pass", "duration_ms": 7, "error_code": 0},
        ],
        "events": [
            {"event": "performance_sample", "details": {"fps": 60, "process_ms": 9, "static_memory_mb": 120}},
            {"event": "performance_sample", "details": {"fps": 58, "process_ms": 10, "static_memory_mb": 125}},
            {"event": "performance_sample", "details": {"fps": 60, "process_ms": 8, "static_memory_mb": 123}},
            {"event": "combat.player_attack_started", "details": {"damage": 20}},
            {"event": "dialogue_started", "details": {"node_count": 4}},
        ],
    }


class AndroidQAReportAnalysisTests(unittest.TestCase):
    def test_healthy_report_passes_only_within_observed_scope(self):
        result = analyze_report(valid_report())
        self.assertEqual(result["readiness"], "passed_within_scope")
        self.assertEqual(result["tests"], {"total": 3, "passed": 3, "failed": 0, "skipped": 0})
        self.assertEqual(result["metrics"]["valid_fps_sample_count"], 3)
        self.assertEqual(result["metrics"]["median_fps"], 60.0)
        self.assertEqual(result["findings"], [])

    def test_failed_dialogue_or_combat_test_blocks_readiness(self):
        report = valid_report()
        report["test_results"][1]["status"] = "fail"
        report["test_results"][1]["error_code"] = 30
        result = analyze_report(report)
        self.assertEqual(result["readiness"], "blocked")
        self.assertTrue(any(item["id"] == "test_failed_dialogue_choice_branch"
                            and item["severity"] == "high" for item in result["findings"]))

    def test_low_fps_is_reported_as_a_performance_finding(self):
        report = valid_report()
        for event, fps in zip(report["events"][:3], [12, 14, 13]):
            event["details"]["fps"] = fps
        result = analyze_report(report)
        self.assertEqual(result["readiness"], "blocked")
        self.assertTrue(any(item["id"] == "critical_low_fps" for item in result["findings"]))

    def test_skipped_manual_acceptance_is_not_counted_as_pass(self):
        report = valid_report()
        report["test_results"].append({
            "id": "manual_player_enemy_combat_3d",
            "status": "skip",
            "duration_ms": 0,
            "error_code": 0,
        })
        result = analyze_report(report)
        self.assertEqual(result["tests"]["skipped"], 1)
        self.assertEqual(result["tests"]["passed"], 3)
        self.assertEqual(result["readiness"], "evidence_incomplete")
        self.assertTrue(any(item["id"] == "manual_acceptance_pending" for item in result["findings"]))

    def test_malformed_report_contract_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "report_type"):
            analyze_report({"schema_version": 1, "report_type": "not-ashen"})

    def test_non_finite_metrics_are_ignored(self):
        report = valid_report()
        report["events"][0]["details"]["fps"] = float("nan")
        report["events"][1]["details"]["fps"] = float("inf")
        result = analyze_report(report)
        self.assertEqual(result["metrics"]["valid_fps_sample_count"], 1)
        self.assertTrue(any(item["id"] == "insufficient_performance_samples" for item in result["findings"]))

    def test_huge_numeric_values_are_ignored_instead_of_crashing(self):
        report = valid_report()
        report["events"][0]["details"]["fps"] = 10 ** 400
        result = analyze_report(report)
        self.assertEqual(result["metrics"]["valid_fps_sample_count"], 2)
        self.assertTrue(any(item["id"] == "insufficient_performance_samples"
                            for item in result["findings"]))

    def test_boolean_schema_version_is_rejected(self):
        report = valid_report()
        report["schema_version"] = True
        with self.assertRaisesRegex(ValueError, "schema_version"):
            analyze_report(report)

    def test_local_ai_is_explicit_and_restricted_to_localhost(self):
        analysis = analyze_report(valid_report())
        fake_response = type("FakeResponse", (), {
            "__enter__": lambda self: self,
            "__exit__": lambda self, *args: None,
            "read": lambda self, size: b'{"response":"\\u0623\\u0639\\u062f \\u0627\\u0644\\u0627\\u062e\\u062a\\u0628\\u0627\\u0631."}',
        })()
        with patch("analyze_android_qa_report.urllib.request.urlopen", return_value=fake_response) as opener:
            advice = request_local_ai(analysis, "qwen2.5:3b")
        self.assertEqual(advice, "أعد الاختبار.")
        request = opener.call_args.args[0]
        self.assertEqual(request.full_url, "http://127.0.0.1:11434/api/generate")
        sent = json.loads(request.data.decode("utf-8"))["prompt"]
        self.assertNotIn("session_id", sent)
        self.assertNotIn("raw_dialogue", sent)

    def test_local_ai_model_name_is_validated_before_request(self):
        analysis = analyze_report(valid_report())
        with patch("analyze_android_qa_report.urllib.request.urlopen") as opener:
            with self.assertRaisesRegex(ValueError, "model name"):
                request_local_ai(analysis, "../../external")
        opener.assert_not_called()


if __name__ == "__main__":
    unittest.main(verbosity=2)
