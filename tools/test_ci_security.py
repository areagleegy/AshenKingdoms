#!/usr/bin/env python3
"""Regression checks that untrusted pull-request CI never receives AI credentials."""
from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VALIDATE_WORKFLOW = ROOT / ".github" / "workflows" / "validate.yml"


class WorkflowSecretIsolationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workflow = VALIDATE_WORKFLOW.read_text(encoding="utf-8")

    def test_validation_workflow_does_not_reference_remote_ai_credentials(self) -> None:
        # This workflow runs code from pull-request branches. Do not inject credentials
        # here: a modified script or workflow could exfiltrate them before review.
        self.assertNotRegex(
            self.workflow,
            r"(?m)^\s*ASHEN_AI_(?:ENDPOINT|API_KEY)\s*:",
        )
        self.assertNotRegex(
            self.workflow,
            r"\$\{\{\s*secrets\.ASHEN_AI_(?:ENDPOINT|API_KEY)\s*\}\}",
        )

    def test_diagnostic_step_explicitly_disables_remote_ai(self) -> None:
        match = re.search(
            r"(?ms)^\s*-\s*name:\s*Diagnose test logs.*?(?=^\s*-\s*name:|\Z)",
            self.workflow,
        )
        self.assertIsNotNone(match, "validate.yml must keep its local diagnostic step")
        assert match is not None
        diagnostic_step = match.group(0)
        self.assertRegex(
            diagnostic_step,
            r"(?m)^\s+ASHEN_AI_DIAGNOSE:\s*[\"']?false[\"']?\s*$",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
