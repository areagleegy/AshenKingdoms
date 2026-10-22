#!/usr/bin/env python3
"""Regression checks that validation CI never exposes remote AI credentials."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "validate.yml"


class WorkflowSecretIsolationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = WORKFLOW.read_text(encoding="utf-8")
        cls.lines = cls.text.splitlines()

    def test_validation_workflow_has_no_ai_secret_bindings(self) -> None:
        self.assertNotRegex(
            self.text,
            r"\$\{\{\s*secrets\.ASHEN_AI_(?:ENDPOINT|API_KEY)\s*\}\}",
        )
        self.assertNotRegex(
            self.text,
            r"(?m)^\s*ASHEN_AI_(?:ENDPOINT|API_KEY)\s*:",
        )

    def test_remote_ai_diagnostics_are_explicitly_disabled(self) -> None:
        step = re.search(
            r"(?ms)^      - name: Diagnose test logs \(local-only\)\n(.*?)(?=^      - name:|\Z)",
            self.text,
        )
        self.assertIsNotNone(step, "validate.yml must retain local log diagnostics")
        assert step is not None
        self.assertRegex(step.group(1), r'(?m)^\s+ASHEN_AI_DIAGNOSE:\s*"false"\s*$')

    def test_checkout_does_not_persist_a_token(self) -> None:
        checkout = re.search(
            r"(?ms)^      - name: Checkout\n(.*?)(?=^      - name:|\Z)",
            self.text,
        )
        self.assertIsNotNone(checkout, "validate.yml must keep a checkout step")
        assert checkout is not None
        self.assertRegex(checkout.group(1), r"(?m)^\s+persist-credentials:\s*false\s*$")

    def test_workflow_and_job_have_read_only_contents_permission(self) -> None:
        self.assertIn("permissions:\n  contents: read", self.text)
        try:
            job_start = self.lines.index("  validate:")
        except ValueError:
            self.fail("validate job is missing")
        job_lines = []
        for line in self.lines[job_start + 1 :]:
            if line.startswith("  ") and not line.startswith("    "):
                break
            job_lines.append(line)
        self.assertIn("    permissions:", job_lines)
        self.assertIn("      contents: read", job_lines)


if __name__ == "__main__":
    unittest.main(verbosity=2)
