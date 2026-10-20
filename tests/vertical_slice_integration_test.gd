extends SceneTree

const MENU_PATH: String = "res://scenes/ui/MainMenu.tscn"
const GAME_PATH: String = "res://scenes/boot/Main.tscn"
const SAVE_PATH: String = "user://savegame.json"
const CYCLE_COUNT: int = 3

var _failures: int = 0
var _completed_cycles: int = 0
var _had_original_save: bool = false
var _original_save: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_had_original_save = FileAccess.file_exists(SAVE_PATH)
	if _had_original_save:
		var original_file := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if original_file == null:
			push_error("Could not back up existing save before the vertical-slice test.")
			quit(1)
			return
		_original_save = original_file.get_as_text()
		original_file.close()

	for cycle_number in range(1, CYCLE_COUNT + 1):
		var cycle_ok: bool = await _run_cycle(cycle_number)
		if not cycle_ok:
			break
		_completed_cycles += 1

	_reset_dialogue_state()
	_restore_original_save()
	print("[vertical-slice] completed cycles: %d/%d; failures: %d" % [
		_completed_cycles, CYCLE_COUNT, _failures
	])
	quit(1 if _failures > 0 or _completed_cycles != CYCLE_COUNT else 0)


func _run_cycle(cycle_number: int) -> bool:
	print("[vertical-slice] starting cycle %d/%d" % [cycle_number, CYCLE_COUNT])
	_reset_dialogue_state()

	if not await _open_menu():
		return false
	if not await _start_solo_from_menu():
		return false

	var game: Node = current_scene
	if not _check(game != null and game.has_method("_save_game"), "solo menu opens the real Main scene"):
		return false

	var world := game.get("world") as Node3D
	var player := game.get("player") as CharacterBody3D
	var progression: Node = game.get("progression")
	var quests: Node = game.get("quests")
	var enemies := game.get("enemies_container") as Node3D
	if not _check(
		world != null and player != null and progression != null and quests != null and enemies != null,
		"world, player, progression, quest manager, and enemies are initialized"
	):
		return false

	if not await _test_movement(player):
		return false
	if not _test_npc_dialogue_and_quest_start(game, world, quests):
		return false
	if not await _test_combat_and_reward(game, player, progression, quests, enemies):
		return false
	if not await _test_save_restart_load(player, progression, quests, enemies):
		return false

	print("[vertical-slice] cycle %d passed" % cycle_number)
	return true


func _open_menu() -> bool:
	var result := change_scene_to_file(MENU_PATH)
	if not _check(result == OK, "request MainMenu scene"):
		return false

	for _frame in range(60):
		await process_frame
		if current_scene != null and current_scene.name == "MainMenu":
			return true

	return _check(false, "MainMenu becomes the current scene within 60 frames")


func _start_solo_from_menu() -> bool:
	if current_scene == null or current_scene.name != "MainMenu":
		return _check(false, "MainMenu is available before starting solo mode")

	var solo_button: Button
	for candidate in current_scene.find_children("*", "Button", true, false):
		if candidate is Button and (candidate as Button).text == "اللعب الفردي":
			solo_button = candidate as Button
			break

	if not _check(solo_button != null, "MainMenu exposes the real solo-play button"):
		return false

	solo_button.emit_signal("pressed")
	for _frame in range(60):
		await process_frame
		if current_scene != null and current_scene.has_method("_save_game"):
			await process_frame
			return true

	return _check(false, "solo-play button enters Main.tscn within 60 frames")


func _test_movement(player: CharacterBody3D) -> bool:
	var start_position := player.global_position
	Input.action_press(&"move_right")
	await _wait_physics_frames(18)
	Input.action_release(&"move_right")
	await _wait_physics_frames(2)

	var end_position := player.global_position
	var horizontal_delta := Vector2(
		end_position.x - start_position.x,
		end_position.z - start_position.z
	).length()
	if not _check(horizontal_delta > 0.15, "player responds to a real InputMap movement action"):
		return false

	player.velocity = Vector3.ZERO
	player.global_position = Vector3(0.0, 0.92, 0.0)
	player.rotation = Vector3.ZERO
	await _wait_physics_frames(2)
	return true


