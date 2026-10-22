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

    def test_validation_workflow_has_no_ai_secret_bindings(self) -> None:
        self.assertNotRegex(self.text, r"\$\{\{\s*secrets\.ASHEN_AI_(?:ENDPOINT|API_KEY)\s*\}\}")
        self.assertNotRegex(self.text, r"(?m)^\s*ASHEN_AI_(?:ENDPOINT|API_KEY)\s*:")

    def test_remote_ai_diagnostics_are_explicitly_disabled(self) -> None:
        step = re.search(
            r"(?ms)^\s*-\s*name:\s*Diagnose test logs \(local-only\).*?(?=^\s*-\s*name:|\Z)",
            self.text,
        )
        self.assertIsNotNone(step, "validate.yml must retain local log diagnostics")
        assert step is not None
        self.assertRegex(step.group(0), r'(?m)^\s+ASHEN_AI_DIAGNOSE:\s*"false"\s*$')

    def test_checkout_does_not_persist_a_token(self) -> None:
        checkout = re.search(
            r"(?ms)^\s*-\s*name:\s*Checkout.*?(?=^\s*-\s*name:|\Z)",
            self.text,
        )
        self.assertIsNotNone(checkout)
        assert checkout is not None
        self.assertRegex(checkout.group(0), r"(?m)^\s+persist-credentials:\s*false\s*$")

    def test_workflow_and_job_have_read_only_contents_permission(self) -> None:
        self.assertRegex(self.text, r"(?m)^permissions:\n\s+contents:\s*read\s*$")
        self.assertRegex(self.text, r"(?ms)^  validate:\n(?:.*\n)*?    permissions:\n      contents:\s*read\s+")


if __name__ == "__main__":
    unittest.main(verbosity=2)
