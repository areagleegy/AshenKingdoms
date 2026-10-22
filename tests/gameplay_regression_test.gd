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
const InputSetupScript = preload("res://scripts/core/input_setup.gd")
const MainScript = preload("res://scripts/core/main.gd")

const SAVE_PATH := "user://savegame.json"
const SAVE_BACKUP_PATH := "user://savegame.json.bak"
const SAVE_TEMP_PATH := "user://savegame.json.tmp"
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
	_test_safe_saved_values()
	_test_dialogue_and_quests()
	_test_android_configuration()
	_test_runtime_input_registration()
	_test_gamepad_input_bindings()
	_test_analog_movement_magnitude()
	_test_controller_navigation_configuration()

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

	var hostile_inventory: Node = InventoryScript.new()
	hostile_inventory.name = "HostileInventory"
	root.add_child(hostile_inventory)
	var hostile_entries: Array = [
		{"id": "health_potion", "amount": INF},
		{"id": "health_potion", "amount": "999"},
		{"id": "health_potion", "amount": 2.5},
		{"id": "health_potion", "amount": 99999999999}
	]
	hostile_inventory.call("restore_save_data", hostile_entries)
	_check(
		int(hostile_inventory.call("count_item", &"health_potion")) == 3 + int(potion.max_stack),
		"inventory restore rejects malformed stack counts and clamps oversized counts"
	)
	hostile_inventory.queue_free()
	restored.queue_free()
	player.queue_free()


func _test_save_and_load(had_original_save: bool, original_save: String) -> void:
	var had_original_backup := FileAccess.file_exists(SAVE_BACKUP_PATH)
	var original_backup := ""
	if had_original_backup:
		var backup_file := FileAccess.open(SAVE_BACKUP_PATH, FileAccess.READ)
		if backup_file == null:
			_check(false, "existing backup can be backed up before regression tests")
			return
		original_backup = backup_file.get_as_text()
		backup_file.close()

	var had_original_temp := FileAccess.file_exists(SAVE_TEMP_PATH)
	var original_temp := ""
	if had_original_temp:
		var temp_file := FileAccess.open(SAVE_TEMP_PATH, FileAccess.READ)
		if temp_file == null:
			_check(false, "existing temporary save can be backed up before regression tests")
			return
		original_temp = temp_file.get_as_text()
		temp_file.close()

	var save_system: Node = SaveSystemScript.new()
	root.add_child(save_system)

	_check(
		not bool(save_system.call("save_game", {"oversized": "x".repeat(1024 * 1024)})),
		"save system rejects payloads larger than the configured size limit"
	)
	_check(bool(save_system.call("save_game", {"level": 4, "health": 61.5, "flags": {"intro_seen": true}})), "save system writes a validated snapshot")
	var loaded = save_system.call("load_game")
	_check(loaded is Dictionary, "save system returns a dictionary for valid JSON")
	if loaded is Dictionary:
		_check(int(loaded.get("level", 0)) == 4, "saved progression values load correctly")
		_check(is_equal_approx(float(loaded.get("health", 0.0)), 61.5), "saved floating-point health loads correctly")
		var flags = loaded.get("flags", {})
		_check(flags is Dictionary and bool(flags.get("intro_seen", false)), "nested dialogue flags survive save/load")

	_check(bool(save_system.call("save_game", {"level": 5, "health": 42.0})), "second save preserves the previous valid snapshot")
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
			and is_equal_approx(float(recovered.get("health", 0.0)), 61.5),
			"malformed primary save recovers the last known-good backup"
		)
		_check(bool(save_system.call("has_save")), "backup recovery leaves a usable save")

	# Simulate a crash after the temporary snapshot was flushed but before it
	# replaced the primary file. Preserve existing developer fixtures above.
	_check(bool(save_system.call("delete_save")), "backup-recovery fixture is cleared for temp recovery test")
	var flushed_temp := FileAccess.open(SAVE_TEMP_PATH, FileAccess.WRITE)
	if flushed_temp == null:
		_check(false, "test can create a flushed temporary save fixture")
	else:
		flushed_temp.store_string(JSON.stringify({"level": 6, "health": 73.0}))
		flushed_temp.flush()
		var temp_write_error: Error = flushed_temp.get_error()
		flushed_temp.close()
		_check(temp_write_error == OK, "temporary save fixture is fully written")
		var recovered_temp = save_system.call("load_game")
		_check(
			recovered_temp is Dictionary
			and int(recovered_temp.get("level", 0)) == 6
			and is_equal_approx(float(recovered_temp.get("health", 0.0)), 73.0),
			"missing primary recovers the latest valid flushed temporary snapshot"
		)
		_check(FileAccess.file_exists(SAVE_PATH), "temporary snapshot recovery recreates the primary save")
		_check(not FileAccess.file_exists(SAVE_TEMP_PATH), "temporary snapshot is removed after successful recovery")
		_check(bool(save_system.call("has_save")), "temporary snapshot recovery leaves a usable save")

		_check(bool(save_system.call("save_game", {"level": 8})), "save system keeps a backup before the next replacement")
		var oversized_primary := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if oversized_primary == null:
			_check(false, "test can create an oversized primary save fixture")
		else:
			oversized_primary.store_string(JSON.stringify({"payload": "x".repeat(1024 * 1024)}))
			oversized_primary.flush()
			var oversized_write_error: Error = oversized_primary.get_error()
			oversized_primary.close()
			_check(oversized_write_error == OK, "oversized primary fixture is written")
			var recovered_from_oversize = save_system.call("load_game")
			_check(
				recovered_from_oversize is Dictionary
				and int(recovered_from_oversize.get("level", 0)) == 6,
				"oversized on-disk save is rejected and recovers the known-good backup"
			)

	_restore_original_save(
		had_original_save, original_save,
		had_original_backup, original_backup,
		had_original_temp, original_temp,
		save_system
	)
	_check(FileAccess.file_exists(SAVE_PATH) == had_original_save, "original primary save presence is restored")
	_check(FileAccess.file_exists(SAVE_BACKUP_PATH) == had_original_backup, "original backup presence is restored")
	_check(FileAccess.file_exists(SAVE_TEMP_PATH) == had_original_temp, "original temporary-file presence is restored")
	save_system.queue_free()


