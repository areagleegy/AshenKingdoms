extends SceneTree

const SAVE_SCRIPT_PATH := "res://scripts/core/save_system.gd"
const TEST_PATHS := [
	"user://savegame.json",
	"user://savegame.bak.json",
	"user://savegame.tmp",
	"user://savegame.json.old",
]
const MAX_SAVE_SIZE := 1_048_576

var _snapshot: Dictionary = {}
var _failures := 0
var _checks := 0
var _save_system: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_snapshot_original_files()
	var script := load(SAVE_SCRIPT_PATH) as Script
	_check(script != null, "SaveSystem script loads")
	if script == null:
		_restore_original_files()
		quit(1)
		return

	_save_system = script.new() as Node
	root.add_child(_save_system)
	_test_round_trip()
	_test_backup_recovery()
	_test_rejects_oversized_data()
	_test_delete()
	_save_system.free()
	_restore_original_files()

	print("[save-security] checks: %d, failures: %d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_round_trip() -> void:
	var data := {
		"level": 7,
		"health": 82.5,
		"flags": {"intro_seen": true},
		"inventory": [{"id": "iron_ore", "quantity": 12}],
	}
	_check(bool(_save_system.call("save_game", data)), "valid data saves successfully")
	var loaded: Dictionary = _save_system.call("load_game")
	_check(int(loaded.get("level", 0)) == 7, "integer values survive save/load")
	_check(is_equal_approx(float(loaded.get("health", 0.0)), 82.5), "float values survive save/load")
	_check(bool((loaded.get("flags", {}) as Dictionary).get("intro_seen", false)), "nested dictionaries survive save/load")


func _test_backup_recovery() -> void:
	_check(bool(_save_system.call("save_game", {"revision": 1})), "first revision saves")
	_check(bool(_save_system.call("save_game", {"revision": 2})), "second revision saves and backs up the previous revision")
	var file := FileAccess.open("user://savegame.json", FileAccess.WRITE)
	_check(file != null, "test can open primary save for corruption fixture")
	if file == null:
		return
	file.store_string("{broken JSON")
	file.close()

	var recovered: Dictionary = _save_system.call("load_game")
	_check(int(recovered.get("revision", 0)) == 1, "corrupt primary save recovers the previous revision from backup")


func _test_rejects_oversized_data() -> void:
	var oversized := {"payload": "x".repeat(MAX_SAVE_SIZE + 10)}
	_check(not bool(_save_system.call("save_game", oversized)), "oversized save data is rejected")


func _test_delete() -> void:
	_check(bool(_save_system.call("delete_save")), "delete_save succeeds")
	_check(not FileAccess.file_exists("user://savegame.json"), "primary save is deleted")
	_check(not FileAccess.file_exists("user://savegame.bak.json"), "backup save is deleted")
	_check(not FileAccess.file_exists("user://savegame.tmp"), "temporary save is deleted")


func _snapshot_original_files() -> void:
	for path in TEST_PATHS:
		var existed := FileAccess.file_exists(path)
		var contents := ""
		if existed:
			var file := FileAccess.open(path, FileAccess.READ)
			if file != null:
				contents = file.get_as_text()
				file.close()
		_snapshot[path] = {"existed": existed, "contents": contents}


func _restore_original_files() -> void:
	for path in TEST_PATHS:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		var saved: Dictionary = _snapshot.get(path, {})
		if not bool(saved.get("existed", false)):
			continue
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			_fail("original test fixture can be restored: %s" % path)
			continue
		file.store_string(String(saved.get("contents", "")))
		file.close()


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % description)
	else:
		_fail(description)


func _fail(description: String) -> void:
	_failures += 1
	push_error("[FAIL] %s" % description)
