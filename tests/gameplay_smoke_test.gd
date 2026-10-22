extends SceneTree

const ProgressionManagerScript: Script = preload("res://scripts/core/progression_manager.gd")
const QuestManagerScript: Script = preload("res://scripts/core/quest_manager.gd")
const SaveSystemScript: Script = preload("res://scripts/core/save_system.gd")
const SAVE_RELATED_FILES: Array[String] = [
	"user://savegame.json",
	"user://savegame.bak.json",
	"user://savegame.tmp",
	"user://savegame.bak.tmp",
	"user://savegame.json.old",
]

var _failures: int = 0
var _save_snapshots: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_save_snapshots = _isolate_save_files()
	if _save_snapshots.has("__snapshot_error"):
		quit(1)
		return

	var network_manager: Node = root.get_node_or_null("NetworkManager")
	_check(network_manager != null, "network manager autoload is present for smoke tests")
	if network_manager != null:
		_check(str(network_manager.get("session_mode")) == "offline", "network manager starts in offline mode")
		_check(int(network_manager.call("start_host", 0)) == ERR_INVALID_PARAMETER, "network manager rejects an invalid host port")
		_check(int(network_manager.call("start_client", "", 7777)) == ERR_INVALID_PARAMETER, "network manager rejects an empty server address")
		_check(str(network_manager.get("session_mode")) == "offline", "invalid network settings do not start a session")

	var progression: Node = ProgressionManagerScript.new()
	root.add_child(progression)
	_check(int(progression.get("level")) == 1, "progression starts at level 1")

	progression.call("add_experience", 100)
	_check(int(progression.get("level")) == 2, "100 XP advances the player to level 2")
	_check(int(progression.get("experience")) == 0, "level-up carries no unused XP for an exact threshold")

	var quests: Node = QuestManagerScript.new()
	quests.set("progression", progression)
	root.add_child(quests)
	_check(bool(quests.call("start_quest", &"ash_trail")), "known quest can start")
	_check(not bool(quests.call("start_quest", &"missing_quest")), "unknown quest is rejected")

	quests.call("on_enemy_defeated", &"ash_wraith")
	quests.call("on_enemy_defeated", &"ash_wraith")
	_check(int(quests.get("progress")) == 2, "quest tracks its first two enemy defeats")
	_check(bool(quests.get("active")), "quest remains active before its target")

	quests.call("on_enemy_defeated", &"ash_wraith")
	_check(int(quests.get("progress")) == 3, "third enemy completes the quest")
	_check(not bool(quests.get("active")), "completed quest is no longer active")
	_check(int(progression.get("experience")) == 75, "quest reward grants 75 XP")

	quests.call("on_enemy_defeated", &"ash_wraith")
	_check(int(progression.get("experience")) == 75, "later defeats do not grant the quest reward again")
	_check(not bool(quests.call("start_quest", &"ash_trail")), "completed quest cannot be accepted again")

	var restored_quest: Node = QuestManagerScript.new()
	restored_quest.set("progression", progression)
	root.add_child(restored_quest)
	restored_quest.call("load_state", quests.call("to_save_data"))
	_check(int(restored_quest.get("progress")) == 3, "quest progress survives save-data round-trip")
	_check(not bool(restored_quest.get("active")), "completed state survives save-data round-trip")

	var save_system: Node = SaveSystemScript.new()
	root.add_child(save_system)
	var sample_data: Dictionary = {
		"version": 1,
		"smoke_test_marker": "ashen-kingdoms",
		"nested": {"value": 7}
	}
	_check(bool(save_system.call("save_game", sample_data)), "save system writes JSON data")
	var loaded_data = save_system.call("load_game")
	_check(loaded_data is Dictionary, "save system loads a JSON object")
	if loaded_data is Dictionary:
		_check(loaded_data.get("smoke_test_marker", "") == "ashen-kingdoms", "loaded save retains its marker")
		var loaded_nested = loaded_data.get("nested", {})
		_check(loaded_nested is Dictionary and int(loaded_nested.get("value", 0)) == 7, "loaded save retains nested values")

	var corrupt_file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if corrupt_file == null:
		_check(false, "test can open save file to simulate corruption")
	else:
		corrupt_file.store_string("{invalid json")
		corrupt_file.close()
		var corrupt_data = save_system.call("load_game")
		_check(corrupt_data is Dictionary and corrupt_data.is_empty(), "malformed JSON is rejected safely")

	_restore_save_files(_save_snapshots)

	print("[smoke] failures: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _isolate_save_files() -> Dictionary:
	var snapshots: Dictionary = {}
	for path in SAVE_RELATED_FILES:
		if not FileAccess.file_exists(path):
			snapshots[path] = null
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			push_error("Could not snapshot save-related file: %s" % path)
			snapshots["__snapshot_error"] = true
			return snapshots
		snapshots[path] = file.get_buffer(file.get_length())
		file.close()
	return snapshots


func _restore_save_files(snapshots: Dictionary) -> void:
	for path in SAVE_RELATED_FILES:
		var absolute_path := ProjectSettings.globalize_path(path)
		var original: Variant = snapshots.get(path, null)
		if original == null:
			if FileAccess.file_exists(path):
				var remove_error := DirAccess.remove_absolute(absolute_path)
				_check(remove_error == OK, "new save-related file is removed: %s" % path)
			continue
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			_check(false, "original save-related file can be restored: %s" % path)
			continue
		file.store_buffer(original as PackedByteArray)
		file.flush()
		var write_error: Error = file.get_error()
		file.close()
		_check(write_error == OK, "original save-related file is restored: %s" % path)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
