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
const SAVE_ARTIFACT_PATHS := [
	"user://savegame.json",
	"user://savegame.json.tmp",
	"user://savegame.json.bak",
	"user://savegame.json.bak.tmp",
	"user://savegame.json.old",
	"user://savegame.json.bak.old"
]
const POTION_PATH := "res://resources/items/health_potion.tres"

var _failures := 0
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var original_artifacts := _snapshot_save_artifacts()
	if original_artifacts.size() != SAVE_ARTIFACT_PATHS.size():
		_check(false, "all original save artifacts can be preserved before regression tests")
		quit(1)
		return

	_test_player_and_health()
	_test_inventory_and_potions()
	_test_save_and_load()
	_restore_save_artifacts(original_artifacts)
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


func _test_save_and_load() -> void:
	var save_system: Node = SaveSystemScript.new()
	root.add_child(save_system)
	_check(bool(save_system.call("delete_save")), "save test starts from an isolated state")

	var saved_inventory: Array = []
	for _slot_index in range(24):
		saved_inventory.append(null)
	saved_inventory[0] = {"id": "health_potion", "amount": 3}
	var first_data := {
		"version": 1,
		"player_position": {"x": 12.5, "y": 0.92, "z": -3.25},
		"player_health": 61.5,
		"level": 4,
		"experience": 23,
		"inventory": saved_inventory,
		"quest": {"id": "ash_trail", "title": "اقتفاء الرماد", "progress": 1, "active": true},
		"dialogue": {"flags": {"intro_seen": true, "quest_accepted": true}}
	}
	_check(bool(save_system.call("save_game", first_data)), "save system writes the actual main.gd gameplay save shape")
	var loaded = save_system.call("load_game")
	_check(loaded is Dictionary, "save system returns a dictionary for valid JSON")
	if loaded is Dictionary:
		_check(int(loaded.get("version", 0)) == 1, "save schema version survives save/load")
		_check(int(loaded.get("level", 0)) == 4 and int(loaded.get("experience", -1)) == 23, "saved progression values load correctly")
		_check(is_equal_approx(float(loaded.get("player_health", 0.0)), 61.5), "saved player health loads correctly")
		var position_data = loaded.get("player_position", {})
		_check(
			position_data is Dictionary
			and is_equal_approx(float(position_data.get("x", 0.0)), 12.5)
			and is_equal_approx(float(position_data.get("y", 0.0)), 0.92)
			and is_equal_approx(float(position_data.get("z", 0.0)), -3.25),
			"saved player position round-trips with all coordinates"
		)
		var restored_inventory = loaded.get("inventory", [])
		_check(
			restored_inventory is Array
			and restored_inventory.size() == 24
			and restored_inventory[0] is Dictionary
			and str(restored_inventory[0].get("id", "")) == "health_potion"
			and int(restored_inventory[0].get("amount", 0)) == 3,
			"actual inventory slot data survives save/load"
		)
		var quest_data = loaded.get("quest", {})
		_check(
			quest_data is Dictionary
			and str(quest_data.get("id", "")) == "ash_trail"
			and int(quest_data.get("progress", -1)) == 1
			and bool(quest_data.get("active", false)),
			"actual quest state survives save/load"
		)
		var dialogue_data = loaded.get("dialogue", {})
		var flags = dialogue_data.get("flags", {}) if dialogue_data is Dictionary else {}
		_check(flags is Dictionary and bool(flags.get("intro_seen", false)) and bool(flags.get("quest_accepted", false)), "serialized dialogue flags survive save/load")

	var second_data: Dictionary = first_data.duplicate(true)
	second_data["level"] = 5
	second_data["player_health"] = 42.0
	second_data["player_position"]["x"] = 14.0
	_check(bool(save_system.call("save_game", second_data)), "subsequent save replaces the primary file")
	var malformed := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if malformed == null:
		_check(false, "test can create malformed JSON fixture")
	else:
		malformed.store_string("{not valid JSON")
		malformed.flush()
		malformed.close()
		var recovered = save_system.call("load_game")
		_check(
			recovered is Dictionary
			and int(recovered.get("level", 0)) == 4
			and is_equal_approx(float(recovered.get("player_health", 0.0)), 61.5)
			and is_equal_approx(float(recovered.get("player_position", {}).get("x", 0.0)), 12.5),
			"corrupt primary save recovers the previous main.gd-compatible gameplay snapshot"
		)
		_check(bool(save_system.call("has_save")), "valid backup remains discoverable after recovery")

	var backup_path := SAVE_PATH + ".bak"
	if FileAccess.file_exists(backup_path):
		_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path)) == OK, "test removes backup before recovery checks")
	_check(
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH)) == OK,
		"test removes primary save to simulate an interrupted first save"
	)
	var staged_path := SAVE_PATH + ".tmp"
	var staged_file := FileAccess.open(staged_path, FileAccess.WRITE)
	if staged_file == null:
		_check(false, "test can create a complete staged save fixture")
	else:
		staged_file.store_string(JSON.stringify(first_data, "\t"))
		staged_file.flush()
		var staged_write_error: Error = staged_file.get_error()
		staged_file.close()
		_check(staged_write_error == OK, "complete staged save fixture is written")
		var staged_recovered = save_system.call("load_game")
		_check(
			staged_recovered is Dictionary
			and int(staged_recovered.get("level", 0)) == 4
			and is_equal_approx(float(staged_recovered.get("player_health", 0.0)), 61.5),
			"valid staged data recovers an interrupted first save"
		)

	var unsupported := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if unsupported == null:
		_check(false, "test can create unsupported-schema fixture")
	else:
		unsupported.store_string("{\"version\":99,\"level\":4}")
		unsupported.flush()
		unsupported.close()
		var unsupported_data = save_system.call("load_game")
		_check(unsupported_data is Dictionary and unsupported_data.is_empty(), "unsupported save schema is rejected safely")

	var invalid_position := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if invalid_position == null:
		_check(false, "test can create invalid-field fixture")
	else:
		invalid_position.store_string("{\"version\":1,\"player_position\":{\"x\":0,\"y\":\"invalid\",\"z\":0}}")
		invalid_position.flush()
		invalid_position.close()
		var invalid_data = save_system.call("load_game")
		_check(invalid_data is Dictionary and invalid_data.is_empty(), "save fields with invalid types are rejected")
		_check(not bool(save_system.call("has_save")), "invalid primary and missing backup are not considered recoverable")

	_check(bool(save_system.call("delete_save")), "save test removes temporary and backup artifacts")
	save_system.queue_free()


