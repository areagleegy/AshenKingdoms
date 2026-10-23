#!/usr/bin/env python3
"""Deterministic test-lab runner for AshenKingdoms; no automatic code changes."""
from __future__ import annotations
import argparse, json, os, re, subprocess, sys, time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "tools" / "test_lab_scenarios.json"
COMMANDS: dict[str, list[str]] = {
    "diagnostics_unit": [sys.executable, "-m", "unittest", "discover", "-s", "tools", "-p", "test_ai_test_diagnostics.py", "-v"],
    "diagnostics_benchmark": [sys.executable, "tools/diagnostic_benchmark.py", "--corpus", "tools/diagnostic_cases.json", "--output", "test-lab-diagnostic-benchmark.json"],
    "docs_links": [sys.executable, "tools/validate_docs.py"],
    "asset_licenses": [sys.executable, "tools/validate_free_assets.py"],
    "content_python": [sys.executable, "-m", "unittest", "tools.test_package_content", "tools.test_sign_content_catalog", "-v"],
    "godot_import": ["godot", "--headless", "--path", ".", "--editor", "--quit"],
    "web_export": ["bash", "tools/test_lab_export.sh", "web"],
    "android_export": ["bash", "tools/test_lab_export.sh", "android"],
    "script_load": ["godot", "--headless", "--path", ".", "--script", "res://tests/script_load_smoke_test.gd"],
    "gameplay_smoke": ["godot", "--headless", "--path", ".", "--script", "res://tests/gameplay_smoke_test.gd"],
    "gameplay_regression": ["godot", "--headless", "--path", ".", "--script", "res://tests/gameplay_regression_test.gd"],
    "player_smoke": ["godot", "--headless", "--path", ".", "--script", "res://tests/player_character_smoke_test.gd"],
    "network_combat": ["timeout", "45s", "godot", "--headless", "--path", ".", "res://tests/network_combat_smoke_test.tscn"],
    "enet_loopback": ["bash", "tools/test-network-loopback.sh"],
    "content_catalog": ["godot", "--headless", "--path", ".", "--script", "res://tests/content_catalog_smoke_test.gd"],
}
SECRET_PATTERNS = [
    (re.compile(r"(?i)(authorization\s*:\s*bearer\s+)[^\s,;]+"), r"\1[REDACTED]"),
    (re.compile(r"(?i)((?:api[_-]?key|access[_-]?token|password|secret)\s*[=:]\s*)[^\s,;]+"), r"\1[REDACTED]"),
    (re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{16,})\b"), "[REDACTED_TOKEN]"),
]

def redact(text: str) -> str:
    for pattern, replacement in SECRET_PATTERNS:
        text = pattern.sub(replacement, text)
    for name in ("GITHUB_TOKEN", "ASHEN_AI_API_KEY"):
        secret = os.environ.get(name, "")
        if len(secret) >= 8:
            text = text.replace(secret, "[REDACTED_TOKEN]")
    return text

def load_catalog(path: Path = CATALOG_PATH) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schema_version") != 1 or not isinstance(data.get("scenarios"), list):
        raise ValueError("Unsupported or malformed test-lab catalog")
    ids: set[str] = set()
    for item in data["scenarios"]:
        if not isinstance(item, dict) or not isinstance(item.get("id"), str):
            raise ValueError("Every scenario needs a string id")
        if item["id"] in ids:
            raise ValueError(f"Duplicate scenario id: {item['id']}")
        ids.add(item["id"])
        if item.get("kind") == "automated":
            command = item.get("command")
            if command not in COMMANDS:
                raise ValueError(f"Unknown command for scenario {item['id']}: {command}")
        elif item.get("kind") != "manual" or item.get("command") is not None:
            raise ValueError(f"Invalid scenario kind/command: {item['id']}")
    by_id = {item["id"]: item for item in data["scenarios"]}
    for profile, selected in data.get("profiles", {}).items():
        unknown = set(selected) - ids
        if unknown:
            raise ValueError(f"Profile {profile} references unknown scenarios: {sorted(unknown)}")
        for sid in selected:
            if by_id[sid].get("kind") != "automated":
                raise ValueError(f"Profile {profile} includes non-automated scenario {sid}")
    return data

def run_scenario(item: dict[str, Any], timeout_seconds: int, log_dir: Path) -> dict[str, Any]:
    sid = item["id"]
    log_path = log_dir / f"{sid}.log"
    command = COMMANDS[item["command"]]
    env = os.environ.copy()
    env["GODOT_SILENCE_ROOT_WARNING"] = "1"
    started = time.monotonic()
    result: dict[str, Any] = {
        "id": sid, "area": item["area"], "status": "failed",
        "command": command, "log": str(log_path), "timeout_seconds": timeout_seconds,
    }
    try:
        proc = subprocess.run(command, cwd=ROOT, env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=timeout_seconds, check=False)
        output = redact(proc.stdout or "")
        log_path.write_text(output, encoding="utf-8")
        result.update(exit_code=proc.returncode, status="passed" if proc.returncode == 0 else "failed")
        result["summary"] = output[-1600:]
    except subprocess.TimeoutExpired as exc:
        partial = exc.stdout or ""
        if isinstance(partial, bytes):
            partial = partial.decode("utf-8", errors="replace")
        output = redact(partial + f"\nTEST LAB TIMEOUT after {timeout_seconds}s")
        log_path.write_text(output, encoding="utf-8")
        result.update(exit_code=None, status="timeout", summary=output[-1600:])
    except OSError as exc:
        output = f"TEST LAB EXECUTION ERROR: {type(exc).__name__}: {exc}"
        log_path.write_text(redact(output), encoding="utf-8")
        result.update(exit_code=None, status="error", summary=output)
    result["duration_seconds"] = round(time.monotonic() - started, 3)
    return result