func _restore_original_save(
	had_original_save: bool,
	original_save: String,
	had_original_backup: bool,
	original_backup: String,
	had_original_temp: bool,
	original_temp: String,
	save_system: Node
) -> void:
	_check(bool(save_system.call("delete_save")), "save test files are removed before restoring fixtures")
	_restore_text_fixture(SAVE_PATH, had_original_save, original_save, "primary save")
	_restore_text_fixture(SAVE_BACKUP_PATH, had_original_backup, original_backup, "backup save")
	_restore_text_fixture(SAVE_TEMP_PATH, had_original_temp, original_temp, "temporary save")


func _restore_text_fixture(path: String, should_exist: bool, contents: String, description: String) -> void:
	if not should_exist:
		_check(not FileAccess.file_exists(path), "%s is absent after cleanup" % description)
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "original %s can be restored" % description)
		return
	file.store_string(contents)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	_check(write_error == OK, "original %s content is restored" % description)


func _test_safe_saved_values() -> void:
	var main_node := Node3D.new()
	main_node.set_script(MainScript)

	_check(
		is_equal_approx(float(main_node.call("_safe_saved_float", 12.5, 3.0)), 12.5),
		"save value sanitizer preserves finite numeric values"
	)
	_check(
		is_equal_approx(float(main_node.call("_safe_saved_float", NAN, 3.0)), 3.0),
		"save value sanitizer replaces NaN with a safe fallback"
	)
	_check(
		is_equal_approx(float(main_node.call("_safe_saved_float", INF, 3.0)), 3.0),
		"save value sanitizer replaces infinity with a safe fallback"
	)
	_check(
		is_equal_approx(float(main_node.call("_safe_saved_float", "bad", 3.0)), 3.0),
		"save value sanitizer rejects nonnumeric types"
	)
	_check(
		int(main_node.call("_safe_saved_int", 9999999999, 1, 1, 50)) == 50,
		"saved progression level is clamped to its supported maximum"
	)
	_check(
		int(main_node.call("_safe_saved_int", NAN, 3, 1, 50)) == 3,
		"invalid saved progression values use a safe default"
	)

	var position: Vector3 = main_node.call(
		"_safe_saved_position",
		{"x": INF, "y": -500.0, "z": 500.0}
	)
	_check(
		position.is_equal_approx(Vector3(0.0, 0.92, 39.0)),
		"saved position rejects non-finite coordinates and clamps out-of-world positions"
	)
	var invalid_position: Vector3 = main_node.call("_safe_saved_position", "invalid")
	_check(
		invalid_position.is_equal_approx(Vector3(0.0, 0.92, 0.0)),
		"saved position falls back safely when its object is malformed"
	)
	main_node.free()


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

	var long_flag_name := "x".repeat(129)
	var malformed_flags: Dictionary = {
		"known_flag": true,
		"string_flag": "true",
		long_flag_name: true
	}
	dialogue.call("deserialize", {"flags": malformed_flags})
	_check(bool(dialogue.call("get_flag", &"known_flag")), "dialogue restore retains valid Boolean flags")
	_check(not bool(dialogue.call("get_flag", &"string_flag")), "dialogue restore rejects non-Boolean flag values")
	_check(dialogue.get("flags").size() == 1, "dialogue restore rejects overlong flag names")

	var excessive_flags: Dictionary = {}
	for flag_index in range(300):
		excessive_flags["flag_%03d" % flag_index] = true
	dialogue.call("deserialize", {"flags": excessive_flags})
	_check(
		dialogue.get("flags").size() == 256,
		"dialogue restore enforces a hard cap on processed saved flag entries"
	)

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
		_check(preset_text.contains('name="Android"'), "export presets contain the required Android test preset")
		_check(preset_text.contains('package/unique_name="org.ashenkingdoms.game"'), "Android package identifier is configured")
		_check(preset_text.contains("architectures/arm64-v8a=true"), "Android ARM64 export architecture is enabled")
		_check(preset_text.contains('name="Android Play"'), "export presets contain a separate Google Play App Bundle preset")
		_check(preset_text.contains('export_path="build/android/AshenKingdoms.aab"'), "Google Play preset writes an AAB artifact")
		_check(preset_text.contains("gradle_build/use_gradle_build=true"), "Google Play export enables the Gradle build template")
		_check(preset_text.contains("gradle_build/export_format=1"), "Google Play export format selects Android App Bundle")
		_check(preset_text.contains('gradle_build/target_sdk="36"'), "Google Play preset explicitly targets Android API 36")
		_check(preset_text.contains('keystore/release=""'), "release keystore path is blank in the committed preset")
		_check(preset_text.contains('keystore/release_password=""'), "release keystore password is not committed")

	var release_workflow_file := FileAccess.open("res://.github/workflows/android-release.yml", FileAccess.READ)
	_check(release_workflow_file != null, "manual Android release workflow is present")
	if release_workflow_file != null:
		var release_workflow := release_workflow_file.get_as_text()
		release_workflow_file.close()
		_check(release_workflow.contains("workflow_dispatch:"), "Android release is started manually")
		_check(not release_workflow.contains("pull_request:"), "release signing is not triggered by pull requests")
		_check(release_workflow.contains("if: github.ref == 'refs/heads/main'"), "release workflow is restricted to main")
		_check(release_workflow.contains("name: android-release"), "release workflow uses the protected environment")
		_check(release_workflow.contains("ANDROID_KEYSTORE_BASE64"), "release workflow expects a keystore secret")
		_check(release_workflow.contains("ANDROID_KEYSTORE_PASSWORD"), "release workflow expects the keystore password secret")
		_check(release_workflow.contains("ANDROID_KEYSTORE_ALIAS"), "release workflow expects the keystore alias secret")
		_check(release_workflow.contains("int(version_code) > 2100000000"), "release workflow rejects version codes above the Google Play maximum")
		_check(release_workflow.contains("version_name must be 1-50 characters"), "release workflow validates the display version name")
		_check(release_workflow.contains("concurrency:"), "release workflow prevents overlapping signing jobs")
		_check(release_workflow.contains("platforms;android-36"), "release workflow installs the required Android API 36 platform")
		_check(release_workflow.contains('--install-android-build-template --export-release "Android Play"'), "release workflow installs the Gradle template during AAB export")
		_check(not release_workflow.contains("- name: Install Android Gradle build template"), "release workflow avoids a standalone template-install step")
		_check(release_workflow.contains("must target API 36"), "release workflow fails when the Google Play target SDK drifts")
		_check(release_workflow.contains("jarsigner -verify"), "release workflow verifies the AAB signature")
		_check(release_workflow.contains("ashen-kingdoms-android-play-release"), "release workflow uploads a distinct signed AAB artifact")

	var generic_workflow_file := FileAccess.open("res://.github/workflows/build.yml", FileAccess.READ)
	_check(generic_workflow_file != null, "generic platform workflow is readable")
	if generic_workflow_file != null:
		var generic_workflow := generic_workflow_file.get_as_text()
		generic_workflow_file.close()
		_check(not generic_workflow.contains("secrets.ANDROID_KEYSTORE_BASE64"), "generic CI does not receive the release keystore secret")
		_check(not generic_workflow.contains("Export signed Google Play App Bundle"), "real release signing is isolated from pull-request CI")
		_check(generic_workflow.contains("Validate Google Play App Bundle export (ephemeral signing key)"), "generic CI exercises AAB export with an ephemeral test key")
		_check(generic_workflow.contains('--install-android-build-template --export-release "Android Play"'), "generic AAB validation installs the Gradle template in the export command")
		_check(not generic_workflow.contains("Install Android Gradle build template"), "generic AAB validation does not run a separate template-install process")
		_check(generic_workflow.contains('trap \'rm -f "$keystore_path" build/android/AshenKingdoms-validation.aab\' EXIT'), "ephemeral AAB signing files are removed even if validation fails")
		_check(generic_workflow.contains("actions/checkout@v7"), "build workflow uses Node 24 compatible checkout")
		_check(generic_workflow.contains("actions/upload-artifact@v7"), "build workflow uses Node 24 compatible artifact upload")
		_check(generic_workflow.contains("actions/setup-java@v6"), "Android build uses current setup-java action")
		_check(generic_workflow.contains("android-actions/setup-android@v4"), "Android build uses current setup-android action")
		_check(not generic_workflow.contains("actions/checkout@v4"), "build workflow does not pin deprecated Node 20 checkout")
		_check(not generic_workflow.contains("actions/upload-artifact@v4"), "build workflow does not pin deprecated Node 20 artifact upload")

	var validation_workflow_file := FileAccess.open("res://.github/workflows/validate.yml", FileAccess.READ)
	_check(validation_workflow_file != null, "validation workflow is readable for action-runtime checks")
	if validation_workflow_file != null:
		var validation_workflow := validation_workflow_file.get_as_text()
		validation_workflow_file.close()
		_check(validation_workflow.contains("actions/checkout@v7"), "validation workflow uses Node 24 compatible checkout")
		_check(validation_workflow.contains("actions/upload-artifact@v7"), "validation workflow uses Node 24 compatible artifact upload")
		_check(not validation_workflow.contains("actions/checkout@v4"), "validation workflow does not pin deprecated Node 20 checkout")
		_check(not validation_workflow.contains("actions/upload-artifact@v4"), "validation workflow does not pin deprecated Node 20 artifact upload")

	var main_source_file := FileAccess.open("res://scripts/core/input_setup.gd", FileAccess.READ)
	_check(main_source_file != null, "shared input setup source is readable")
	if main_source_file != null:
		var main_source := main_source_file.get_as_text()
		main_source_file.close()
		_check(main_source.contains("static func register_input_actions()"), "shared input setup defines the runtime input registration routine")
		for action in [&"move_forward", &"move_back", &"move_left", &"move_right", &"look_left", &"look_right", &"look_up", &"look_down", &"jump", &"sprint", &"inventory", &"pause", &"save", &"load", &"interact", &"attack", &"ui_accept", &"ui_cancel", &"ui_up", &"ui_down", &"ui_left", &"ui_right"]:
			_check(main_source.contains(String(action)), "shared input setup references action: %s" % String(action))
		_check(main_source.contains("JOY_AXIS_TRIGGER_RIGHT"), "right trigger is mapped as an alternate attack input")


