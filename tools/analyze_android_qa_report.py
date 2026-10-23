#!/usr/bin/env python3
"""Offline-first analyzer for AshenKingdoms Android QA JSON reports.

No external request is made unless --ollama-model is explicitly supplied.
Optional model assistance is restricted to a local Ollama listener on 127.0.0.1.
"""
from __future__ import annotations

import argparse
import json
import math
import re
import statistics
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

REPORT_TYPE = "ashenkingdoms.android_qa"
SAFE_ID = re.compile(r"^[a-z][a-z0-9_.-]{0,63}$")
SAFE_MODEL = re.compile(r"^[A-Za-z0-9._:-]{1,100}$")
MAX_REPORT_BYTES = 5 * 1024 * 1024


def _number(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    result = float(value)
    return result if math.isfinite(result) else None


def _safe_id(value: Any) -> str:
    candidate = str(value)
    return candidate if SAFE_ID.fullmatch(candidate) else "invalid_id"


def _finding(finding_id: str, severity: str, title: str,
             evidence: dict[str, Any], action: str) -> dict[str, Any]:
    return {
        "id": finding_id,
        "severity": severity,
        "title": title,
        "evidence": evidence,
        "recommended_action": action,
    }


def analyze_report(report: dict[str, Any], minimum_fps: float = 30.0,
                   critical_fps: float = 15.0,
                   maximum_frame_ms: float = 33.3) -> dict[str, Any]:
    """Analyze an exported QA report using explainable offline rules."""
    if report.get("report_type") != REPORT_TYPE:
        raise ValueError(f"Unsupported report_type; expected {REPORT_TYPE}")
    if report.get("schema_version") != 1:
        raise ValueError("Unsupported or missing QA report schema_version")
    if critical_fps <= 0 or minimum_fps < critical_fps or maximum_frame_ms <= 0:
        raise ValueError("Invalid performance thresholds")

    findings: list[dict[str, Any]] = []
    build = report.get("build", {})
    if not isinstance(build, dict):
        build = {}

    if build.get("qa_tools") is not True:
        findings.append(_finding(
            "not_a_qa_build", "critical", "التقرير لا يثبت أنه صادر عن بناء QA",
            {"qa_tools": bool(build.get("qa_tools", False))},
            "أعد التصدير وتثبيت Android QA APK المخصص، ولا تستخدم APK العادي لهذا الفحص.",
        ))
    if build.get("android") is not True:
        findings.append(_finding(
            "not_android_runtime", "high", "بيئة التقرير ليست Android مؤكدة",
            {"android": bool(build.get("android", False))},
            "أعد جمع التقرير من جهاز Android الفعلي المستهدف.",
        ))

    raw_tests = report.get("test_results", [])
    tests = raw_tests if isinstance(raw_tests, list) else []
    normalized_tests: list[dict[str, Any]] = []
    for item in tests:
        if not isinstance(item, dict):
            continue
        status = item.get("status")
        if status not in {"pass", "fail", "skip"}:
            continue
        normalized_tests.append({
            "id": _safe_id(item.get("id", "")),
            "status": status,
            "duration_ms": max(0, int(_number(item.get("duration_ms")) or 0)),
            "error_code": int(_number(item.get("error_code")) or 0),
        })

    failed_tests = [item for item in normalized_tests if item["status"] == "fail"]
    skipped_tests = [item for item in normalized_tests if item["status"] == "skip"]
    passed_tests = [item for item in normalized_tests if item["status"] == "pass"]

    for item in failed_tests:
        test_id = item["id"]
        severity = "high" if test_id.startswith(("combat_", "dialogue_", "quest_")) else "medium"
        findings.append(_finding(
            f"test_failed_{test_id}", severity, f"فشل اختبار: {test_id}",
            {"test_id": test_id, "error_code": item["error_code"], "duration_ms": item["duration_ms"]},
            "أعد تشغيل الاختبار منفردًا على نفس البناء، واحتفظ بالتقرير والسجل المقابل قبل تغيير الكود.",
        ))

    if not normalized_tests:
        findings.append(_finding(
            "no_test_results", "high", "التقرير لا يحتوي نتائج اختبارات",
            {"test_count": 0},
            "شغّل زر فحص QA داخل التطبيق وتأكد من أن التقرير صادر بعد انتهاء الفحص.",
        ))

    raw_events = report.get("events", [])
    events = [item for item in raw_events if isinstance(item, dict)] if isinstance(raw_events, list) else []
    event_counts: dict[str, int] = {}
    performance_samples: list[dict[str, Any]] = []
    for event in events:
        name = _safe_id(event.get("event", ""))
        event_counts[name] = event_counts.get(name, 0) + 1
        details = event.get("details", {})
        if name == "performance_sample" and isinstance(details, dict):
            performance_samples.append(details)

    fps_values = [v for sample in performance_samples if (v := _number(sample.get("fps"))) is not None and v > 0]
    frame_times = [v for sample in performance_samples if (v := _number(sample.get("process_ms"))) is not None and v >= 0]
    memory_values = [v for sample in performance_samples if (v := _number(sample.get("static_memory_mb"))) is not None and v >= 0]
    metrics: dict[str, Any] = {
        "performance_sample_count": len(performance_samples),
        "valid_fps_sample_count": len(fps_values),
        "median_fps": round(statistics.median(fps_values), 2) if fps_values else None,
        "minimum_fps": round(min(fps_values), 2) if fps_values else None,
        "average_fps": round(statistics.fmean(fps_values), 2) if fps_values else None,
        "max_process_ms": round(max(frame_times), 2) if frame_times else None,
        "peak_static_memory_mb": round(max(memory_values), 2) if memory_values else None,
    }

    if len(fps_values) < 3:
        findings.append(_finding(
            "insufficient_performance_samples", "medium", "عدد عينات الأداء لا يكفي للحكم على الاستقرار",
            {"valid_fps_sample_count": len(fps_values), "minimum_for_analysis": 3},
            "شغّل اللعبة على الهاتف عدة دقائق وصدّر التقرير بعد تسجيل ثلاث عينات أداء صالحة على الأقل.",
        ))
    elif metrics["median_fps"] < critical_fps:
        findings.append(_finding(
            "critical_low_fps", "high", "معدل الإطارات الوسيط منخفض جدًا",
            {"median_fps": metrics["median_fps"], "threshold_fps": critical_fps, "samples": len(fps_values)},
            "كرر القياس بعد تحميل المشهد، ثم افحص كثافة المشهد والمواد والإضاءة وعدد الأعداء وزمن CPU/GPU على الجهاز نفسه.",
        ))
    elif metrics["median_fps"] < minimum_fps:
        findings.append(_finding(
            "low_fps", "medium", "معدل الإطارات الوسيط أقل من هدف الفرز الأولي",
            {"median_fps": metrics["median_fps"], "threshold_fps": minimum_fps, "samples": len(fps_values)},
            "قارن المشهد الهادئ بمشهد القتال، وخفّض حمل الرسم/الذكاء الاصطناعي فقط بعد تحديد سبب قابل للقياس.",
        ))

    slow_frames = [value for value in frame_times if value > maximum_frame_ms]
    if len(slow_frames) >= 2:
        findings.append(_finding(
            "repeated_slow_frames", "medium", "تكررت عينات زمن معالجة الإطار المرتفع",
            {"samples_over_threshold": len(slow_frames), "total_frame_time_samples": len(frame_times),
             "threshold_ms": maximum_frame_ms, "max_process_ms": round(max(slow_frames), 2)},
            "أعد القياس في مشهد اللعب والقتال؛ هذه إشارة فرز وليست وحدها تشخيصًا نهائيًا لعنق الزجاجة.",
        ))

    if event_counts.get("combat.player_attack_started", 0) == 0:
        findings.append(_finding(
            "no_live_combat_observed", "info", "لم تُسجّل ضربة لاعب فعلية أثناء جلسة الهاتف",
            {"attack_events": 0},
            "افتح اللعب الفردي، وهاجم عدوًا ثم جرّب هجومًا لا يصيب هدفًا، وبعدها أعد تصدير التقرير.",
        ))
    if event_counts.get("dialogue_started", 0) == 0:
        findings.append(_finding(
            "no_live_dialogue_observed", "info", "لم يُسجّل بدء حوار فعلي في جلسة الهاتف",
            {"dialogue_start_events": 0},
            "تحدث إلى شخصية غير قابلة للعب، اختر إجابة، وتحقق من أثر المهمة/العَلَم ثم أعد التصدير.",
        ))

    skipped_ids = [item["id"] for item in skipped_tests]
    if skipped_ids:
        findings.append(_finding(
            "manual_acceptance_pending", "info", "بوابات قبول يدوية لم تُنفذ بعد",
            {"skipped_count": len(skipped_ids), "test_ids": skipped_ids},
            "نفّذ السيناريوهات على الهاتف كما في دليل QA، ولا تعتبر العناصر المتخطاة اختبارات ناجحة.",
        ))

    if failed_tests or any(item["severity"] in {"critical", "high"} for item in findings):
        readiness = "blocked"
    elif any(item["severity"] == "medium" for item in findings):
        readiness = "needs_review"
    elif skipped_tests or any(item["severity"] == "info" for item in findings):
        readiness = "evidence_incomplete"
    else:
        readiness = "passed_within_scope"

    build_summary = {
        "commit": str(build.get("commit", "unknown"))[:64],
        "project_version": str(build.get("project_version", "unknown"))[:64],
        "godot_version": str(build.get("godot_version", "unknown"))[:32],
        "android": build.get("android") is True,
        "qa_tools": build.get("qa_tools") is True,
    }
    return {
        "analysis_schema_version": 1,
        "analyzer": "ashen_android_qa_offline_rules",
        "readiness": readiness,
        "build": build_summary,
        "session_duration_seconds": max(0.0, _number(report.get("session_duration_seconds")) or 0.0),
        "metrics": metrics,
        "tests": {
            "total": len(normalized_tests),
            "passed": len(passed_tests),
            "failed": len(failed_tests),
            "skipped": len(skipped_tests),
        },
        "event_counts": event_counts,
        "findings": findings,
        "ai_advice": None,
        "limitations": [
            "التحليل الخوارزمي لا يثبت اكتمال جميع الأنظمة أو جاهزية الإصدار.",
            "قياسات FPS والذاكرة وزمن الإطار لا تحدد وحدها سبب البطء ولا تقيس حرارة الجهاز.",
            "السيناريوهات اليدوية المتخطاة تتطلب تنفيذًا موثقًا على جهاز حقيقي.",
            "لا يوجد اتصال شبكي أو طلب AI سحابي افتراضيًا.",
        ],
    }


def request_local_ai(analysis: dict[str, Any], model: str, timeout: float = 15.0) -> str:
    """Optional advice from local Ollama only; never sends the full report."""
    if not SAFE_MODEL.fullmatch(model):
        raise ValueError("Invalid local model name")
    safe_findings = [
        {
            "id": item["id"],
            "severity": item["severity"],
            "title": item["title"],
            "evidence": item["evidence"],
            "recommended_action": item["recommended_action"],
        }
        for item in analysis.get("findings", [])
        if isinstance(item, dict)
    ]
    payload = {
        "model": model,
        "stream": False,
        "prompt": (
            "أنت محلل QA للعبة Godot. حلل النتائج المنظمة التالية فقط. "
            "قدّم حتى 6 خطوات تحقق مرتبة بالعربية. لا تدّع أن اختبارًا يدويًا نجح دون دليل. "
            "لا تقترح إصلاح الكود تلقائيًا، ولا تضف وقائع غير موجودة.\n"
            + json.dumps({
                "readiness": analysis.get("readiness"),
                "metrics": analysis.get("metrics", {}),
                "tests": analysis.get("tests", {}),
                "findings": safe_findings,
            }, ensure_ascii=False)
        ),
        "options": {"temperature": 0.1},
    }
    request = urllib.request.Request(
        "http://127.0.0.1:11434/api/generate",
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read(256 * 1024).decode("utf-8", errors="replace")
    except (OSError, urllib.error.URLError) as exc:
        raise RuntimeError("Local Ollama is unavailable; offline rule analysis is still valid.") from exc
    result = json.loads(raw)
    advice = result.get("response")
    if not isinstance(advice, str) or not advice.strip():
        raise RuntimeError("Local AI returned an empty or unsupported response.")
    return advice.strip()[:12000]


def render_markdown(analysis: dict[str, Any]) -> str:
    metrics = analysis["metrics"]
    tests = analysis["tests"]
    lines = [
        "# تقرير تحليل QA — ممالك الرماد",
        "",
        f"نتيجة الفرز: {analysis['readiness']}",
        f"Commit: {analysis['build']['commit']}",
        f"Android QA: {analysis['build']['android']} / qa_tools: {analysis['build']['qa_tools']}",
        f"مدة الجلسة: {analysis['session_duration_seconds']:.1f} ثانية",
        "",
        "## الاختبارات",
        f"- المنفذة: {tests['total']} — نجح: {tests['passed']} — فشل: {tests['failed']} — متخطى/يدوي: {tests['skipped']}",
        "",
        "## الأداء المرصود",
        f"- عدد عينات الأداء: {metrics['performance_sample_count']}",
        f"- متوسط FPS: {metrics['average_fps']}",
        f"- وسيط FPS: {metrics['median_fps']}",
        f"- أقل FPS: {metrics['minimum_fps']}",
        f"- أقصى زمن process: {metrics['max_process_ms']} ms",
        f"- ذروة الذاكرة الساكنة المسجلة: {metrics['peak_static_memory_mb']} MB",
        "",
        "## النتائج والتوصيات",
    ]
    if not analysis["findings"]:
        lines.append("- لا توجد قاعدة تشخيصية أطلقت نتيجة في نطاق التقرير الحالي؛ هذا ليس اعتمادًا للإصدار.")
    else:
        for item in analysis["findings"]:
            lines.extend([
                f"### [{item['severity']}] {item['title']}",
                f"- الرمز: {item['id']}",
                f"- الدليل: {json.dumps(item['evidence'], ensure_ascii=False, sort_keys=True)}",
                f"- الخطوة التالية: {item['recommended_action']}",
                "",
            ])
    if analysis.get("ai_advice"):
        lines.extend(["## رأي النموذج المحلي (استشاري فقط)", str(analysis["ai_advice"]), ""])
    lines.extend([
        "## الحدود",
        "- التحليل الخوارزمي محلي ومفسر، ولا يتصل بأي خدمة سحابية.",
        "- مساعد النموذج اختياري؛ عند تفعيله يستخدم Ollama على 127.0.0.1 فقط ويرسل ملخصًا منقحًا لا تقرير الجلسة الخام.",
        "- نتيجة الفرز لا تستبدل مراجعة المطور أو فحص الهاتف واللعب اليدوي.",
        "",
    ])
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path, help="JSON file copied/exported by Android QA APK")
    parser.add_argument("--json-output", type=Path, help="Analysis JSON destination")
    parser.add_argument("--markdown-output", type=Path, help="Human-readable report destination")
    parser.add_argument("--min-fps-warning", type=float, default=30.0)
    parser.add_argument("--critical-fps", type=float, default=15.0)
    parser.add_argument("--max-frame-ms", type=float, default=33.3)
    parser.add_argument("--ollama-model", help="Optional model already installed in local Ollama; no cloud AI")
    args = parser.parse_args(argv)

    if not args.report.is_file():
        print(f"ERROR: report file not found: {args.report}", file=sys.stderr)
        return 2
    if args.report.stat().st_size > MAX_REPORT_BYTES:
        print(f"ERROR: report exceeds {MAX_REPORT_BYTES} bytes", file=sys.stderr)
        return 2
    try:
        report = json.loads(args.report.read_text(encoding="utf-8"))
        if not isinstance(report, dict):
            raise ValueError("Report JSON root must be an object")
        analysis = analyze_report(report, args.min_fps_warning, args.critical_fps, args.max_frame_ms)
        if args.ollama_model:
            analysis["ai_advice"] = request_local_ai(analysis, args.ollama_model)
    except (OSError, json.JSONDecodeError, ValueError, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    json_path = args.json_output or args.report.with_name(args.report.stem + ".analysis.json")
    markdown_path = args.markdown_output or args.report.with_name(args.report.stem + ".analysis.md")
    json_path.write_text(json.dumps(analysis, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    markdown_path.write_text(render_markdown(analysis), encoding="utf-8")
    print(f"Readiness: {analysis['readiness']}")
    print(f"Findings: {len(analysis['findings'])}")
    print(f"JSON: {json_path}")
    print(f"Markdown: {markdown_path}")
    print("AI mode: local Ollama" if args.ollama_model else "AI mode: disabled; offline rules only")
    return 1 if analysis["readiness"] == "blocked" else 0


if __name__ == "__main__":
    raise SystemExit(main())
