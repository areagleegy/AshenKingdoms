#!/usr/bin/env python3
"""Evaluate local diagnostic rules against a reviewed, labeled regression corpus."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Callable


def evaluate_cases(
    cases: list[dict[str, Any]],
    classifier: Callable[[str], list[dict[str, Any]]],
) -> dict[str, Any]:
    """Return deterministic corpus metrics; this evaluates rules, it does not train them."""
    seen: set[str] = set()
    positive = negative = hits = true_negative = 0
    missed: list[str] = []
    false_positive: list[str] = []
    per_case: list[dict[str, Any]] = []

    for case in cases:
        case_id = case.get("id")
        expected = case.get("expected_category")
        log = case.get("log")
        if not isinstance(case_id, str) or not case_id.strip():
            raise ValueError("each benchmark case requires a non-empty id")
        if case_id in seen:
            raise ValueError(f"duplicate benchmark case id: {case_id}")
        seen.add(case_id)
        if expected is not None and not isinstance(expected, str):
            raise ValueError(f"invalid expected_category for case {case_id}")
        if not isinstance(log, str):
            raise ValueError(f"invalid log for case {case_id}")

        findings = classifier(log)
        categories = sorted({item.get("category") for item in findings if item.get("category")})
        if expected is None:
            negative += 1
            is_correct = not findings
            if is_correct:
                true_negative += 1
            else:
                false_positive.append(case_id)
        else:
            positive += 1
            is_correct = expected in categories
            if is_correct:
                hits += 1
            else:
                missed.append(case_id)
        per_case.append({
            "id": case_id,
            "expected_category": expected,
            "predicted_categories": categories,
            "correct_for_expected_label": is_correct,
        })

    return {
        "schema_version": 1,
        "metric_type": "labeled_corpus_evaluation_not_model_training",
        "total_cases": len(cases),
        "positive_cases": positive,
        "negative_cases": negative,
        "detected_expected_category": hits,
        "missed_positive_cases": missed,
        "true_negative_cases": true_negative,
        "false_positive_cases": false_positive,
        "expected_category_recall_percent": round(100.0 * hits / positive, 2) if positive else None,
        "negative_case_specificity_percent": round(100.0 * true_negative / negative, 2) if negative else None,
        "cases": per_case,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", default="tools/diagnostic_cases.json")
    parser.add_argument("--output", default="diagnostic-benchmark.json")
    parser.add_argument("--summary", default="")
    args = parser.parse_args()

    # Support both direct script execution and package-style imports.
    try:
        from ai_test_diagnostics import classify_text
    except ModuleNotFoundError:
        from tools.ai_test_diagnostics import classify_text

    corpus = json.loads(Path(args.corpus).read_text(encoding="utf-8"))
    if not isinstance(corpus, dict) or not isinstance(corpus.get("cases"), list):
        raise ValueError("corpus must contain a cases array")
    report = evaluate_cases(corpus["cases"], classify_text)
    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    Path(args.output).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    lines = [
        "## AshenKingdoms — تقييم جودة التشخيص",
        "",
        f"- الحالات: {report['total_cases']}",
        f"- استدعاء الفئات المتوقعة: {report['expected_category_recall_percent']}%",
        f"- النوعية على الحالات السليمة: {report['negative_case_specificity_percent']}%",
        f"- الحالات الإيجابية الفائتة: {len(report['missed_positive_cases'])}",
        f"- الإنذارات الكاذبة على الحالات السليمة: {len(report['false_positive_cases'])}",
        "",
        "هذه مؤشرات على مجموعة اصطناعية صغيرة، وليست ضمانًا لأداء الإنتاج أو تدريبًا لنموذج.",
    ]
    if report["missed_positive_cases"]:
        lines.extend(["", "### حالات إيجابية فائتة", *[f"- {item}" for item in report["missed_positive_cases"]]])
    if report["false_positive_cases"]:
        lines.extend(["", "### إنذارات كاذبة", *[f"- {item}" for item in report["false_positive_cases"]]])
    markdown = "\n".join(lines) + "\n"
    print(markdown, end="")
    if args.summary:
        with Path(args.summary).open("a", encoding="utf-8") as stream:
            stream.write(markdown)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
