extends SceneTree

const SaveSystemScript: Script = preload("res://scripts/core/save_system.gd")
const SAVE_PATH := "user://savegame.json"
const TEMP_PATH := "user://savegame.json.tmp"
const BACKUP_PATH := "user://savegame.json.bak"

var _failures := 0
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var had_original := FileAccess.file_exists(SAVE_PATH)
	var original_text := ""
	if had_original:
		var original_file := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if original_file == null:
			_check(false, "existing save can be backed up before test")
			quit(1)
			return
		original_text = original_file.get_as_text()
		original_file.close()

	var save_system: Node = SaveSystemScript.new()
	root.add_child(save_system)

	_check(bool(save_system.call("save_game", {"version": 1, "value": "first"})), "first save is written")
	var first: Variant = save_system.call("load_game")
	_check(first is Dictionary and first.get("value", "") == "first", "first save can be loaded")

	_check(bool(save_system.call("save_game", {"version": 1, "value": "second"})), "replacement save is written")
	var second: Variant = save_system.call("load_game")
	_check(second is Dictionary and second.get("value", "") == "second", "replacement save is the active save")
	_check(not FileAccess.file_exists(TEMP_PATH), "temporary file is cleaned after a successful replacement")
	_check(not FileAccess.file_exists(BACKUP_PATH), "backup is cleaned after a successful replacement")

	var array_file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if array_file == null:
		_check(false, "test can create a non-object JSON fixture")
	else:
		array_file.store_string("[1, 2, 3]")
		array_file.close()
		var array_data: Variant = save_system.call("load_game")
		_check(array_data is Dictionary and array_data.is_empty(), "JSON arrays are rejected as save roots")

	var malformed_file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if malformed_file == null:
		_check(false, "test can create malformed JSON fixture")
	else:
		malformed_file.store_string("{broken")
		malformed_file.close()
		var malformed_data: Variant = save_system.call("load_game")
		_check(malformed_data is Dictionary and malformed_data.is_empty(), "malformed JSON is rejected safely")

	if had_original:
		var restore_file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if restore_file == null:
			_check(false, "original save can be restored after test")
		else:
			restore_file.store_string(original_text)
			restore_file.close()
		_check(FileAccess.file_exists(SAVE_PATH), "original save fixture is retained")
	else:
		_check(bool(save_system.call("delete_save")), "test save and recovery files are removed")

	_check(not FileAccess.file_exists(TEMP_PATH), "no temporary save remains after cleanup")
	if not had_original:
		_check(not FileAccess.file_exists(BACKUP_PATH), "no backup remains after cleanup")

	print("[save-system] checks: %d, failures: %d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
