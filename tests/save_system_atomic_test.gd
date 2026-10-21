extends SceneTree

const SaveSystemScript: Script = preload("res://scripts/core/save_system.gd")
const SAVE_PATH := "user://savegame.json"
const TEMP_PATH := "user://savegame.json.tmp"
const BACKUP_PATH := "user://savegame.json.bak"

var _failures := 0
var _checks := 0
var _original_files: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for path in [SAVE_PATH, TEMP_PATH, BACKUP_PATH]:
		var exists := FileAccess.file_exists(path)
		_original_files[path] = {
			"exists": exists,
			"text": FileAccess.get_file_as_string(path) if exists else "",
		}

	var save_system: Node = SaveSystemScript.new()
	root.add_child(save_system)
	save_system.call("delete_save")

	_test_round_trip(save_system)
	_test_backup_recovery(save_system)
	_test_v1_migration(save_system)
	_test_corrupt_json(save_system)
	_test_wrong_root(save_system)
	_test_invalid_schema_rejected(save_system)
	_test_future_version_rejected(save_system)
	_test_oversized_payload_rejected(save_system)
	_test_delete_cleans_recovery_files(save_system)

	_restore_original_files()
	print("[save-system] checks: %d, failures: %d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _valid_payload(version: int = 2, level_value: int = 1) -> Dictionary:
	return {
		"version": version,
		"player_position": {"x": 0.0, "y": 0.92, "z": 0.0},
		"player_health": 100.0,
		"level": level_value,
		"experience": 42,
		"inventory": [],
		"quest": {"active": false, "progress": 0},
		"dialogue": {},
	}


func _test_round_trip(save_system: Node) -> void:
	var first := _valid_payload(2, 2)
	_check(bool(save_system.call("save_game", first)), "valid save is written")
	_check(int(first["version"]) == 2, "save operation does not mutate caller data")
	_check(FileAccess.file_exists(SAVE_PATH), "primary save exists after write")

	var loaded: Dictionary = save_system.call("load_game")
	_check(int(loaded.get("level", -1)) == 2, "saved level round-trips")
	_check(int(loaded.get("experience", -1)) == 42, "saved experience round-trips")

	var second := _valid_payload(2, 3)
	_check(bool(save_system.call("save_game", second)), "replacement save is written")
	loaded = save_system.call("load_game")
	_check(int(loaded.get("level", -1)) == 3, "replacement becomes active save")
	_check(FileAccess.file_exists(BACKUP_PATH), "previous valid save is retained as recovery backup")
	_check(not FileAccess.file_exists(TEMP_PATH), "temporary file is removed after successful replacement")


func _test_backup_recovery(save_system: Node) -> void:
	_write_text(SAVE_PATH, "{broken json")
	var loaded: Dictionary = save_system.call("load_game")
	_check(int(loaded.get("level", -1)) == 2, "corrupt primary save recovers previous valid backup")

	# A missing primary file should also recover the backup.
	_remove_if_exists(SAVE_PATH)
	loaded = save_system.call("load_game")
	_check(int(loaded.get("level", -1)) == 2, "missing primary save recovers backup")


func _test_v1_migration(save_system: Node) -> void:
	_write_text(SAVE_PATH, JSON.stringify(_valid_payload(1, 4)))
	var loaded: Dictionary = save_system.call("load_game")
	_check(int(loaded.get("version", -1)) == 2, "version 1 save migrates to current schema")
	_check(int(loaded.get("level", -1)) == 4, "migration preserves player progression")


func _test_corrupt_json(save_system: Node) -> void:
	_remove_if_exists(BACKUP_PATH)
	_write_text(SAVE_PATH, "{not-json")
	var loaded: Dictionary = save_system.call("load_game")
	_check(loaded.is_empty(), "malformed JSON is rejected when no backup exists")


func _test_wrong_root(save_system: Node) -> void:
	_write_text(SAVE_PATH, "[1, 2, 3]")
	var loaded: Dictionary = save_system.call("load_game")
	_check(loaded.is_empty(), "JSON array root is rejected")


func _test_invalid_schema_rejected(save_system: Node) -> void:
	var invalid := _valid_payload()
	invalid.erase("level")
	_check(not bool(save_system.call("save_game", invalid)), "saving a payload with a required field missing is rejected")

	invalid = _valid_payload()
	invalid["player_health"] = INF
	_check(not bool(save_system.call("save_game", invalid)), "non-finite player health is rejected")

	invalid = _valid_payload()
	invalid["inventory"] = [{"id": "health_potion", "amount": "many"}]
	_check(not bool(save_system.call("save_game", invalid)), "inventory item with a non-numeric amount is rejected")

	invalid = _valid_payload()
	invalid["inventory"] = [{"id": "", "amount": 1}]
	_check(not bool(save_system.call("save_game", invalid)), "inventory item with an empty id is rejected")

	invalid = _valid_payload()
	invalid["inventory"] = []
	for _i in range(81):
		invalid["inventory"].append(null)
	_check(not bool(save_system.call("save_game", invalid)), "inventory exceeding the supported 80 slots is rejected")

	invalid = _valid_payload()
	invalid["quest"] = {"active": "yes", "progress": 0}
	_check(not bool(save_system.call("save_game", invalid)), "quest with a non-boolean active field is rejected")

	invalid = _valid_payload()
	invalid["quest"] = {"active": false, "progress": 0}
	_check(bool(save_system.call("save_game", invalid)), "legacy quest payload with active/progress remains valid")


func _test_future_version_rejected(save_system: Node) -> void:
	_write_text(SAVE_PATH, JSON.stringify(_valid_payload(3, 9)))
	# A stale backup must not cause an older game to silently roll back a newer save.
	_write_text(BACKUP_PATH, JSON.stringify(_valid_payload(2, 2)))
	var loaded: Dictionary = save_system.call("load_game")
	_check(loaded.is_empty(), "future-version save is rejected without silent backup rollback")


func _test_oversized_payload_rejected(save_system: Node) -> void:
	var oversized := _valid_payload()
	var large_inventory: Array = []
	for _i in range(180000):
		large_inventory.append("xxxxxxxx")
	oversized["inventory"] = large_inventory
	_check(not bool(save_system.call("save_game", oversized)), "payload larger than 1 MiB is rejected")


func _test_delete_cleans_recovery_files(save_system: Node) -> void:
	_write_text(SAVE_PATH, JSON.stringify(_valid_payload()))
	_write_text(TEMP_PATH, "temporary")
	_write_text(BACKUP_PATH, JSON.stringify(_valid_payload()))
	_check(bool(save_system.call("delete_save")), "delete_save reports successful cleanup")
	_check(not FileAccess.file_exists(SAVE_PATH), "delete_save removes primary save")
	_check(not FileAccess.file_exists(TEMP_PATH), "delete_save removes temporary file")
	_check(not FileAccess.file_exists(BACKUP_PATH), "delete_save removes backup")


func _write_text(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "test fixture can be written: %s" % path)
		return
	file.store_string(value)
	file.close()


func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _restore_original_files() -> void:
	for path in _original_files.keys():
		_remove_if_exists(path)
		var saved: Dictionary = _original_files[path]
		if bool(saved["exists"]):
			_write_text(path, str(saved["text"]))


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
