extends SceneTree

const MAIN_SCRIPT: Script = preload("res://scripts/core/main.gd")
const PLAYER_SCRIPT: Script = preload("res://scripts/player/player.gd")
const HEALTH_SCRIPT: Script = preload("res://scripts/components/health.gd")
const INVENTORY_SCRIPT: Script = preload("res://scripts/components/inventory.gd")
const PLAYER_MODEL_PATH: String = "res://assets/characters/player/player.glb"

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_model_loader_and_placeholder()
	_test_player_without_animations()
	_test_player_animation_aliases()
	print("[player-smoke] failures: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _test_model_loader_and_placeholder() -> void:
	var main_node := Node3D.new()
	main_node.set_script(MAIN_SCRIPT)
	var body := CharacterBody3D.new()

	var loaded_model := bool(main_node.call("_add_player_model_or_placeholder", body))
	if ResourceLoader.exists(PLAYER_MODEL_PATH):
		_check(loaded_model, "present player.glb loads as a PackedScene")
	else:
		_check(not loaded_model, "missing player.glb selects the documented placeholder path")

	if not loaded_model:
		main_node.call("_add_hero_fallback_visual", body)
		_check(body.get_node_or_null("CollisionShape3D") != null, "fallback keeps independent player collision")
		_check(body.get_node_or_null("HeroFallbackVisual") != null, "fallback creates a separate visual root")
		_check(body.get_node_or_null("HeroFallbackVisual/ChestArmor") != null, "fallback includes a visible chest armor mesh")
	else:
		_check(body.get_node_or_null("CollisionShape3D") != null, "GLB player keeps independent capsule collision")
		_check(body.get_node_or_null("PlayerVisual/GeneratedPlayerModel") != null, "GLB is attached below PlayerVisual")

	body.free()
	main_node.free()


func _test_player_without_animations() -> void:
	var player := _make_player()
	root.add_child(player)

	_check(player.get("_animation_player") == null, "player tolerates missing AnimationPlayer")

	var slow_direction: Vector3 = player.call("_movement_direction", Vector2(0.25, 0.0))
	_check(is_equal_approx(slow_direction.x, 0.25), "analog movement preserves partial stick magnitude")
	_check(is_equal_approx(slow_direction.length(), 0.25), "analog movement allows controlled slow walking")

	var oversized_direction: Vector3 = player.call("_movement_direction", Vector2(1.0, 1.0))
	_check(is_equal_approx(oversized_direction.length(), 1.0), "diagonal input is clamped to unit movement speed")

	player.call("_play_animation", &"idle")
	player.call("_update_animation", Vector3.ZERO)
	_check(true, "missing animation clips do not block idle update")

	var health := player.get_node("Health")
	health.call("take_damage", 1000.0)
	_check(bool(player.get("is_dead")), "player death state still works without animations")
	player.call("reset_after_death", Vector3.ZERO)
	_check(not bool(player.get("is_dead")), "player can respawn without animations")

	player.free()


func _test_player_animation_aliases() -> void:
	var player := _make_player()
	var visual := Node3D.new()
	visual.name = "PlayerVisual"
	var animation_player := AnimationPlayer.new()
	animation_player.name = "AnimationPlayer"
	var library := AnimationLibrary.new()
	var clip_names: Array[String] = [
		"Idle_01", "Walking", "Running", "Jump", "HeavyAttack", "Death"
	]
	for clip_name in clip_names:
		var result := library.add_animation(clip_name, Animation.new())
		_check(result == OK, "test animation clip added: %s" % clip_name)
	animation_player.add_animation_library("mock", library)
	visual.add_child(animation_player)
	player.add_child(visual)
	root.add_child(player)

	var resolved: Dictionary = player.get("_resolved_animations")
	_check(String(resolved.get("idle", "")).contains("Idle_01"), "idle alias resolves")
	_check(String(resolved.get("walk", "")).contains("Walking"), "walk alias resolves")
	_check(String(resolved.get("run", "")).contains("Running"), "run alias resolves")
	_check(String(resolved.get("jump", "")).contains("Jump"), "jump alias resolves")
	_check(String(resolved.get("attack", "")).contains("HeavyAttack"), "attack alias resolves")
	_check(String(resolved.get("death", "")).contains("Death"), "death alias resolves")
	_check(not animation_player.current_animation.is_empty(), "idle clip starts when available")

	player.free()


func _make_player() -> CharacterBody3D:
	var player := CharacterBody3D.new()
	player.name = "PlayerSmokeTest"
	player.set_script(PLAYER_SCRIPT)

	var health := Node.new()
	health.name = "Health"
	health.set_script(HEALTH_SCRIPT)
	player.add_child(health)

	var inventory := Node.new()
	inventory.name = "Inventory"
	inventory.set_script(INVENTORY_SCRIPT)
	player.add_child(inventory)
	return player


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
