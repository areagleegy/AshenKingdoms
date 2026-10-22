extends SceneTree

const ReporterScript: Script = preload("res://scripts/qa/qa_reporter.gd")
const REPORT_DIRECTORY := "user://qa_reports"
const CHECKPOINT_A := "user://qa_reports/qa_session_checkpoint_a.json"
const CHECKPOINT_B := "user://qa_reports/qa_session_checkpoint_b.json"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ReporterScript.can_instantiate():
		push_error("QA reporter script failed to compile and cannot be instantiated.")
		quit(1)
		return

	var reporter := ReporterScript.new() as Node
	root.add_child(reporter)
	reporter.set("_enabled", true)

	reporter.call("record_event", "test_initial_event", {
		"safe_count": 7,
		"private_text": "must-not-appear-in-report",
	})
	var initial_report: Dictionary = reporter.call("build_report")
	_check(initial_report.get("report_type") == "ashenkingdoms.android_qa", "report type is stable")
	_check(bool((initial_report.get("safety", {}) as Dictionary).get("automatic_upload", true)) == false, "automatic upload is disabled")
	_check(str(reporter.call("get_report_json")).contains("must-not-appear-in-report") == false, "free-form text is not stored in event details")
	_check(int((initial_report.get("events", []) as Array).size()) >= 1, "structured event is recorded")

	reporter.call("set_test_results", [{
		"id": "scene_main",
		"status": "pass",
		"duration_ms": 12,
		"error_code": 0,
		"diagnostic_text": "must-not-appear-in-report",
	}])
	var report_with_tests: Dictionary = reporter.call("build_report")
	var test_results: Array = report_with_tests.get("test_results", [])
	_check(test_results.size() == 1, "test result is included")
	_check(not JSON.stringify(test_results).contains("diagnostic_text"), "unapproved test-result fields are dropped")

	for index in range(340):
		# Isolate the buffer-cap test from periodic disk checkpoints; the
		# checkpoint and export paths are exercised separately above/below.
		reporter.set("_events_since_checkpoint", 0)
		reporter.call("record_event", "bounded_event", {"index": index})
	var bounded_report: Dictionary = reporter.call("build_report")
	var events: Array = bounded_report.get("events", [])
	_check(events.size() <= 300, "event history stays within its configured bound")
	_check(not JSON.stringify(bounded_report).contains("must-not-appear-in-report"), "sanitization remains active after checkpoint rotation")

	var export_result: Dictionary = reporter.call("export_report")
	_check(bool(export_result.get("ok", false)), "JSON report exports to app-local storage")
	var report_path := str(export_result.get("path", ""))
	if not report_path.is_empty() and FileAccess.file_exists(report_path):
		var file := FileAccess.open(report_path, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			file.close()
			_check(parsed is Dictionary, "exported report is valid JSON")
		else:
			_check(false, "exported report can be reopened")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(report_path))
	else:
		_check(false, "exported report exists")

	_clean_checkpoint(CHECKPOINT_A)
	_clean_checkpoint(CHECKPOINT_B)
	var reports_directory := ProjectSettings.globalize_path(REPORT_DIRECTORY)
	if DirAccess.dir_exists_absolute(reports_directory):
		DirAccess.remove_absolute(reports_directory)
	reporter.free()

	print("[qa-reporter] checks: %d, failures: %d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _clean_checkpoint(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % message)
	else:
		_failures += 1
		push_error("[FAIL] %s" % message)
