extends SceneTree

const ProgressionManagerScript: Script = preload("res://scripts/core/progression_manager.gd")
const QuestManagerScript: Script = preload("res://scripts/core/quest_manager.gd")
const SaveSystemScript: Script = preload("res://scripts/core/save_system.gd")
const SAVE_PATH: String = "user://savegame.json"
const TEMP_SAVE_PATH: String = "user://savegame.json.tmp"
const BACKUP_SAVE_PATH: String = "user://savegame.json.bak"

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var original_files := {}
	for path in [SAVE_PATH, TEMP_SAVE_PATH, BACKUP_SAVE_PATH]:
		original_files[path] = _read_text_if_present(path)

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

	# Simulate an interrupted replacement: the primary is corrupt but the backup is valid.
	var backup_file := FileAccess.open(BACKUP_SAVE_PATH, FileAccess.WRITE)
	if backup_file == null:
		_check(false, "test can create a backup save for recovery")
	else:
		backup_file.store_string(JSON.stringify({"recovered_marker": "backup-save"}))
		backup_file.close()
	var corrupt_file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if corrupt_file == null:
		_check(false, "test can open save file to simulate corruption")
	else:
		corrupt_file.store_string("{invalid json")
		corrupt_file.close()
		var recovered_data = save_system.call("load_game")
		_check(recovered_data is Dictionary and recovered_data.get("recovered_marker", "") == "backup-save", "valid backup is loaded when primary JSON is corrupt")

	# A directory at the temporary-file path forces a write failure; the previous save must survive.
	var previous_file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if previous_file == null:
		_check(false, "test can set up the previous save before failed write")
	else:
		previous_file.store_string(JSON.stringify({"preserve_marker": "previous-save"}))
		previous_file.close()
	var temp_absolute := ProjectSettings.globalize_path(TEMP_SAVE_PATH)
	var temp_directory_created := DirAccess.make_dir_absolute(temp_absolute) == OK
	_check(temp_directory_created, "test can create a temporary-path obstruction")
	if temp_directory_created:
		_check(not bool(save_system.call("save_game", {"replacement": true})), "save reports failure when temporary path cannot be opened")
		var preserved_data = save_system.call("load_game")
		_check(preserved_data is Dictionary and preserved_data.get("preserve_marker", "") == "previous-save", "failed save preserves the previous save data")
		DirAccess.remove_absolute(temp_absolute)

	_restore_original_files(original_files)

	print("[smoke] failures: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _read_text_if_present(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"exists": false, "text": ""}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_check(false, "existing test save can be read before tests")
		return {"exists": false, "text": ""}
	var content := file.get_as_text()
	file.close()
	return {"exists": true, "text": content}


func _restore_original_files(original_files: Dictionary) -> void:
	for path in [SAVE_PATH, TEMP_SAVE_PATH, BACKUP_SAVE_PATH]:
		var original: Dictionary = original_files[path]
		if bool(original.get("exists", false)):
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file == null:
				_check(false, "original save-related file can be restored")
				continue
			file.store_string(str(original.get("text", "")))
			file.close()
		elif FileAccess.file_exists(path):
			_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "temporary test file is removed")


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
