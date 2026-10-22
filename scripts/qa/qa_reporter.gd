extends Node

const QA_FEATURE := "qa_tools"
const MAX_EVENTS := 300
const MAX_PREVIOUS_SESSIONS := 3
const MAX_CHECKPOINT_BYTES := 512 * 1024
const SAMPLE_INTERVAL_SECONDS := 5.0
const CHECKPOINT_INTERVAL_SECONDS := 30.0
const CHECKPOINT_PATHS := [
	"user://qa_reports/qa_session_checkpoint_a.json",
	"user://qa_reports/qa_session_checkpoint_b.json",
]
const REPORT_DIRECTORY := "user://qa_reports"
const BUILD_COMMIT := "development"

var _enabled: bool = false
var _events: Array[Dictionary] = []
var _test_results: Array[Dictionary] = []
var _previous_sessions: Array[Dictionary] = []
var _event_name_regex: RegEx
var _detail_key_regex: RegEx
var _session_id: String = ""
var _session_started_at: String = ""
var _session_started_ticks: int = 0
var _last_scene_label: String = ""
var _sample_elapsed: float = 0.0
var _checkpoint_elapsed: float = 0.0
var _events_since_checkpoint: int = 0
var _active_checkpoint_slot: int = -1
var _fps_sum: float = 0.0
var _fps_samples: int = 0
var _fps_min: float = INF
var _fps_max: float = 0.0
var _peak_static_memory_mb: float = 0.0


func _init() -> void:
	_event_name_regex = RegEx.new()
	_event_name_regex.compile("^[a-z][a-z0-9_.-]{0,63}$")
	_detail_key_regex = RegEx.new()
	_detail_key_regex.compile("^[a-z][a-z0-9_]{0,31}$")


func _ready() -> void:
	_session_started_at = Time.get_datetime_string_from_system(true)
	_session_started_ticks = Time.get_ticks_msec()
	_session_id = "%d-%d" % [
		int(Time.get_unix_time_from_system()),
		_session_started_ticks,
	]
	_previous_sessions = _load_previous_sessions()
	_last_scene_label = _current_scene_label()
	_enabled = OS.has_feature(QA_FEATURE)
	set_process(_enabled)
	if not _enabled:
		return

	record_event("qa_session_started", {
		"android": OS.has_feature("android"),
		"debug_build": OS.has_feature("debug"),
	})
	_write_checkpoint()


func _process(delta: float) -> void:
	if not _enabled:
		return

	_sample_elapsed += delta
	_checkpoint_elapsed += delta
	var scene_label := _current_scene_label()
	if not scene_label.is_empty() and scene_label != _last_scene_label:
		_last_scene_label = scene_label
		record_event("scene_changed")

	if _sample_elapsed >= SAMPLE_INTERVAL_SECONDS:
		_sample_elapsed = 0.0
		_record_performance_sample()

	if _checkpoint_elapsed >= CHECKPOINT_INTERVAL_SECONDS:
		_checkpoint_elapsed = 0.0
		_write_checkpoint()


func record_event(event_name: String, details: Dictionary = {}) -> void:
	if not _enabled or not _is_safe_identifier(event_name, _event_name_regex):
		return

	var safe_details := _sanitize_details(details)
	_events.append({
		"at": Time.get_datetime_string_from_system(true),
		"elapsed_seconds": _elapsed_seconds(),
		"event": event_name,
		"scene": _current_scene_label(),
		"details": safe_details,
	})
	while _events.size() > MAX_EVENTS:
		_events.pop_front()

	_events_since_checkpoint += 1
	if _events_since_checkpoint >= 20:
		_events_since_checkpoint = 0
		_write_checkpoint()


func set_test_results(results: Array) -> void:
	if not _enabled:
		return

	_test_results.clear()
	for raw_result in results:
		if not raw_result is Dictionary:
			continue
		var test_id := str(raw_result.get("id", ""))
		var status := str(raw_result.get("status", ""))
		if not _is_safe_identifier(test_id, _event_name_regex):
			continue
		if status not in ["pass", "fail", "skip"]:
			continue

		var duration_value: Variant = raw_result.get("duration_ms", 0)
		var error_value: Variant = raw_result.get("error_code", 0)
		var duration_ms := max(0, int(duration_value)) if typeof(duration_value) in [TYPE_INT, TYPE_FLOAT] else 0
		var error_code := int(error_value) if typeof(error_value) in [TYPE_INT, TYPE_FLOAT] else 0
		_test_results.append({
			"id": test_id,
			"status": status,
			"duration_ms": duration_ms,
			"error_code": error_code,
		})

	_write_checkpoint()


