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

const SAVE_PATH := "user://savegame.json"
const TEMP_SAVE_PATH := "user://savegame.json.tmp"
const BACKUP_SAVE_PATH := "user://savegame.json.bak"

var _original_aux_files: Dictionary = {}
const POTION_PATH := "res://resources/items/health_potion.tres"

var _failures := 0
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var had_original_save := FileAccess.file_exists(SAVE_PATH)
	var original_save := ""
	if had_original_save:
		var original_file := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if original_file == null:
			_check(false, "existing save can be backed up before regression tests")
			quit(1)
			return
		original_save = original_file.get_as_text()
		original_file.close()

	for path in [TEMP_SAVE_PATH, BACKUP_SAVE_PATH]:
		var exists := FileAccess.file_exists(path)
		_original_aux_files[path] = {"exists": exists, "text": FileAccess.get_file_as_string(path) if exists else ""}

	_test_player_and_health()
	_test_inventory_and_potions()
	_test_save_and_load(had_original_save, original_save)
	_test_dialogue_and_quests()
	_test_quest_reward_idempotency()
	_test_android_configuration()
	_test_runtime_input_registration()

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


func _test_save_and_load(had_original_save: bool, original_save: String) -> void:
	var save_system: Node = SaveSystemScript.new()
	root.add_child(save_system)

	var sample_data: Dictionary = {
		"version": 1,
		"player_position": {"x": 1.0, "y": 0.92, "z": -2.0},
		"player_health": 61.5,
		"level": 4,
		"experience": 12,
		"inventory": [],
		"quest": {},
		"dialogue": {"flags": {"intro_seen": true}},
	}
	_check(bool(save_system.call("save_game", sample_data)), "save system writes schema-valid structured data")
	var loaded = save_system.call("load_game")
	_check(loaded is Dictionary, "save system returns a dictionary for valid JSON")
	if loaded is Dictionary:
		_check(int(loaded.get("level", 0)) == 4, "saved progression values load correctly")
		_check(is_equal_approx(float(loaded.get("player_health", 0.0)), 61.5), "saved floating-point health loads correctly")
		var flags = loaded.get("dialogue", {}).get("flags", {})
		_check(flags is Dictionary and bool(flags.get("intro_seen", false)), "nested dialogue flags survive save/load")

	_remove_if_exists(BACKUP_SAVE_PATH)
	var malformed := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if malformed == null:
		_check(false, "test can create malformed JSON fixture")
	else:
		malformed.store_string("{not valid JSON")
		malformed.close()
		var corrupt = save_system.call("load_game")
		_check(corrupt is Dictionary and corrupt.is_empty(), "malformed JSON safely returns an empty dictionary")

	_restore_original_save(had_original_save, original_save, save_system)
	_check(not bool(save_system.call("has_save")) if not had_original_save else bool(save_system.call("has_save")), "save fixture is cleaned up or original save is restored")
	save_system.queue_free()


func _restore_original_save(had_original_save: bool, original_save: String, save_system: Node) -> void:
	if had_original_save:
		var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if file == null:
			_check(false, "original save can be restored after test")
			return
		file.store_string(original_save)
		file.close()
	else:
		_check(bool(save_system.call("delete_save")), "temporary save file is removed after test")

	for path in _original_aux_files.keys():
		_remove_if_exists(path)
		var original: Dictionary = _original_aux_files[path]
		if bool(original["exists"]):
			var restore_aux := FileAccess.open(path, FileAccess.WRITE)
			if restore_aux == null:
				_check(false, "original auxiliary save file can be restored: %s" % path)
			else:
				restore_aux.store_string(str(original["text"]))
				restore_aux.close()


func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


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


func _test_quest_reward_idempotency() -> void:
	var progression_before: Node = ProgressionScript.new()
	progression_before.name = "QuestRewardProgressionBefore"
	root.add_child(progression_before)
	var quests_before: Node = QuestManagerScript.new()
	quests_before.name = "QuestRewardManagerBefore"
	quests_before.set("progression", progression_before)
	root.add_child(quests_before)

	_check(bool(quests_before.call("start_quest", &"ash_trail")), "reward idempotency fixture starts the known quest")
	var completion_events: Array = []
	quests_before.connect("quest_completed", func(_title: String, _reward_xp: int) -> void: completion_events.append(true))
	for _kill in range(3):
		quests_before.call("on_enemy_defeated", &"ash_wraith")
	_check(int(progression_before.get("experience")) == 75, "quest grants its configured reward exactly once on completion")
	_check(completion_events.size() == 1, "quest completion signal fires once")
	var saved_quest: Dictionary = quests_before.call("to_save_data")

	var progression_after: Node = ProgressionScript.new()
	progression_after.name = "QuestRewardProgressionAfter"
	root.add_child(progression_after)
	progression_after.call("restore_state", int(progression_before.get("level")), int(progression_before.get("experience")))
	var quests_after: Node = QuestManagerScript.new()
	quests_after.name = "QuestRewardManagerAfter"
	quests_after.set("progression", progression_after)
	root.add_child(quests_after)
	quests_after.call("load_state", saved_quest)
	quests_after.call("on_enemy_defeated", &"ash_wraith")
	_check(int(progression_after.get("experience")) == 75, "completed quest cannot grant its reward again after save/reload")
	_check(not bool(quests_after.call("start_quest", &"ash_trail")), "completed quest cannot be restarted to farm its reward")
	_check(int(quests_after.get("progress")) == 3 and not bool(quests_after.get("active")), "completed quest state remains completed after reload")

	quests_after.free()
	progression_after.free()
	quests_before.free()
	progression_before.free()


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