func _test_runtime_input_registration() -> void:
	InputSetupScript.register_input_actions()

	var actions: Array[StringName] = [
		&"move_forward", &"move_back", &"move_left", &"move_right",
		&"look_left", &"look_right", &"look_up", &"look_down",
		&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_accept", &"ui_cancel",
		&"jump", &"sprint", &"inventory", &"pause", &"save", &"load",
		&"interact", &"attack"
	]
	var initial_event_counts: Dictionary = {}
	for action in actions:
		initial_event_counts[action] = InputMap.action_get_events(action).size()

	InputSetupScript.register_input_actions()
	for action in actions:
		_check(
			InputMap.action_get_events(action).size() == int(initial_event_counts[action]),
			"runtime input registration is idempotent for %s" % String(action)
		)


func _test_gamepad_input_bindings() -> void:
	_check(_has_joypad_axis(&"move_left", JOY_AXIS_LEFT_X, -1.0), "left stick X maps to move left")
	_check(_has_joypad_axis(&"move_right", JOY_AXIS_LEFT_X, 1.0), "left stick X maps to move right")
	_check(_has_joypad_axis(&"move_forward", JOY_AXIS_LEFT_Y, -1.0), "left stick Y maps to move forward")
	_check(_has_joypad_axis(&"move_back", JOY_AXIS_LEFT_Y, 1.0), "left stick Y maps to move back")
	_check(_has_joypad_axis(&"look_left", JOY_AXIS_RIGHT_X, -1.0), "right stick X maps to camera left")
	_check(_has_joypad_axis(&"look_right", JOY_AXIS_RIGHT_X, 1.0), "right stick X maps to camera right")
	_check(_has_joypad_axis(&"look_up", JOY_AXIS_RIGHT_Y, -1.0), "right stick Y maps to camera up")
	_check(_has_joypad_axis(&"look_down", JOY_AXIS_RIGHT_Y, 1.0), "right stick Y maps to camera down")
	_check(_has_joypad_button(&"jump", JOY_BUTTON_A), "A/Cross button maps to jump")
	_check(_has_joypad_button(&"interact", JOY_BUTTON_B), "B/Circle button maps to interaction")
	_check(_has_joypad_button(&"attack", JOY_BUTTON_X), "X/Square button maps to attack")
	_check(_has_joypad_axis(&"attack", JOY_AXIS_TRIGGER_RIGHT, 1.0), "RT/R2 trigger maps to attack")
	_check(_has_joypad_button(&"inventory", JOY_BUTTON_Y), "Y/Triangle button maps to inventory")
	_check(_has_joypad_button(&"sprint", JOY_BUTTON_LEFT_STICK), "left stick press maps to sprint")
	_check(_has_joypad_button(&"pause", JOY_BUTTON_START), "Start button maps to pause menu")
	_check(_has_joypad_button(&"ui_accept", JOY_BUTTON_A), "A/Cross activates the focused UI control")
	_check(_has_joypad_button(&"ui_cancel", JOY_BUTTON_B), "B/Circle cancels focused UI navigation")
	_check(_has_joypad_button(&"ui_up", JOY_BUTTON_DPAD_UP), "D-pad up navigates focused UI")
	_check(_has_joypad_button(&"ui_down", JOY_BUTTON_DPAD_DOWN), "D-pad down navigates focused UI")
	_check(_has_joypad_button(&"ui_left", JOY_BUTTON_DPAD_LEFT), "D-pad left navigates focused UI")
	_check(_has_joypad_button(&"ui_right", JOY_BUTTON_DPAD_RIGHT), "D-pad right navigates focused UI")
	_check(_has_joypad_axis(&"ui_left", JOY_AXIS_LEFT_X, -1.0), "left stick X navigates focused UI left")
	_check(_has_joypad_axis(&"ui_right", JOY_AXIS_LEFT_X, 1.0), "left stick X navigates focused UI right")
	_check(_has_joypad_axis(&"ui_up", JOY_AXIS_LEFT_Y, -1.0), "left stick Y navigates focused UI up")
	_check(_has_joypad_axis(&"ui_down", JOY_AXIS_LEFT_Y, 1.0), "left stick Y navigates focused UI down")


