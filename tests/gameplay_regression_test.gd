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
	# Preserve all save-related files, not only the primary file. These tests
	# deliberately overwrite .bak and .tmp fixtures and must not destroy a
	# pre-existing backup when run against a developer's user:// directory.
	var had_original_backup := FileAccess.file_exists("user://savegame.json.bak")
	var original_backup: Variant = _read_text_file("user://savegame.json.bak") if had_original_backup else ""
	var had_original_temp := FileAccess.file_exists("user://savegame.json.tmp")
	var original_temp: Variant = _read_text_file("user://savegame.json.tmp") if had_original_temp else ""
	# Abort before mutating fixtures if an existing file could not be read.
	if (had_original_backup and original_backup == null) or (had_original_temp and original_temp == null):
		_check(false, "existing backup and temporary save files can be read before regression tests")
		return

	var save_system: Node = SaveSystemScript.new()
	root.add_child(save_system)

	_check(bool(save_system.call("save_game", {"level": 4, "health": 61.5, "flags": {"intro_seen": true}})), "save system writes structured data")
	var loaded = save_system.call("load_game")
	_check(loaded is Dictionary, "save system returns a dictionary for valid JSON")
	if loaded is Dictionary:
		_check(int(loaded.get("level", 0)) == 4, "saved progression values load correctly")
		_check(is_equal_approx(float(loaded.get("health", 0.0)), 61.5), "saved floating-point health loads correctly")
		var flags = loaded.get("flags", {})
		_check(flags is Dictionary and bool(flags.get("intro_seen", false)), "nested dialogue flags survive save/load")

	var malformed := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if malformed == null:
		_check(false, "test can create malformed JSON fixture")
	else:
		malformed.store_string("{not valid JSON")
		malformed.close()
		var corrupt = save_system.call("load_game")
		_check(corrupt is Dictionary and corrupt.is_empty(), "malformed JSON safely returns an empty dictionary")

	# Simulate a crash after the old save was moved to the backup but before the
	# temporary save replaced it. Loading should recover the backup immediately.
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	var backup_fixture := FileAccess.open("user://savegame.json.bak", FileAccess.WRITE)
	if backup_fixture == null:
		_check(false, "test can create a backup-only recovery fixture")
	else:
		backup_fixture.store_string(JSON.stringify({"recovered_level": 7}))
		backup_fixture.close()
		_check(bool(save_system.call("has_save")), "has_save recognizes a backup-only save")
		var recovered = save_system.call("load_game")
		_check(recovered is Dictionary and int(recovered.get("recovered_level", 0)) == 7, "load_game restores a backup when the primary save is missing")
		_check(FileAccess.file_exists(SAVE_PATH), "backup recovery restores the primary save path")


		# A corrupt primary must not prevent recovery of a valid backup.
		var corrupt_primary := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		var valid_backup := FileAccess.open("user://savegame.json.bak", FileAccess.WRITE)
		if corrupt_primary == null or valid_backup == null:
			_check(false, "test can create corrupt-primary and valid-backup fixtures")
			if corrupt_primary != null:
				corrupt_primary.close()
			if valid_backup != null:
				valid_backup.close()
		else:
			corrupt_primary.store_string("{broken primary")
			corrupt_primary.close()
			valid_backup.store_string(JSON.stringify({"recovered_level": 12}))
			valid_backup.close()
			var recovered_corrupt = save_system.call("load_game")
			_check(
				recovered_corrupt is Dictionary and int(recovered_corrupt.get("recovered_level", 0)) == 12,
				"load_game recovers valid backup when primary JSON is corrupt"
			)
			_check(FileAccess.file_exists(SAVE_PATH), "corrupt-primary recovery restores the primary save path")


		# A subsequent save must not delete a valid backup just because the
		# primary path exists but contains malformed JSON.
		var corrupt_before_save := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		var backup_before_save := FileAccess.open("user://savegame.json.bak", FileAccess.WRITE)
		if corrupt_before_save == null or backup_before_save == null:
			_check(false, "test can create corrupt-primary save fixture")
			if corrupt_before_save != null:
				corrupt_before_save.close()
			if backup_before_save != null:
				backup_before_save.close()
		else:
			corrupt_before_save.store_string("{bad primary")
			corrupt_before_save.close()
			backup_before_save.store_string(JSON.stringify({"older_level": 4}))
			backup_before_save.close()
			var saved_after_recovery := bool(save_system.call("save_game", {"fresh_save": true}))
			var fresh_data = save_system.call("load_game")
			_check(saved_after_recovery, "save_game succeeds after recovering a valid backup")
			_check(
				fresh_data is Dictionary and bool(fresh_data.get("fresh_save", false)),
				"new save replaces the recovered backup only after a successful write"
			)

	_restore_original_save(had_original_save, original_save, save_system)
	_restore_auxiliary_save_file("user://savegame.json.bak", had_original_backup, original_backup)
	_restore_auxiliary_save_file("user://savegame.json.tmp", had_original_temp, original_temp)
	_check(
		bool(save_system.call("has_save")) if had_original_save or had_original_backup else not bool(save_system.call("has_save")),
		"save fixtures are cleaned up or original save files are restored"
	)
	save_system.queue_free()


func _read_text_file(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var content := file.get_as_text()
	file.close()
	return content


func _restore_auxiliary_save_file(path: String, had_original_file: bool, original_content: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path) and DirAccess.remove_absolute(absolute_path) != OK:
		_check(false, "test-generated save file can be removed: %s" % path)
		return
	if not had_original_file:
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "original save-related file can be restored: %s" % path)
		return
	file.store_string(original_content)
	file.close()


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
