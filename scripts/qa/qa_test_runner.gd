extends Node

const QA_FEATURE := "qa_tools"
const REPORT_DIRECTORY := "user://qa_reports"
const STORAGE_PROBE_PATH := "user://qa_reports/qa_storage_probe.tmp"


func run_smoke_tests() -> Dictionary:
	if not OS.has_feature(QA_FEATURE):
		return {"enabled": false, "reason": "qa_feature_disabled", "results": []}

	var results: Array[Dictionary] = [
		_check_scene("main_scene_load", "res://scenes/boot/Main.tscn"),
		_check_scene("multiplayer_arena_load", "res://scenes/network/MultiplayerArena.tscn"),
		_check_scene("touch_controls_load", "res://scenes/ui/TouchControls.tscn"),
		_check_scene("network_avatar_load", "res://scenes/network/NetworkAvatar.tscn"),
		_check_scene("network_enemy_load", "res://scenes/network/NetworkEnemy.tscn"),
		_check_storage_roundtrip(),
	]

	var passed := 0
	var failed := 0
	for result in results:
		if str(result.get("status", "")) == "pass":
			passed += 1
		elif str(result.get("status", "")) == "fail":
			failed += 1

	var reporter := get_node_or_null("/root/QAReporter")
	if reporter != null:
		reporter.call("set_test_results", results)
		reporter.call("record_event", "qa_smoke_tests_completed", {
			"passed": passed,
			"failed": failed,
		})

	return {
		"enabled": true,
		"passed": passed,
		"failed": failed,
		"results": results,
	}


func _check_scene(test_id: String, resource_path: String) -> Dictionary:
	var started := Time.get_ticks_msec()
	var status := "fail"
	var error_code := ERR_FILE_NOT_FOUND
	if ResourceLoader.exists(resource_path):
		var resource := ResourceLoader.load(resource_path)
		if resource is PackedScene:
			status = "pass"
			error_code = OK
		else:
			error_code = ERR_FILE_UNRECOGNIZED
	return _result(test_id, status, Time.get_ticks_msec() - started, error_code)


func _check_storage_roundtrip() -> Dictionary:
	var started := Time.get_ticks_msec()
	var directory_path := ProjectSettings.globalize_path(REPORT_DIRECTORY)
	if not DirAccess.dir_exists_absolute(directory_path):
		var mkdir_error := DirAccess.make_dir_recursive_absolute(directory_path)
		if mkdir_error != OK:
			return _result("storage_roundtrip", "fail", Time.get_ticks_msec() - started, mkdir_error)

	var file := FileAccess.open(STORAGE_PROBE_PATH, FileAccess.WRITE)
	if file == null:
		return _result("storage_roundtrip", "fail", Time.get_ticks_msec() - started, FileAccess.get_open_error())
	file.store_string("ashen-qa-storage-probe-v1")
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		_remove_probe()
		return _result("storage_roundtrip", "fail", Time.get_ticks_msec() - started, write_error)

	var read_file := FileAccess.open(STORAGE_PROBE_PATH, FileAccess.READ)
	if read_file == null:
		var read_error := FileAccess.get_open_error()
		_remove_probe()
		return _result("storage_roundtrip", "fail", Time.get_ticks_msec() - started, read_error)

	var probe_text := read_file.get_as_text()
	read_file.close()
	var remove_error := _remove_probe()
	if probe_text != "ashen-qa-storage-probe-v1":
		return _result("storage_roundtrip", "fail", Time.get_ticks_msec() - started, ERR_FILE_CORRUPT)
	if remove_error != OK:
		return _result("storage_roundtrip", "fail", Time.get_ticks_msec() - started, remove_error)
	return _result("storage_roundtrip", "pass", Time.get_ticks_msec() - started, OK)


func _remove_probe() -> Error:
	if not FileAccess.file_exists(STORAGE_PROBE_PATH):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(STORAGE_PROBE_PATH))


func _result(test_id: String, status: String, duration_ms: int, error_code: int) -> Dictionary:
	return {
		"id": test_id,
		"status": status,
		"duration_ms": max(0, duration_ms),
		"error_code": error_code,
	}
