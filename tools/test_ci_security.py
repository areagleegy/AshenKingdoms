#!/usr/bin/env python3
"""Regression checks for credentials and least-privilege permissions in CI workflows."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = {
    "validate": ROOT / ".github" / "workflows" / "validate.yml",
    "build": ROOT / ".github" / "workflows" / "build.yml",
}


def _step_blocks(text: str, step_name: str) -> list[str]:
    """Return YAML step blocks by indentation, without matching across the full file."""
    lines = text.splitlines()
    blocks: list[str] = []
    prefix = f"      - name: {step_name}"
    index = 0
    while index < len(lines):
        if lines[index] != prefix:
            index += 1
            continue
        start = index
        index += 1
        while index < len(lines) and not lines[index].startswith("      - name: "):
            index += 1
        blocks.append("\n".join(lines[start:index]))
    return blocks


def _job_blocks(text: str) -> dict[str, str]:
    lines = text.splitlines()
    try:
        jobs_index = lines.index("jobs:")
    except ValueError:
        return {}
    starts: list[tuple[int, str]] = []
    for index in range(jobs_index + 1, len(lines)):
        match = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", lines[index])
        if match:
            starts.append((index, match.group(1)))
    result: dict[str, str] = {}
    for offset, (start, name) in enumerate(starts):
        end = starts[offset + 1][0] if offset + 1 < len(starts) else len(lines)
        result[name] = "\n".join(lines[start:end])
    return result


class WorkflowSecretIsolationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workflows = {
            name: path.read_text(encoding="utf-8")
            for name, path in WORKFLOWS.items()
        }

    def test_workflows_have_no_inline_secret_bindings(self) -> None:
        for name, text in self.workflows.items():
            with self.subTest(workflow=name):
                self.assertNotRegex(text, r"\$\{\{\s*secrets\.")
                self.assertNotRegex(
                    text,
                    r"(?m)^\s*ASHEN_AI_(?:ENDPOINT|API_KEY)\s*:",
                )

    def test_validation_diagnostics_are_explicitly_local_only(self) -> None:
        blocks = _step_blocks(self.workflows["validate"], "Diagnose test logs (local-only)")
        self.assertEqual(len(blocks), 1, "validate.yml must retain one local diagnostic step")
        self.assertRegex(blocks[0], r'(?m)^\s+ASHEN_AI_DIAGNOSE:\s*"false"\s*$')

    def test_every_checkout_disables_persisted_credentials(self) -> None:
        for name, text in self.workflows.items():
            with self.subTest(workflow=name):
                blocks = _step_blocks(text, "Checkout")
                self.assertGreater(len(blocks), 0, "workflow must have a checkout step")
                for block in blocks:
                    self.assertRegex(
                        block,
                        r"(?m)^\s+persist-credentials:\s*false\s*$",
                    )

    def test_each_job_has_explicit_read_only_contents_permission(self) -> None:
        for name, text in self.workflows.items():
            with self.subTest(workflow=name):
                jobs = _job_blocks(text)
                self.assertGreater(len(jobs), 0, "workflow must define jobs")
                for job_name, block in jobs.items():
                    with self.subTest(job=job_name):
                        self.assertIn("    permissions:", block)
                        self.assertIn("      contents: read", block)

    def test_workflow_level_permissions_are_read_only(self) -> None:
        for name, text in self.workflows.items():
            with self.subTest(workflow=name):
                self.assertRegex(text, r"(?m)^permissions:\n  contents: read\s*$")


if __name__ == "__main__":
    unittest.main(verbosity=2)