func build_report() -> Dictionary:
	var version_info: Dictionary = Engine.get_version_info()
	return {
		"schema_version": 1,
		"report_type": "ashenkingdoms.android_qa",
		"generated_at": Time.get_datetime_string_from_system(true),
		"checkpoint_unix": int(Time.get_unix_time_from_system()),
		"session_id": _session_id,
		"session_started_at": _session_started_at,
		"session_duration_seconds": _elapsed_seconds(),
		"build": {
			"commit": BUILD_COMMIT,
			"project_name": str(ProjectSettings.get_setting("application/config/name", "AshenKingdoms")),
			"project_version": str(ProjectSettings.get_setting("application/config/version", "0.1.0")),
			"godot_version": str(version_info.get("string", "unknown")),
			"os_name": OS.get_name(),
			"android": OS.has_feature("android"),
			"qa_tools": OS.has_feature(QA_FEATURE),
			"debug_build": OS.has_feature("debug"),
		},
		"current_scene": _current_scene_label(),
		"performance": _performance_summary(),
		"test_results": _test_results.duplicate(true),
		"events": _events.duplicate(true),
		"previous_sessions": _previous_sessions.duplicate(true),
		"safety": {
			"local_only": true,
			"automatic_upload": false,
			"ai_requests_from_apk": false,
			"raw_dialogue_or_chat_recorded": false,
			"save_contents_recorded": false,
			"network_addresses_recorded": false,
			"event_limit": MAX_EVENTS,
		},
	}


func get_report_json() -> String:
	return JSON.stringify(build_report(), "\t")


func export_report() -> Dictionary:
	if not _enabled:
		return {"ok": false, "reason": "qa_feature_disabled"}

	var directory_path := ProjectSettings.globalize_path(REPORT_DIRECTORY)
	if not DirAccess.dir_exists_absolute(directory_path):
		var mkdir_error := DirAccess.make_dir_recursive_absolute(directory_path)
		if mkdir_error != OK:
			return {"ok": false, "reason": "directory_creation_failed", "error_code": mkdir_error}

	var report_path := REPORT_DIRECTORY.path_join(
		"qa_report_%d.json" % int(Time.get_unix_time_from_system())
	)
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		return {
			"ok": false,
			"reason": "report_open_failed",
			"error_code": FileAccess.get_open_error(),
		}

	file.store_string(get_report_json())
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return {"ok": false, "reason": "report_write_failed", "error_code": write_error}

	_write_checkpoint()
	return {"ok": true, "path": report_path}


func _record_performance_sample() -> void:
	var fps := float(Engine.get_frames_per_second())
	var memory_mb := float(Performance.get_monitor(Performance.MEMORY_STATIC)) / (1024.0 * 1024.0)
	_peak_static_memory_mb = maxf(_peak_static_memory_mb, memory_mb)

	if fps > 0.0:
		_fps_sum += fps
		_fps_samples += 1
		_fps_min = minf(_fps_min, fps)
		_fps_max = maxf(_fps_max, fps)

	record_event("performance_sample", {
		"fps": fps,
		"static_memory_mb": memory_mb,
		"process_ms": float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0,
		"physics_process_ms": float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0,
	})


func _performance_summary() -> Dictionary:
	return {
		"sample_count": _fps_samples,
		"average_fps": _fps_sum / float(_fps_samples) if _fps_samples > 0 else 0.0,
		"minimum_fps": _fps_min if _fps_samples > 0 else 0.0,
		"maximum_fps": _fps_max,
		"peak_static_memory_mb": _peak_static_memory_mb,
	}


func _load_previous_sessions() -> Array[Dictionary]:
	var latest_report: Dictionary = {}
	var latest_slot := -1
	for index in range(CHECKPOINT_PATHS.size()):
		var parsed := _read_checkpoint(CHECKPOINT_PATHS[index])
		if parsed.is_empty():
			continue
		if latest_report.is_empty() or int(parsed.get("checkpoint_unix", 0)) >= int(latest_report.get("checkpoint_unix", 0)):
			latest_report = parsed
			latest_slot = index

	_active_checkpoint_slot = latest_slot
	if latest_report.is_empty():
		return []

	var recovered: Array[Dictionary] = []
	var latest_snapshot := _snapshot_from_report(latest_report)
	if not latest_snapshot.is_empty():
		recovered.append(latest_snapshot)

	var raw_previous: Variant = latest_report.get("previous_sessions", [])
	if raw_previous is Array:
		for raw_snapshot in raw_previous:
			if recovered.size() >= MAX_PREVIOUS_SESSIONS:
				break
			if not raw_snapshot is Dictionary:
				continue
			var snapshot := _sanitize_session_snapshot(raw_snapshot)
			if not snapshot.is_empty() and not _contains_session(recovered, str(snapshot.get("session_id", ""))):
				recovered.append(snapshot)

	return recovered.slice(0, MAX_PREVIOUS_SESSIONS)


