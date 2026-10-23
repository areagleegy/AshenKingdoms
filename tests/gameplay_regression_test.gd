extends SceneTree

const PlayerScript: Script = preload("res://scripts/player/player.gd")
const HealthScript: Script = preload("res://scripts/components/health.gd")
const InventoryScript: Script = preload("res://scripts/components/inventory.gd")
const ItemResourceScript: Script = preload("res://scripts/items/item_resource.gd")
const ProgressionScript: Script = preload("res://scripts/core/progression_manager.gd")
const QuestManagerScript: Script = preload("res://scripts/core/quest_manager.gd")
const SaveSystemScript: Script = preload("res://scripts/core/save_system.gd")
const DialogueManagerScript: Script = preload("res://scripts/dialogue/dialogue_manager.gd")
const DialogueGraphScript: Script = preload("res://scripts/dialogue/dialogue_graph.gd")
const DialogueNodeScript: Script = preload("res://scripts/dialogue/dialogue_node.gd")
const DialogueChoiceScript: Script = preload("res://scripts/dialogue/dialogue_choice.gd")
const MainScript: Script = preload("res://scripts/core/main.gd")

const POTION_PATH := "res://resources/items/health_potion.tres"

var _failures := 0
var _checks := 0
var _test_save_path: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_save_path = "user://ashen_regression_save_%d.json" % OS.get_process_id()
	_cleanup_test_save_files(_test_save_path)

	_test_player_and_health()
	_test_inventory_and_potions()
	_test_save_and_load()
	_test_player_position_finite_guard()
	_test_autosave_notifications()
	_test_main_close_notification_wiring()
	_test_dialogue_and_quests()
	_test_android_configuration()
	_test_runtime_input_registration()

	_cleanup_test_save_files(_test_save_path)
	print("[regression] checks: %d, failures: %d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _make_player() -> CharacterBody3D:
	var player := CharacterBody3D.new()
	player.name = "TestPlayer"
	player.set_script(PlayerScript)

	var health: Node = HealthScript.new()
	health.name = "Health"
	player.add_child(health)

	var inventory: Node = InventoryScript.new()
	inventory.name = "Inventory"
	player.add_child(inventory)

	root.add_child(player)
	return player


func _test_player_and_health() -> void:
	var player := _make_player()
	var health: Health = player.get_node("Health") as Health
	_check(health != null, "player owns a Health component")
	_check(is_equal_approx(health.current, 100.0), "player health initializes to the configured maximum")

	var death_events: Array = []
	player.died.connect(func(_dead_player: Node) -> void: death_events.append(true))
	player.call("take_damage", 35.0)
	_check(is_equal_approx(health.current, 65.0), "player damage reduces health")
	player.call("take_damage", -10.0)
	_check(is_equal_approx(health.current, 65.0), "negative damage is ignored")

	player.call("take_damage", 1000.0)
	_check(health.is_dead(), "lethal damage clamps health to zero")
	_check(bool(player.get("is_dead")), "player enters its dead state after Health.died")
	_check(death_events.size() == 1, "player death signal fires once for lethal damage")

	player.call("reset_after_death", Vector3(2.0, 1.0, -3.0))
	_check(not bool(player.get("is_dead")), "reset after death restores the living state")
	_check(is_equal_approx(health.current, health.max_health), "reset after death restores full health")
	_check((player as Node3D).position.is_equal_approx(Vector3(2.0, 1.0, -3.0)), "reset after death restores the spawn position")
	player.queue_free()


func _test_inventory_and_potions() -> void:
	var player := _make_player()
	var inventory: Inventory = player.get_node("Inventory") as Inventory
	var health: Health = player.get_node("Health") as Health
	var potion := load(POTION_PATH) as ItemResource
	_check(potion != null, "health potion resource loads")
	if potion == null:
		player.queue_free()
		return

	_check(String(potion.id) == "health_potion", "health potion has the inventory's registered item ID")
	_check(int(inventory.call("add_item", potion, 2)) == 0, "inventory accepts a valid potion stack")
	_check(int(inventory.call("count_item", &"health_potion")) == 2, "inventory counts stacked potions")

	health.take_damage(50.0)
	_check(bool(inventory.call("use_item", 0, player)), "a potion can be used when health is missing")
	_check(is_equal_approx(health.current, 85.0), "potion restores its configured healing amount")
	_check(int(inventory.call("count_item", &"health_potion")) == 1, "using a potion decrements the stack")

	_check(bool(inventory.call("use_item", 0, player)), "remaining potion can be used")
	_check(is_equal_approx(health.current, health.max_health), "healing clamps to maximum health")
	_check(not bool(inventory.call("use_item", 0, player)), "empty inventory slot cannot be used")
	_check(not bool(inventory.call("use_item", -1, player)), "negative inventory index is rejected")
	_check(not bool(inventory.call("use_item", 0, null)), "null user is rejected")

	inventory.call("add_item", potion, 1)
	_check(not bool(inventory.call("use_item", 0, player)), "potion is not consumed when health is already full")
	_check(int(inventory.call("count_item", &"health_potion")) == 1, "rejected potion use preserves the item")

	var saved_inventory: Array = inventory.call("to_save_data")
	var restored: Node = InventoryScript.new()
	restored.name = "RestoredInventory"
	root.add_child(restored)
	restored.call("restore_save_data", saved_inventory)
	_check(int(restored.call("count_item", &"health_potion")) == 1, "inventory item ID and count survive serialization round-trip")
	restored.queue_free()
	player.queue_free()


func _test_save_and_load() -> void:
	var save_system: Node = SaveSystemScript.new()
	save_system.set("save_path", _test_save_path)
	root.add_child(save_system)

	_check(bool(save_system.call("save_game", {"level": 4, "health": 61.5, "flags": {"intro_seen": true}})), "save system writes structured data to an isolated path")
	var loaded = save_system.call("load_game")
	_check(loaded is Dictionary, "save system returns a dictionary for valid JSON")
	if loaded is Dictionary:
		_check(int(loaded.get("level", 0)) == 4, "saved progression values load correctly")
		_check(is_equal_approx(float(loaded.get("health", 0.0)), 61.5), "saved floating-point health loads correctly")
		var flags = loaded.get("flags", {})
		_check(flags is Dictionary and bool(flags.get("intro_seen", false)), "nested dialogue flags survive save/load")

	var malformed := FileAccess.open(_test_save_path, FileAccess.WRITE)
	if malformed == null:
		_check(false, "test can create malformed JSON fixture")
	else:
		malformed.store_string("{not valid JSON")
		malformed.close()
		var corrupt = save_system.call("load_game")
		_check(corrupt is Dictionary and corrupt.is_empty(), "malformed JSON without backup safely returns an empty dictionary")
		_check(str(save_system.get("last_load_status")) == "invalid_json", "load status distinguishes invalid JSON")

	_check(bool(save_system.call("save_game", {"marker": "backup-state", "level": 5})), "save system writes a valid recovery baseline")
	_check(bool(save_system.call("save_game", {"marker": "latest-state", "level": 6})), "save system preserves the previous valid state as backup")
	var latest := FileAccess.open(_test_save_path, FileAccess.WRITE)
	if latest == null:
		_check(false, "test can corrupt the latest primary save")
	else:
		latest.store_string("{latest save is corrupt")
		latest.close()
	var recovered = save_system.call("load_game")
	_check(recovered is Dictionary and recovered.get("marker", "") == "backup-state", "load recovers data from a valid backup")
	_check(str(save_system.get("last_load_status")) == "recovered_backup", "load status identifies backup recovery")
	_check(FileAccess.get_file_as_string(_test_save_path) == FileAccess.get_file_as_string(_test_save_path + ".bak"), "recovered primary matches the verified backup bytes")

	save_system.queue_free()


func _test_player_position_finite_guard() -> void:
	var main_for_test := MainScript.new() as Node3D
	var test_player := CharacterBody3D.new()
	root.add_child(test_player)
	main_for_test.set("player", test_player)

	test_player.global_position = Vector3(4.0, 5.0, 6.0)
	var original_position := test_player.global_position
	_check(not bool(main_for_test.call("_restore_player_position", {"x": NAN, "y": 0.92, "z": 0.0})), "non-finite X coordinate is rejected")
	_check(not bool(main_for_test.call("_restore_player_position", {"x": 0.0, "y": INF, "z": 0.0})), "infinite Y coordinate is rejected")
	_check(not bool(main_for_test.call("_restore_player_position", {"x": 0.0, "y": 0.92, "z": -INF})), "negative infinite Z coordinate is rejected")
	_check(not bool(main_for_test.call("_restore_player_position", {"x": "NaN", "y": 0.92, "z": 0.0})), "string coordinate is rejected")
	_check(test_player.global_position.is_equal_approx(original_position), "rejected coordinates do not change the player's position")

	_check(bool(main_for_test.call("_restore_player_position", {"x": 1.0, "y": 2.0, "z": 3.0})), "finite numeric coordinates are accepted")
	_check(test_player.global_position.is_equal_approx(Vector3(1.0, 2.0, 3.0)), "valid saved position is restored")
	test_player.queue_free()
	main_for_test.free()


func _test_main_close_notification_wiring() -> void:
	var source_file := FileAccess.open("res://scripts/core/main.gd", FileAccess.READ)
	_check(source_file != null, "main script is readable for close notification regression checks")
	if source_file == null:
		return
	var source := source_file.get_as_text()
	source_file.close()

	var notification_start := source.find("func _notification(what: int) -> void:")
	var next_function := source.find("\n\nfunc ", notification_start + 1)
	_check(
		notification_start >= 0 and next_function > notification_start,
		"main notification handler can be located for regression checks"
	)
	if notification_start < 0 or next_function <= notification_start:
		return

	var notification_block := source.substr(notification_start, next_function - notification_start)
	var close_branch := notification_block.find("if what == NOTIFICATION_WM_CLOSE_REQUEST:")
	var save_call := notification_block.find("_handle_window_close_request()")
	var quit_call := notification_block.find("get_tree().quit()")
	_check(
		close_branch >= 0 and save_call > close_branch and quit_call > save_call,
		"window close notification autosaves before quitting the scene tree"
	)


func _test_autosave_notifications() -> void:
	var autosave_path := "user://ashen_autosave_regression_%d.json" % OS.get_process_id()
	_cleanup_test_save_files(autosave_path)
	var main_for_test := MainScript.new() as Node3D
	var test_player := _make_player()
	var progression: Node = ProgressionScript.new()
	root.add_child(progression)
	var quests: Node = QuestManagerScript.new()
	quests.set("progression", progression)
	root.add_child(quests)
	var save_system: Node = SaveSystemScript.new()
	save_system.set("save_path", autosave_path)
	root.add_child(save_system)
	main_for_test.set("player", test_player)
	main_for_test.set("progression", progression)
	main_for_test.set("quests", quests)
	main_for_test.set("save_system", save_system)

	main_for_test.call("_notification", MainLoop.NOTIFICATION_APPLICATION_PAUSED)
	_check(FileAccess.file_exists(autosave_path), "application pause autosaves a valid live session")

	test_player.global_position = Vector3(6.0, 1.5, -4.0)
	main_for_test.call("_notification", Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	var loaded_after_back: Dictionary = save_system.call("load_game")
	var position_after_back: Dictionary = loaded_after_back.get("player_position", {})
	_check(
		is_equal_approx(float(position_after_back.get("x", 0.0)), 6.0)
		and is_equal_approx(float(position_after_back.get("y", 0.0)), 1.5)
		and is_equal_approx(float(position_after_back.get("z", 0.0)), -4.0),
		"Android back-button request autosaves the current player position"
	)

	test_player.global_position = Vector3(2.0, 3.0, 4.0)
	main_for_test.call("_handle_window_close_request")
	var loaded_after_close: Dictionary = save_system.call("load_game")
	var position_after_close: Dictionary = loaded_after_close.get("player_position", {})
	_check(
		is_equal_approx(float(position_after_close.get("x", 0.0)), 2.0)
		and is_equal_approx(float(position_after_close.get("y", 0.0)), 3.0)
		and is_equal_approx(float(position_after_close.get("z", 0.0)), 4.0),
		"window close request autosaves the current player position"
	)

	var bytes_before_death := FileAccess.get_file_as_string(autosave_path)
	test_player.call("take_damage", 100000.0)
	main_for_test.call("_notification", MainLoop.NOTIFICATION_APPLICATION_PAUSED)
	_check(
		FileAccess.get_file_as_string(autosave_path) == bytes_before_death,
		"application pause does not overwrite the save after player death"
	)

	_cleanup_test_save_files(autosave_path)
	save_system.free()
	quests.free()
	progression.free()
	test_player.free()
	main_for_test.free()


func _cleanup_test_save_files(base_path: String) -> void:
	for suffix in ["", ".tmp", ".bak", ".bak.tmp", ".restore.tmp"]:
		var test_path: String = base_path + str(suffix)
		if FileAccess.file_exists(test_path):
			var remove_error: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
			if remove_error != OK:
				push_error("Could not clean isolated regression save file: %s" % test_path)


func _test_dialogue_and_quests() -> void:
	var player := _make_player()
	var progression: Node = ProgressionScript.new()
	progression.name = "TestProgression"
	root.add_child(progression)
	var quests: Node = QuestManagerScript.new()
	quests.name = "TestQuests"
	quests.set("progression", progression)
	root.add_child(quests)

	var dialogue: Node = DialogueManagerScript.new()
	dialogue.name = "IsolatedDialogueManager"
	root.add_child(dialogue)
	dialogue.call("configure_context", player, progression, quests)

	var graph: DialogueGraph = DialogueGraphScript.new()
	var entry: DialogueNode = DialogueNodeScript.new()
	entry.id = &"start"
	entry.speaker_name = "الشيخ"
	entry.text = "اختبار الحوار"
	entry.set_flags = [&"intro_seen"]

	var choice: DialogueChoice = DialogueChoiceScript.new()
	choice.text = "قبول المهمة"
	choice.required_flags = [&"intro_seen"]
	choice.set_flags = [&"quest_accepted"]
	choice.start_quest_id = &"ash_trail"
	choice.target_node_id = &"after_choice"
	entry.choices.append(choice)

	var target: DialogueNode = DialogueNodeScript.new()
	target.id = &"after_choice"
	target.speaker_name = "الشيخ"
	target.text = "تم قبول المهمة"
	graph.entry_node_id = &"start"
	graph.nodes = [entry, target]

	var quest_requests: Array = []
	dialogue.quest_start_requested.connect(func(quest_id: StringName) -> void: quest_requests.append(quest_id))
	_check(bool(dialogue.call("start", graph)), "dialogue starts when a valid entry node exists")
	_check(bool(dialogue.call("is_active")), "dialogue manager reports active dialogue")
	_check(bool(dialogue.call("get_flag", &"intro_seen")), "entry node applies its flag effect")
	_check((dialogue.get("_current") as DialogueNode).id == &"start", "dialogue displays the entry node")

	dialogue.call("choose", 0)
	_check(bool(dialogue.call("get_flag", &"quest_accepted")), "choosing a dialogue option applies its flag")
	_check(quest_requests.size() == 1 and quest_requests[0] == &"ash_trail", "dialogue choice emits the expected quest request")
	_check(bool(quests.call("start_quest", quest_requests[0])), "quest manager accepts the dialogue's known quest ID")
	_check(String(quests.get("quest_id")) == "ash_trail", "quest manager stores the accepted quest ID")

	dialogue.call("next")
	_check(not bool(dialogue.call("is_active")), "dialogue ends after the final node")
	dialogue.call("deserialize", {"flags": {"restored_flag": true}})
	_check(bool(dialogue.call("get_flag", &"restored_flag")), "dialogue flags deserialize from saved data")

	var missing_graph: DialogueGraph = DialogueGraphScript.new()
	missing_graph.entry_node_id = &"missing"
	_check(not bool(dialogue.call("start", missing_graph)), "dialogue rejects a graph with a missing entry node")

	dialogue.queue_free()
	quests.queue_free()
	progression.queue_free()
	player.queue_free()


func _test_android_configuration() -> void:
	var preset_file := FileAccess.open("res://export_presets.cfg", FileAccess.READ)
	_check(preset_file != null, "Android export preset file is readable")
	if preset_file != null:
		var preset_text := preset_file.get_as_text()
		preset_file.close()
		_check(preset_text.contains('name="Android"'), "export presets contain the required Android preset")
		_check(preset_text.contains('package/unique_name="org.ashenkingdoms.game"'), "Android package identifier is configured")
		_check(preset_text.contains("architectures/arm64-v8a=true"), "Android ARM64 export architecture is enabled")

	var main_source_file := FileAccess.open("res://scripts/core/main.gd", FileAccess.READ)
	_check(main_source_file != null, "main script source is readable for input configuration checks")
	if main_source_file != null:
		var main_source := main_source_file.get_as_text()
		main_source_file.close()
		_check(main_source.contains("func _register_input_actions()"), "main defines the runtime input registration routine")
		for action in [&"move_forward", &"move_back", &"move_left", &"move_right", &"jump", &"sprint", &"inventory", &"pause", &"save", &"load", &"interact", &"attack"]:
			_check(main_source.contains(String(action)), "main input registration references action: %s" % String(action))


func _test_runtime_input_registration() -> void:
	var main_node := Node3D.new()
	main_node.set_script(MainScript)
	main_node.call("_register_input_actions")

	var actions: Array[StringName] = [
		&"move_forward", &"move_back", &"move_left", &"move_right",
		&"jump", &"sprint", &"inventory", &"pause", &"save", &"load",
		&"interact", &"attack"
	]
	var initial_event_counts: Dictionary = {}
	for action in actions:
		initial_event_counts[action] = InputMap.action_get_events(action).size()

	main_node.call("_register_input_actions")
	for action in actions:
		_check(
			InputMap.action_get_events(action).size() == int(initial_event_counts[action]),
			"runtime input registration is idempotent for %s" % String(action)
		)
	main_node.free()


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