def make_report(catalog: dict[str, Any], profile: str, results: list[dict[str, Any]]) -> dict[str, Any]:
    selected = catalog["profiles"][profile]
    manual = [s for s in catalog["scenarios"] if s["kind"] == "manual"]
    counts = {state: sum(r["status"] == state for r in results) for state in ("passed", "failed", "timeout", "error")}
    failed = counts["failed"] + counts["timeout"] + counts["error"]
    result_ids = [r.get("id") for r in results]
    complete = len(results) == len(selected) and len(result_ids) == len(set(result_ids)) and set(result_ids) == set(selected)
    diagnostic_lines = []
    for item in results:
        if item["status"] != "passed":
            diagnostic_lines.extend(str(item.get("summary", "")).splitlines())
    try:
        from ai_test_diagnostics import classify_text
        ai_diagnostics = classify_text("\n".join(diagnostic_lines)) if diagnostic_lines else []
    except Exception as exc:
        ai_diagnostics = [{"category": "diagnostics_unavailable", "severity": "low", "reason": type(exc).__name__}]
    return {
        "schema_version": 1, "project": catalog.get("project", "unknown"),
        "profile": profile, "generated_at": datetime.now(timezone.utc).isoformat(),
        "overall_status": "passed" if failed == 0 and complete else "failed",
        "counts": {**counts, "automated_total": len(results), "manual_not_run": len(manual)},
        "results": results,
        "ai_diagnostics": ai_diagnostics,
        "manual_scenarios_not_run": [
            {"id": s["id"], "area": s["area"], "purpose": s["purpose"], "acceptance": s["acceptance"]}
            for s in manual
        ],
        "limitations": [
            "نجاح الفحوص الآلية لا يثبت قبول هاتف Android أو المتصفح أو الشبكة العامة.",
            "السيناريوهات اليدوية معروضة ولا تُعلَن ناجحة تلقائيًا.",
            "لا يصلح المختبر الكود تلقائيًا؛ أي إصلاح يحتاج تغييرًا واختبارًا قابلين للمراجعة.",
        ],
    }

def render_markdown(report: dict[str, Any]) -> str:
    c = report["counts"]
    lines = [
        "# AshenKingdoms — Test Lab / AI-assisted diagnostics", "",
        f"- Profile: **{report['profile']}**",
        f"- Overall: **{report['overall_status']}**",
        f"- Automated: {c['passed']} passed, {c['failed']} failed, {c['timeout']} timeout, {c['error']} execution errors.",
        f"- Manual acceptance scenarios not run: {c['manual_not_run']}", "",
        "| Scenario | Area | Result | Seconds |", "|---|---|---:|---:|",
    ]
    for r in report["results"]:
        lines.append(f"| {r['id']} | {r['area']} | **{r['status']}** | {r.get('duration_seconds', 0):.3f} |")
    if report.get("ai_diagnostics"):
        lines.extend(["", "## AI-assisted local diagnostics (advisory)", ""])
        for finding in report["ai_diagnostics"][:8]:
            lines.append(f"- {finding.get('title', finding.get('category', 'diagnostic'))} — {finding.get('severity', 'unknown')}: {finding.get('recommended_action', finding.get('reason', ''))}")
    if any(r["status"] != "passed" for r in report["results"]):
        lines.extend(["", "## Failed or incomplete checks", ""])
        for r in report["results"]:
            if r["status"] != "passed":
                lines.extend([f"### {r['id']} — {r['status']}", f"Log: {r['log']}", "---", r.get("summary", "")[-1200:], "---", ""])
    lines.extend(["", "## Manual acceptance still required", ""])
    for s in report["manual_scenarios_not_run"]:
        lines.extend([f"### {s['id']} — {s['area']}", s["purpose"], f"**Acceptance:** {s['acceptance']}", ""])
    lines.extend(["## Limits", *[f"- {x}" for x in report["limitations"]], ""])
    return "\n".join(lines)

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=("python", "ci"), default="python")
    parser.add_argument("--timeout", type=int, default=180, help="Per-scenario timeout in seconds.")
    parser.add_argument("--output-dir", default="test-lab-results")
    parser.add_argument("--report", default="test-lab-report.json")
    parser.add_argument("--markdown", default="test-lab-report.md")
    parser.add_argument("--list", action="store_true", help="List scenarios without running them.")
    args = parser.parse_args()
    if args.timeout < 1:
        parser.error("--timeout must be positive")
    catalog = load_catalog()
    if args.list:
        print(json.dumps({"profiles": catalog["profiles"], "scenarios": catalog["scenarios"]}, ensure_ascii=False, indent=2))
        return 0
    log_dir = (ROOT / args.output_dir).resolve()
    log_dir.mkdir(parents=True, exist_ok=True)
    selected = set(catalog["profiles"][args.profile])
    results = []
    for item in catalog["scenarios"]:
        if item["id"] not in selected:
            continue
        print(f"[RUN] {item['id']} — {item['purpose']}", flush=True)
        result = run_scenario(item, args.timeout, log_dir)
        results.append(result)
        print(f"[{result['status'].upper()}] {item['id']} ({result['duration_seconds']}s)", flush=True)
    report = make_report(catalog, args.profile, results)
    report_path = (ROOT / args.report).resolve()
    markdown_path = (ROOT / args.markdown).resolve()
    report_path.parent.mkdir(parents=True, exist_ok=True)
    markdown_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    markdown_path.write_text(render_markdown(report), encoding="utf-8")
    print(render_markdown(report))
    return 0 if report["overall_status"] == "passed" else 1

if __name__ == "__main__":
    sys.exit(main())
