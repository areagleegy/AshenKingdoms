extends SceneTree

const ProgressionManagerScript: Script = preload("res://scripts/core/progression_manager.gd")
const QuestManagerScript: Script = preload("res://scripts/core/quest_manager.gd")
const SaveSystemScript: Script = preload("res://scripts/core/save_system.gd")
const SAVE_PATH: String = "user://savegame.json"

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var had_original_save := FileAccess.file_exists(SAVE_PATH)
	var original_save := ""
	if had_original_save:
		var original_file := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if original_file == null:
			push_error("Could not back up existing save before running smoke tests.")
			quit(1)
			return
		original_save = original_file.get_as_text()
		original_file.close()

	_check(NetworkManager.session_mode == "offline", "network manager starts in offline mode")
	_check(int(NetworkManager.call("start_host", 0)) == ERR_INVALID_PARAMETER, "network manager rejects an invalid host port")
	_check(int(NetworkManager.call("start_client", "", 7777)) == ERR_INVALID_PARAMETER, "network manager rejects an empty server address")
	_check(NetworkManager.session_mode == "offline", "invalid network settings do not start a session")

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

	_restore_original_save(had_original_save, original_save, save_system)

	print("[smoke] failures: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _restore_original_save(had_original_save: bool, original_save: String, save_system: Node) -> void:
	if had_original_save:
		var restore_file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if restore_file == null:
			_check(false, "existing save file can be restored after the test")
			return
		restore_file.store_string(original_save)
		restore_file.close()
	else:
		_check(bool(save_system.call("delete_save")), "temporary smoke-test save is removed")


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