func _test_analog_movement_magnitude() -> void:
	var player := CharacterBody3D.new()
	player.set_script(PlayerScript)

	var partial_direction: Vector3 = player.call("_movement_direction", Vector2(0.35, 0.0))
	_check(
		is_equal_approx(partial_direction.length(), 0.35),
		"single-player movement preserves partial analog stick magnitude"
	)

	var full_direction: Vector3 = player.call("_movement_direction", Vector2(0.0, -1.0))
	_check(
		is_equal_approx(full_direction.length(), 1.0),
		"full analog stick movement reaches full speed"
	)

	var diagonal_direction: Vector3 = player.call("_movement_direction", Vector2(1.0, -1.0))
	_check(
		is_equal_approx(diagonal_direction.length(), 1.0),
		"diagonal input is clamped to prevent faster movement"
	)

	var neutral_direction: Vector3 = player.call("_movement_direction", Vector2.ZERO)
	_check(
		is_zero_approx(neutral_direction.length()),
		"neutral analog stick input produces no movement"
	)
	player.free()


func _test_controller_navigation_configuration() -> void:
	var menu_file := FileAccess.open("res://scripts/ui/main_menu.gd", FileAccess.READ)
	_check(menu_file != null, "main menu source is readable for controller navigation checks")
	if menu_file != null:
		var menu_source := menu_file.get_as_text()
		menu_file.close()
		_check(menu_source.contains("_solo_button.grab_focus()"), "main menu focuses the initial game action")
		_check(menu_source.contains("_set_mouse_visible_for_menu()"), "main menu restores a visible mouse cursor after scene transitions")
		_check(menu_source.contains("Input.MOUSE_MODE_VISIBLE"), "main menu uses a visible cursor on desktop")
		_check(menu_source.contains("_focus_default_control"), "main menu defers focus until layout is ready")
		_check(menu_source.contains("INPUT_SETUP_SCRIPT.register_input_actions()"), "main menu registers inputs before opening solo or network play")
		_check(menu_source.contains("العصا اليسرى للحركة"), "main menu displays controller instructions")

	var hud_file := FileAccess.open("res://scripts/ui/hud.gd", FileAccess.READ)
	_check(hud_file != null, "HUD source is readable for controller navigation checks")
	if hud_file != null:
		var hud_source := hud_file.get_as_text()
		hud_file.close()
		_check(hud_source.contains("_focus_resume_button"), "pause overlay focuses resume action")
		_check(hud_source.contains("_focus_inventory_default"), "inventory overlay focuses an actionable control")
		_check(hud_source.contains('event.is_action_pressed("ui_cancel")'), "controller cancel action is handled by the HUD")
		_check(hud_source.contains("_set_paused(false)"), "controller cancel can close the pause overlay")
		_check(hud_source.contains("_set_inventory_visible(false)"), "controller cancel can close the inventory overlay")
		_check(hud_source.contains("Start"), "HUD includes the controller pause hint")

	var camera_file := FileAccess.open("res://scripts/player/player_camera.gd", FileAccess.READ)
	_check(camera_file != null, "camera source is readable for controller look checks")
	if camera_file != null:
		var camera_source := camera_file.get_as_text()
		camera_file.close()
		_check(camera_source.contains("look_left"), "camera reads right-stick input actions")
		_check(camera_source.contains("InputEventScreenDrag"), "single-player camera handles touch drag")
		_check(camera_source.contains("touch_sensitivity"), "touch camera sensitivity is applied")
		_check(camera_source.contains("drag.screen_relative"), "touch camera uses resolution-independent screen deltas")

	var dialogue_file := FileAccess.open("res://scripts/ui/dialogue_ui.gd", FileAccess.READ)
	_check(dialogue_file != null, "dialogue UI source is readable for controller focus checks")
	if dialogue_file != null:
		var dialogue_source := dialogue_file.get_as_text()
		dialogue_file.close()
		_check(dialogue_source.contains("_focus_first_choice"), "dialogue focuses the first choice for controller selection")
		_check(dialogue_source.contains("Control.FOCUS_ALL"), "dialogue choice buttons are focusable")

	var arena_file := FileAccess.open("res://scripts/networking/multiplayer_arena.gd", FileAccess.READ)
	_check(arena_file != null, "network arena source is readable for pause-menu checks")
	if arena_file != null:
		var arena_source := arena_file.get_as_text()
		arena_file.close()
		_check(arena_source.contains("_build_pause_menu"), "network arena builds a controller-accessible pause menu")
		_check(arena_source.contains("_set_pause_menu_open"), "network pause menu has an explicit open/close state")
		_check(arena_source.contains("set_local_input_enabled"), "network pause menu gates local player input")
		_check(arena_source.contains("_set_mouse_mode_for_pause_menu"), "network pause menu manages mouse visibility")
		_check(arena_source.contains("_mouse_mode_before_pause = Input.mouse_mode"), "network pause menu stores prior mouse mode")
		_check(arena_source.contains("Input.mouse_mode = Input.MOUSE_MODE_VISIBLE"), "network pause menu shows cursor for pointer interaction")
		_check(arena_source.contains("Input.mouse_mode = Input.MOUSE_MODE_VISIBLE"), "return to menu restores desktop mouse visibility")

	var network_file := FileAccess.open("res://scripts/networking/network_avatar.gd", FileAccess.READ)
	_check(network_file != null, "network avatar source is readable for controller look checks")
	if network_file != null:
		var network_source := network_file.get_as_text()
		network_file.close()
		_check(network_source.contains('Input.get_vector("look_left"'), "network camera reads right-stick input actions")
		_check(
			network_source.contains('@rpc("any_peer", "call_remote", "unreliable_ordered")'),
			"network movement RPC drops out-of-order stale input packets"
		)
		_check(network_source.contains("drag.screen_relative"), "network touch look uses resolution-independent screen deltas")
		var input_handler_start := network_source.find("func _unhandled_input(event: InputEvent) -> void:")
		var input_handler_end := network_source.find("func _apply_camera_rotation", input_handler_start)
		_check(input_handler_start >= 0 and input_handler_end > input_handler_start, "network avatar camera input handler is present")
		if input_handler_start >= 0 and input_handler_end > input_handler_start:
			var input_handler_source := network_source.substr(input_handler_start, input_handler_end - input_handler_start)
			_check(input_handler_source.contains("not _local_input_enabled"), "network camera input is disabled while pause menu is open")


func _has_joypad_button(action: StringName, expected_button: int) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			if (event as InputEventJoypadButton).button_index == expected_button:
				return true
	return false


func _has_joypad_axis(action: StringName, expected_axis: int, expected_value: float) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion:
			var axis_event := event as InputEventJoypadMotion
			if axis_event.axis == expected_axis and is_equal_approx(axis_event.axis_value, expected_value):
				return true
	return false


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