func _read_checkpoint(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	if file.get_length() > MAX_CHECKPOINT_BYTES:
		file.close()
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _snapshot_from_report(report: Dictionary) -> Dictionary:
	if not report.has("session_id"):
		return {}
	return _sanitize_session_snapshot({
		"session_id": report.get("session_id", ""),
		"session_started_at": report.get("session_started_at", ""),
		"session_duration_seconds": report.get("session_duration_seconds", 0.0),
		"current_scene": report.get("current_scene", ""),
		"performance": report.get("performance", {}),
		"events": report.get("events", []),
		"recovered_from_checkpoint": true,
	})


func _sanitize_session_snapshot(raw: Dictionary) -> Dictionary:
	var session_id := str(raw.get("session_id", "")).substr(0, 80)
	if session_id.is_empty():
		return {}

	var safe_events: Array[Dictionary] = []
	var raw_events: Variant = raw.get("events", [])
	if raw_events is Array:
		for raw_event in raw_events:
			if safe_events.size() >= MAX_EVENTS:
				break
			if raw_event is Dictionary:
				var safe_event := _sanitize_event_snapshot(raw_event)
				if not safe_event.is_empty():
					safe_events.append(safe_event)

	var raw_performance: Variant = raw.get("performance", {})
	var performance: Dictionary = _sanitize_numeric_dictionary(raw_performance) if raw_performance is Dictionary else {}
	return {
		"session_id": session_id,
		"session_started_at": str(raw.get("session_started_at", "")).substr(0, 64),
		"session_duration_seconds": maxf(0.0, float(raw.get("session_duration_seconds", 0.0))),
		"current_scene": str(raw.get("current_scene", "")).substr(0, 64),
		"performance": performance,
		"events": safe_events,
		"recovered_from_checkpoint": bool(raw.get("recovered_from_checkpoint", false)) or bool(raw.get("recovered_from_checkpoint", true)),
	}


func _sanitize_event_snapshot(raw: Dictionary) -> Dictionary:
	var event_name := str(raw.get("event", ""))
	if not _is_safe_identifier(event_name, _event_name_regex):
		return {}
	var raw_details: Variant = raw.get("details", {})
	var safe_details := _sanitize_details(raw_details) if raw_details is Dictionary else {}
	return {
		"at": str(raw.get("at", "")).substr(0, 40),
		"elapsed_seconds": maxf(0.0, float(raw.get("elapsed_seconds", 0.0))),
		"event": event_name,
		"scene": str(raw.get("scene", "")).substr(0, 64),
		"details": safe_details,
	}


func _sanitize_numeric_dictionary(raw: Dictionary) -> Dictionary:
	var safe := {}
	for raw_key in raw:
		var key := str(raw_key)
		if _detail_key_regex.search(key) == null:
			continue
		var value: Variant = raw[raw_key]
		if typeof(value) in [TYPE_BOOL, TYPE_INT]:
			safe[key] = value
		elif typeof(value) == TYPE_FLOAT and is_finite(value):
			safe[key] = value
	return safe


func _sanitize_details(details: Dictionary) -> Dictionary:
	return _sanitize_numeric_dictionary(details)


func _write_checkpoint() -> void:
	if not _enabled:
		return
	var directory_path := ProjectSettings.globalize_path(REPORT_DIRECTORY)
	if not DirAccess.dir_exists_absolute(directory_path):
		if DirAccess.make_dir_recursive_absolute(directory_path) != OK:
			return

	var target_slot := 0 if _active_checkpoint_slot != 0 else 1
	var target_path: String = CHECKPOINT_PATHS[target_slot]
	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(get_report_json())
	var write_error := file.get_error()
	file.close()
	if write_error == OK:
		_active_checkpoint_slot = target_slot


func _current_scene_label() -> String:
	if get_tree() == null or get_tree().current_scene == null:
		return ""
	var scene_path := get_tree().current_scene.scene_file_path
	if scene_path.is_empty():
		return get_tree().current_scene.name.substr(0, 64)
	return scene_path.get_file().get_basename().substr(0, 64)


func _elapsed_seconds() -> float:
	if _session_started_ticks <= 0:
		return 0.0
	return maxf(0.0, float(Time.get_ticks_msec() - _session_started_ticks) / 1000.0)


func _is_safe_identifier(value: String, regex: RegEx) -> bool:
	return not value.is_empty() and regex.search(value) != null


func _contains_session(sessions: Array[Dictionary], session_id: String) -> bool:
	for snapshot in sessions:
		if str(snapshot.get("session_id", "")) == session_id:
			return true
	return false
