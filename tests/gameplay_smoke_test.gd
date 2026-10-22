extends SceneTree

const ProgressionManagerScript: Script = preload("res://scripts/core/progression_manager.gd")
const QuestManagerScript: Script = preload("res://scripts/core/quest_manager.gd")
const SaveSystemScript: Script = preload("res://scripts/core/save_system.gd")
var _failures: int = 0
var _test_save_path: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_save_path = "user://ashen_smoke_save_%d.json" % OS.get_process_id()
	_cleanup_test_save_files(_test_save_path)

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
	save_system.set("save_path", _test_save_path)
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

	# Inject a short write after the temporary file has opened. The original save must survive.
	save_system.set("write_hook_for_testing", Callable(self, "_simulate_partial_write_failure"))
	_check(not bool(save_system.call("save_game", {"smoke_test_marker": "partial-write-must-fail"})), "partial write failure is not reported as a successful save")
	save_system.set("write_hook_for_testing", Callable())
	var after_failed_write = save_system.call("load_game")
	_check(after_failed_write is Dictionary and after_failed_write.get("smoke_test_marker", "") == "ashen-kingdoms", "failed temporary write preserves the previous primary save")

	var corrupt_file := FileAccess.open(_test_save_path, FileAccess.WRITE)
	if corrupt_file == null:
		_check(false, "test can open save file to simulate corruption")
	else:
		corrupt_file.store_string("{invalid json")
		corrupt_file.close()
		var corrupt_data = save_system.call("load_game")
		_check(corrupt_data is Dictionary and corrupt_data.is_empty(), "malformed JSON is rejected safely")
		_check(str(save_system.get("last_load_status")) == "invalid_json", "load status distinguishes malformed JSON")

	_check(bool(save_system.call("save_game", {"version": 1, "smoke_test_marker": "backup-state"})), "valid recovery baseline is saved")
	_check(bool(save_system.call("save_game", {"version": 2, "smoke_test_marker": "latest-state"})), "new save rotates the previous valid save into backup")
	var latest_file := FileAccess.open(_test_save_path, FileAccess.WRITE)
	if latest_file == null:
		_check(false, "test can corrupt the latest primary save")
	else:
		latest_file.store_string("{corrupt latest save")
		latest_file.close()
	var recovered_data = save_system.call("load_game")
	_check(recovered_data is Dictionary and recovered_data.get("smoke_test_marker", "") == "backup-state", "load recovers the previous valid backup")
	_check(str(save_system.get("last_load_status")) == "recovered_backup", "load status reports backup recovery")

	save_system.set("rename_hook_for_testing", Callable(self, "_fail_primary_rename_for_test"))
	_check(not bool(save_system.call("save_game", {"smoke_test_marker": "must-not-replace"})), "replacement failure is not reported as a successful save")
	save_system.set("rename_hook_for_testing", Callable())
	var preserved_data = save_system.call("load_game")
	_check(preserved_data is Dictionary and preserved_data.get("smoke_test_marker", "") == "backup-state", "replacement failure leaves the prior valid save intact")

	_cleanup_test_save_files(_test_save_path)

	_cleanup_test_save_files(_test_save_path)
	print("[smoke] failures: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _simulate_partial_write_failure(file: FileAccess, serialized: String) -> bool:
	var partial_length := maxi(1, serialized.length() / 2)
	file.store_string(serialized.substr(0, partial_length))
	return false


func _fail_primary_rename_for_test(from_path: String, to_path: String) -> Error:
	if to_path == ProjectSettings.globalize_path(_test_save_path):
		return ERR_CANT_CREATE
	return DirAccess.rename_absolute(from_path, to_path)


func _cleanup_test_save_files(base_path: String) -> void:
	for suffix in ["", ".tmp", ".bak", ".bak.tmp", ".restore.tmp"]:
		var test_path := base_path + suffix
		if FileAccess.file_exists(test_path):
			var remove_error: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
			if remove_error != OK:
				push_error("Could not clean isolated test save file: %s" % test_path)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
