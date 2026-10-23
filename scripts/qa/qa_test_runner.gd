extends Node

const QA_FEATURE := "qa_tools"
const REPORT_DIRECTORY := "user://qa_reports"
const STORAGE_PROBE_PATH := "user://qa_reports/qa_storage_probe.tmp"

const HealthScript: Script = preload("res://scripts/components/health.gd")
const DialogueManagerScript: Script = preload("res://scripts/dialogue/dialogue_manager.gd")
const DialogueGraphScript: Script = preload("res://scripts/dialogue/dialogue_graph.gd")
const DialogueNodeScript: Script = preload("res://scripts/dialogue/dialogue_node.gd")
const DialogueChoiceScript: Script = preload("res://scripts/dialogue/dialogue_choice.gd")
const QuestManagerScript: Script = preload("res://scripts/core/quest_manager.gd")
const ProgressionManagerScript: Script = preload("res://scripts/core/progression_manager.gd")


func run_smoke_tests() -> Dictionary:
	if not OS.has_feature(QA_FEATURE):
		return {"enabled": false, "reason": "qa_feature_disabled", "results": []}

	var results: Array[Dictionary] = [
		_check_scene("main_scene_load", "res://scenes/boot/Main.tscn"),
		_check_scene("multiplayer_arena_load", "res://scenes/network/MultiplayerArena.tscn"),
		_check_scene("touch_controls_load", "res://scenes/ui/TouchControls.tscn"),
		_check_scene("network_avatar_load", "res://scenes/network/NetworkAvatar.tscn"),
		_check_scene("network_enemy_load", "res://scenes/network/NetworkEnemy.tscn"),
		_check_scene("npc_scene_load", "res://scenes/npc/NPC.tscn"),
		_check_storage_roundtrip(),
		_test_combat_health_lifecycle(),
		_test_dialogue_choice_branch(),
		_test_quest_reward_once(),
	]
	results.append_array(_manual_acceptance_gates())

	var passed := 0
	var failed := 0
	var skipped := 0
	for result in results:
		match str(result.get("status", "")):
			"pass":
				passed += 1
			"fail":
				failed += 1
			"skip":
				skipped += 1

	var reporter := get_node_or_null("/root/QAReporter")
	if reporter != null:
		reporter.call("set_test_results", results)
		reporter.call("record_event", "qa_smoke_tests_completed", {
			"passed": passed,
			"failed": failed,
			"skipped": skipped,
		})

	return {
		"enabled": true,
		"passed": passed,
		"failed": failed,
		"skipped": skipped,
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


func _test_combat_health_lifecycle() -> Dictionary:
	var started := Time.get_ticks_msec()
	var health := HealthScript.new() as Node
	if health == null:
		return _result("combat_health_lifecycle", "fail", Time.get_ticks_msec() - started, ERR_CANT_CREATE)
	get_tree().root.add_child(health)

	var maximum := float(health.get("max_health"))
	health.call("take_damage", 25.0)
	var after_damage := float(health.get("current"))
	health.call("heal", 10.0)
	var after_heal := float(health.get("current"))
	health.call("set_current_health", 0.0)
	var dead := bool(health.call("is_dead"))
	var valid := (
		is_finite(maximum)
		and is_equal_approx(maximum, 100.0)
		and is_equal_approx(after_damage, 75.0)
		and is_equal_approx(after_heal, 85.0)
		and dead
	)
	health.free()
	return _result("combat_health_lifecycle", "pass" if valid else "fail", Time.get_ticks_msec() - started, OK if valid else ERR_INVALID_DATA)


func _test_dialogue_choice_branch() -> Dictionary:
	var started := Time.get_ticks_msec()
	var manager := DialogueManagerScript.new() as Node
	var graph := DialogueGraphScript.new() as DialogueGraph
	var start_node := DialogueNodeScript.new() as DialogueNode
	var end_node := DialogueNodeScript.new() as DialogueNode
	var choice := DialogueChoiceScript.new() as DialogueChoice

	if manager == null or graph == null or start_node == null or end_node == null or choice == null:
		if is_instance_valid(manager):
			manager.free()
		return _result("dialogue_choice_branch", "fail", Time.get_ticks_msec() - started, ERR_CANT_CREATE)

	start_node.id = &"qa_start"
	start_node.text = "QA test"
	end_node.id = &"qa_end"
	end_node.text = "QA end"
	choice.text = "Continue"
	choice.target_node_id = &"qa_end"
	var flags_to_set: Array[StringName] = [&"qa_dialogue_choice_selected"]
	choice.set_flags = flags_to_set
	var start_choices: Array[DialogueChoice] = [choice]
	start_node.choices = start_choices
	var graph_nodes: Array[DialogueNode] = [start_node, end_node]
	graph.entry_node_id = &"qa_start"
	graph.nodes = graph_nodes

	manager.set_meta("qa_synthetic_test", true)
	get_tree().root.add_child(manager)
	var did_start := bool(manager.call("start", graph))
	manager.call("choose", 99)
	var invalid_choice_safe := bool(manager.call("is_active")) and not bool(manager.call("get_flag", &"qa_dialogue_choice_selected"))
	manager.call("choose", 0)
	var branch_flag_set := bool(manager.call("get_flag", &"qa_dialogue_choice_selected"))
	var remains_active := bool(manager.call("is_active"))
	manager.call("next")
	var ended := not bool(manager.call("is_active"))
	manager.free()

	var valid := did_start and invalid_choice_safe and branch_flag_set and remains_active and ended
	return _result("dialogue_choice_branch", "pass" if valid else "fail", Time.get_ticks_msec() - started, OK if valid else ERR_INVALID_DATA)


func _test_quest_reward_once() -> Dictionary:
	var started := Time.get_ticks_msec()
	var progression := ProgressionManagerScript.new() as Node
	var quests := QuestManagerScript.new() as Node
	if progression == null or quests == null:
		if is_instance_valid(progression):
			progression.free()
		if is_instance_valid(quests):
			quests.free()
		return _result("quest_reward_once", "fail", Time.get_ticks_msec() - started, ERR_CANT_CREATE)

	quests.set("progression", progression)
	quests.set_meta("qa_synthetic_test", true)
	get_tree().root.add_child(progression)
	get_tree().root.add_child(quests)
	var accepted := bool(quests.call("start_quest", &"ash_trail"))
	quests.call("on_enemy_defeated", &"ash_wraith")
	quests.call("on_enemy_defeated", &"ash_wraith")
	var active_before_target := bool(quests.get("active"))
	quests.call("on_enemy_defeated", &"ash_wraith")
	var progress_complete := int(quests.get("progress")) == 3
	var completed := not bool(quests.get("active"))
	var reward := int(progression.get("experience")) == 75
	quests.call("on_enemy_defeated", &"ash_wraith")
	var reward_not_duplicated := int(progression.get("experience")) == 75
	var cannot_restart := not bool(quests.call("start_quest", &"ash_trail"))
	quests.free()
	progression.free()

	var valid := accepted and active_before_target and progress_complete and completed and reward and reward_not_duplicated and cannot_restart
	return _result("quest_reward_once", "pass" if valid else "fail", Time.get_ticks_msec() - started, OK if valid else ERR_INVALID_DATA)


func _manual_acceptance_gates() -> Array[Dictionary]:
	# These gates intentionally remain skipped until a tester performs the
	# interaction on a real device. The report must not overstate coverage.
	return [
		_result("manual_touch_movement_jump_camera", "skip", 0, ERR_UNAVAILABLE),
		_result("manual_player_enemy_combat_3d", "skip", 0, ERR_UNAVAILABLE),
		_result("manual_dialogue_ui_and_quest", "skip", 0, ERR_UNAVAILABLE),
		_result("manual_save_load_after_restart", "skip", 0, ERR_UNAVAILABLE),
		_result("manual_android_background_resume", "skip", 0, ERR_UNAVAILABLE),
		_result("manual_visual_animation_audio", "skip", 0, ERR_UNAVAILABLE),
		_result("manual_performance_soak_10min", "skip", 0, ERR_UNAVAILABLE),
		_result("manual_two_device_network", "skip", 0, ERR_UNAVAILABLE),
	]


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