func _snapshot_save_artifacts() -> Dictionary:
	var snapshots: Dictionary = {}
	for path in SAVE_ARTIFACT_PATHS:
		var snapshot := {"exists": FileAccess.file_exists(path), "content": PackedByteArray()}
		if bool(snapshot["exists"]):
			var file := FileAccess.open(path, FileAccess.READ)
			if file == null:
				push_error("Cannot preserve existing save artifact before tests: %s" % path)
				return {}
			var size := file.get_length()
			if size > 2 * 1024 * 1024:
				file.close()
				push_error("Save artifact is unexpectedly large; refusing to alter test state: %s" % path)
				return {}
			var bytes := file.get_buffer(size)
			file.close()
			if bytes.size() != size:
				push_error("Cannot read the full save artifact before tests: %s" % path)
				return {}
			snapshot["content"] = bytes
		snapshots[path] = snapshot
	return snapshots


func _restore_save_artifacts(snapshots: Dictionary) -> void:
	for path in SAVE_ARTIFACT_PATHS:
		if FileAccess.file_exists(path):
			if DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) != OK:
				_check(false, "test save artifact can be removed before restoring original state")
				continue
		var snapshot: Dictionary = snapshots.get(path, {})
		if not bool(snapshot.get("exists", false)):
			continue
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			_check(false, "original save artifact can be restored")
			continue
		var original_bytes: PackedByteArray = snapshot.get("content", PackedByteArray())
		file.store_buffer(original_bytes)
		file.flush()
		var write_error: Error = file.get_error()
		file.close()
		_check(write_error == OK, "original save artifact contents are restored")


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