func _test_npc_dialogue_and_quest_start(game: Node, world: Node3D, quests: Node) -> bool:
	var npc := world.get_node_or_null("WanderingElder")
	var dialogue_manager: Node = root.get_node_or_null("DialogueManager")
	if not _check(npc != null and dialogue_manager != null, "real NPC and DialogueManager are present"):
		return false

	npc.call("interact")
	if not _check(bool(dialogue_manager.call("is_active")), "NPC interaction starts the configured dialogue graph"):
		return false

	dialogue_manager.call("next")
	var current_node = dialogue_manager.get("_current")
	if not _check(current_node != null and StringName(current_node.get("id")) == &"ask", "dialogue advances to the quest offer"):
		return false

	dialogue_manager.call("choose", 0)
	if not _check(
		String(quests.get("quest_id")) == "ash_trail" and bool(quests.get("active")),
		"accepting the NPC choice starts the Ash Trail quest"
	):
		return false
	if not _check(
		bool(dialogue_manager.call("get_flag", &"quest_accepted"))
		and bool(dialogue_manager.call("get_flag", &"met_elder")),
		"quest dialogue updates the expected progression flags"
	):
		return false

	dialogue_manager.call("next")
	if not _check(not bool(dialogue_manager.call("is_active")), "dialogue can close without leaving the game paused"):
		return false
	if not _check(not paused, "game tree is unpaused after dialogue completion"):
		return false
	return true


func _test_combat_and_reward(
	game: Node,
	player: CharacterBody3D,
	progression: Node,
	quests: Node,
	enemies: Node3D
) -> bool:
	# Keep enemies still and spread them out so each ray cast has a single target.
	for index in range(enemies.get_child_count()):
		var enemy := enemies.get_child(index)
		enemy.set("player", null)
		enemy.set("velocity", Vector3.ZERO)
		enemy.global_position = Vector3(100.0 + float(index * 5), 0.92, 100.0)

	player.velocity = Vector3.ZERO
	player.global_position = Vector3(0.0, 0.92, 0.0)
	player.rotation = Vector3.ZERO
	player.set("attack_damage", 100.0)
	await _wait_physics_frames(2)

	var target_names: Array[String] = ["AshWraith_01", "AshWraith_02", "AshWraith_03"]
	for index in range(target_names.size()):
		var enemy := enemies.get_node_or_null(target_names[index]) as CharacterBody3D
		if not _check(enemy != null, "expected target exists: %s" % target_names[index]):
			return false

		enemy.set("player", null)
		enemy.set("velocity", Vector3.ZERO)
		enemy.global_position = player.global_position + Vector3(0.0, 0.0, -1.8)
		var health: Node = enemy.get_node_or_null("Health")
		if not _check(health != null, "enemy has a health component"):
			return false
		health.call("set_current_health", 20.0)
		await _wait_physics_frames(2)

		player.call("_attack")
		await create_timer(float(player.get("attack_cooldown")) + 0.15).timeout
		await process_frame

		if not _check(
			int(quests.get("progress")) == index + 1,
			"combat defeat advances quest progress to %d" % (index + 1)
		):
			return false

	if not _check(not bool(quests.get("active")), "three real combat kills complete the quest"):
		return false
	if not _check(
		int(progression.get("level")) >= 2 and int(progression.get("experience")) > 0,
		"enemy XP and quest reward update player progression"
	):
		return false

	var xp_before := int(progression.get("experience"))
	var level_before := int(progression.get("level"))
	quests.call("on_enemy_defeated", &"ash_wraith")
	if not _check(
		int(progression.get("experience")) == xp_before and int(progression.get("level")) == level_before,
		"completed quest does not grant its reward a second time"
	):
		return false

	return true


