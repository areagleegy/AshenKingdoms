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

const SAVE_PATH := "user://ashenkingdoms_regression/savegame.json"
const SAVE_DIR := "user://ashenkingdoms_regression"
const POTION_PATH := "res://resources/items/health_potion.tres"

var _failures := 0
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	for path in [SAVE_PATH, SAVE_PATH + ".tmp", SAVE_PATH + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
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

	_test_player_and_health()
	_test_inventory_and_potions()
	_test_save_and_load(had_original_save, original_save)
	_test_dialogue_and_quests()
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
	save_system.set("save_path", SAVE_PATH)
	root.add_child(save_system)

	var first_save := _valid_save_data(4, 61.5)
	_check(bool(save_system.call("save_game", first_save)), "save system writes a schema-valid save")
	var loaded: Dictionary = save_system.call("load_game")
	_check(loaded is Dictionary and int(loaded.get("version", 0)) == 1, "save system returns the current schema version")
	_check(int(loaded.get("level", 0)) == 4, "saved progression values load correctly")
	_check(is_equal_approx(float(loaded.get("player_health", 0.0)), 61.5), "saved floating-point health loads correctly")
	var dialogue: Dictionary = loaded.get("dialogue", {})
	var flags: Dictionary = dialogue.get("flags", {})
	_check(bool(flags.get("intro_seen", false)), "nested dialogue flags survive save/load")

	_check(bool(save_system.call("save_game", _valid_save_data(5, 70.0))), "second save commits successfully")
	_check(FileAccess.file_exists(SAVE_PATH + ".bak"), "atomic save keeps the previous save as a backup")

	var malformed := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if malformed == null:
		_check(false, "test can create malformed JSON fixture")
	else:
		malformed.store_string("{not valid JSON")
		malformed.close()
	var recovered: Dictionary = save_system.call("load_game")
	_check(int(recovered.get("level", 0)) == 4, "corrupt primary save falls back to the previous valid backup")

	_check(bool(save_system.call("delete_save")), "save test can remove primary, temporary, and backup files")
	var malformed_without_backup := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if malformed_without_backup == null:
		_check(false, "test can create malformed JSON without a backup")
	else:
		malformed_without_backup.store_string("{not valid JSON")
		malformed_without_backup.close()
	var corrupt = save_system.call("load_game")
	_check(corrupt is Dictionary and corrupt.is_empty(), "malformed JSON without a valid backup is rejected")

	var incomplete := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if incomplete == null:
		_check(false, "test can create a missing-fields fixture")
	else:
		incomplete.store_string(JSON.stringify({"version": 1, "level": 1}))
		incomplete.close()
	var missing_fields = save_system.call("load_game")
	_check(missing_fields is Dictionary and missing_fields.is_empty(), "save with missing required fields is rejected")

	var invalid_range := _valid_save_data(3, 45.0)
	invalid_range["player_position"]["x"] = 1000001.0
	var invalid_range_file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if invalid_range_file == null:
		_check(false, "test can create an out-of-range save fixture")
	else:
		invalid_range_file.store_string(JSON.stringify(invalid_range))
		invalid_range_file.close()
	var rejected_range = save_system.call("load_game")
	_check(rejected_range is Dictionary and rejected_range.is_empty(), "out-of-range world coordinates are rejected")

	var unsupported_version := _valid_save_data(3, 45.0)
	unsupported_version["version"] = 999
	var unsupported_file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if unsupported_file == null:
		_check(false, "test can create an unsupported-version save fixture")
	else:
		unsupported_file.store_string(JSON.stringify(unsupported_version))
		unsupported_file.close()
	var rejected_version = save_system.call("load_game")
	_check(rejected_version is Dictionary and rejected_version.is_empty(), "unsupported save schema versions are rejected")

	var versionless := _valid_save_data(3, 45.0)
	versionless.erase("version")
	var legacy_file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if legacy_file == null:
		_check(false, "test can create a versionless legacy save")
	else:
		legacy_file.store_string(JSON.stringify(versionless))
		legacy_file.close()
	var migrated: Dictionary = save_system.call("load_game")
	_check(int(migrated.get("version", 0)) == 1, "valid versionless legacy save migrates to schema version 1")

	var preserved := JSON.stringify(_valid_save_data(6, 80.0), "\t")
	_check(bool(save_system.call("save_game", _valid_save_data(6, 80.0))), "save system accepts a valid replacement before failed-write test")
	var existing_file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var existing_contents := existing_file.get_as_text() if existing_file != null else ""
	if existing_file != null:
		existing_file.close()
	save_system.set("save_path", SAVE_DIR + "/missing-parent/savegame.json")
	_check(not bool(save_system.call("save_game", _valid_save_data(7, 90.0))), "failed temporary-file open is reported as a failed save")
	save_system.set("save_path", SAVE_PATH)
	var after_failed_write := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var after_failed_contents := after_failed_write.get_as_text() if after_failed_write != null else ""
	if after_failed_write != null:
		after_failed_write.close()
	_check(after_failed_contents == existing_contents and after_failed_contents == preserved, "failed write leaves the committed save unchanged")

	_restore_original_save(had_original_save, original_save, save_system)
	_check(not bool(save_system.call("has_save")) if not had_original_save else bool(save_system.call("has_save")), "test save artifacts are cleaned up or original save is restored")
	save_system.queue_free()


func _valid_save_data(level: int, health: float) -> Dictionary:
	return {
		"version": 1,
		"player_position": {"x": 1.0, "y": 0.92, "z": -2.0},
		"player_health": health,
		"level": level,
		"experience": 125,
		"inventory": [{"id": "health_potion", "amount": 2}],
		"quest": {"id": "ash_trail", "title": "اقتفاء الرماد", "progress": 1, "active": true},
		"dialogue": {"flags": {"intro_seen": true}}
	}

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