func _test_save_restart_load(
	player: CharacterBody3D,
	progression: Node,
	quests: Node,
	enemies: Node3D
) -> bool:
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(1.5, 0.92, 2.5)
	var health: Node = player.get_node("Health")
	health.call("set_current_health", 63.0)

	var inventory: Node = player.get_node("Inventory")
	var expected_inventory: Array = inventory.call("to_save_data")
	var expected_level := int(progression.get("level"))
	var expected_experience := int(progression.get("experience"))
	var expected_quest_progress := int(quests.get("progress"))
	var expected_position := player.global_position

	current_scene.call("_save_game")
	var save_system: Node = current_scene.get("save_system")
	var saved_data = save_system.call("load_game")
	if not _check(saved_data is Dictionary and not saved_data.is_empty(), "gameplay save writes a readable JSON dictionary"):
		return false

	var saved_quest: Dictionary = saved_data.get("quest", {})
	var saved_dialogue: Dictionary = saved_data.get("dialogue", {})
	var saved_flags: Dictionary = saved_dialogue.get("flags", {})
	if not _check(
		int(saved_quest.get("progress", -1)) == 3 and not bool(saved_quest.get("active", true)),
		"saved quest state records completion and final progress"
	):
		return false
	if not _check(
		bool(saved_flags.get("quest_accepted", false)) and bool(saved_flags.get("met_elder", false)),
		"saved dialogue state retains NPC progression flags"
	):
		return false

	# Rebuild the real menu and gameplay scene to approximate an application restart.
	_reset_dialogue_state()
	if not await _open_menu():
		return false
	if not await _start_solo_from_menu():
		return false

	var reloaded_game: Node = current_scene
	var reloaded_player := reloaded_game.get("player") as CharacterBody3D
	var reloaded_progression: Node = reloaded_game.get("progression")
	var reloaded_quests: Node = reloaded_game.get("quests")
	if not _check(
		reloaded_player != null and reloaded_progression != null and reloaded_quests != null,
		"fresh gameplay scene initializes before loading the saved state"
	):
		return false

	reloaded_game.call("_load_game")
	await process_frame

	if not _check(
		int(reloaded_progression.get("level")) == expected_level
		and int(reloaded_progression.get("experience")) == expected_experience,
		"load restores the same level and experience"
	):
		return false
	if not _check(
		int(reloaded_quests.get("progress")) == expected_quest_progress
		and not bool(reloaded_quests.get("active")),
		"load restores completed quest state"
	):
		return false
	if not _check(
		(reloaded_player.global_position - expected_position).length() < 0.25,
		"load restores the saved player position"
	):
		return false

	var reloaded_health: Node = reloaded_player.get_node("Health")
	if not _check(
		is_equal_approx(float(reloaded_health.get("current")), 63.0),
		"load restores player health"
	):
		return false
	var reloaded_inventory: Node = reloaded_player.get_node("Inventory")
	if not _check(
		reloaded_inventory.call("to_save_data") == expected_inventory,
		"load restores the same inventory data"
	):
		return false

	var dialogue_manager: Node = root.get_node("DialogueManager")
	if not _check(
		bool(dialogue_manager.call("get_flag", &"quest_accepted"))
		and bool(dialogue_manager.call("get_flag", &"met_elder")),
		"load restores NPC dialogue flags"
	):
		return false

	var xp_before := int(reloaded_progression.get("experience"))
	var level_before := int(reloaded_progression.get("level"))
	reloaded_quests.call("on_enemy_defeated", &"ash_wraith")
	if not _check(
		int(reloaded_progression.get("experience")) == xp_before
		and int(reloaded_progression.get("level")) == level_before,
		"loading a completed quest does not duplicate its reward"
	):
		return false

	return true


func _wait_physics_frames(count: int) -> void:
	for _frame in range(count):
		await physics_frame


func _reset_dialogue_state() -> void:
	var dialogue_manager: Node = root.get_node_or_null("DialogueManager")
	if dialogue_manager != null:
		if bool(dialogue_manager.call("is_active")):
			dialogue_manager.call("finish")
		dialogue_manager.call("deserialize", {})
	paused = false
	Input.action_release(&"move_right")


func _restore_original_save() -> void:
	if _had_original_save:
		var restore_file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if restore_file == null:
			_check(false, "original save can be restored after end-to-end testing")
			return
		restore_file.store_string(_original_save)
		restore_file.close()
	else:
		if FileAccess.file_exists(SAVE_PATH):
			var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
			_check(error == OK, "temporary save file is removed after end-to-end testing")


func _check(condition: bool, description: String) -> bool:
	if condition:
		print("[PASS] %s" % description)
		return true
	_failures += 1
	push_error("[FAIL] %s" % description)
	return false
