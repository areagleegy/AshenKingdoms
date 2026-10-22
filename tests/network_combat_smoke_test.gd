extends Node3D

const NetworkAvatarScene: PackedScene = preload("res://scenes/network/NetworkAvatar.tscn")
const NetworkEnemyScene: PackedScene = preload("res://scenes/network/NetworkEnemy.tscn")

var _failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[network-smoke] start")
	# Run inside a real Node3D scene tree so 3D physics and multiplayer nodes
	# have their normal viewport/world context in headless CI.
	var avatar := NetworkAvatarScene.instantiate() as CharacterBody3D
	if avatar == null or not avatar.has_method("configure_owner"):
		_check(false, "network avatar scene and script load correctly")
		get_tree().quit(1)
		return
	avatar.call("configure_owner", 1)
	add_child(avatar)
	print("[network-smoke] avatar ready")
	_check(float(avatar.get("current_health")) == 100.0, "network avatar starts with expected health")
	_check(bool(multiplayer.is_server()), "offline smoke harness is allowed to exercise server logic")
	_test_input_direction_validation(avatar)
	_test_input_rate_limit(avatar)
	_test_stale_input_reset(avatar)
	_test_server_authority_guards()

	avatar.call("server_grant_experience", 100)
	print("[network-smoke] XP tested")
	_check(int(avatar.get("level")) == 2, "server-granted XP advances the network avatar")
	_check(float(avatar.get("max_health")) == 110.0, "level-up increases maximum health")

	avatar.call("register_enemy_defeat")
	avatar.call("register_enemy_defeat")
	avatar.call("register_enemy_defeat")
	print("[network-smoke] quest tested")
	_check(int(avatar.get("quest_progress")) == 3, "three enemy defeats advance the network kill quest")
	_check(bool(avatar.get("quest_completed")), "network kill quest completes at its target")
	_check(int(avatar.get("level")) >= 3, "one-time quest reward can advance the player level")
	avatar.call("register_enemy_defeat")
	_check(int(avatar.get("quest_progress")) == 3, "completed network quest progress stays capped")

	var enemy := NetworkEnemyScene.instantiate() as CharacterBody3D
	if enemy == null or not enemy.has_method("configure_spawn"):
		_check(false, "network enemy scene and script load correctly")
		avatar.queue_free()
		get_tree().quit(1)
		return
	enemy.call("configure_spawn", 1)
	add_child(enemy)
	print("[network-smoke] enemy ready")
	enemy.global_position = avatar.global_position + Vector3(0.0, 0.0, -2.0)
	var death_event: Dictionary = {"count": 0, "attacker": 0}
	enemy.died.connect(func(_dead_enemy: Node, attacker_peer_id: int) -> void:
		death_event["count"] = int(death_event["count"]) + 1
		death_event["attacker"] = attacker_peer_id
	)
	avatar.call("_server_try_attack")
	_check(is_equal_approx(float(enemy.get("current_health")), 65.0), "server attack damages an enemy within range and in front")
	avatar.call("_server_try_attack")
	_check(is_equal_approx(float(enemy.get("current_health")), 65.0), "server attack cooldown rejects an immediate repeat")

	enemy.call("apply_damage_from_server", 999.0, 1)
	print("[network-smoke] lethal hit applied")
	_check(bool(enemy.get("is_dead")), "lethal server damage marks the enemy dead")
	_check(float(enemy.get("current_health")) == 0.0, "enemy health is clamped at zero")
	_check(int(death_event["count"]) == 1 and int(death_event["attacker"]) == 1, "enemy death emits one attacker event")

	print("[network-smoke] failures: %d" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _test_input_direction_validation(avatar: Node) -> void:
	_check(
		bool(avatar.call("_is_valid_input_direction", Vector3(0.6, 0.0, 0.8))),
		"input validator accepts finite horizontal movement vectors"
	)
	_check(
		not bool(avatar.call("_is_valid_input_direction", Vector3(NAN, 0.0, 0.0))),
		"input validator rejects NaN movement components"
	)
	_check(
		not bool(avatar.call("_is_valid_input_direction", Vector3(INF, 0.0, 0.0))),
		"input validator rejects infinite movement components"
	)
	_check(
		not bool(avatar.call("_is_valid_input_direction", Vector3(0.0, 0.2, 1.0))),
		"input validator rejects non-horizontal movement"
	)
	_check(
		not bool(avatar.call("_is_valid_input_direction", Vector3(2.0, 0.0, 0.0))),
		"input validator rejects excessive movement components"
	)


func _test_input_rate_limit(avatar: Node) -> void:
	for packet_index in range(5):
		_check(
			bool(avatar.call("_consume_input_rate_token", 1000)),
			"input rate limiter accepts initial burst packet %d" % (packet_index + 1)
		)
	_check(
		not bool(avatar.call("_consume_input_rate_token", 1000)),
		"input rate limiter rejects packets beyond burst budget"
	)
	for packet_index in range(3):
		_check(
			bool(avatar.call("_consume_input_rate_token", 1100)),
			"input rate limiter replenishes tokens over time: %d" % (packet_index + 1)
		)
	_check(
		not bool(avatar.call("_consume_input_rate_token", 1100)),
		"input rate limiter enforces the replenished budget"
	)


func _test_stale_input_reset(avatar: Node) -> void:
	avatar.set("_requested_direction", Vector3(0.5, 0.0, -0.5))
	avatar.set("_sprint_requested", true)
	avatar.set("_jump_buffered", true)
	avatar.set("_attack_requested", true)
	avatar.set("_last_jump_down", true)
	avatar.set("_last_attack_down", true)

	avatar.call("_clear_stale_remote_input")

	var direction_after_reset: Vector3 = avatar.get("_requested_direction")
	_check(direction_after_reset.is_zero_approx(), "stale input reset clears remote movement direction")
	_check(not bool(avatar.get("_sprint_requested")), "stale input reset clears sprint")
	_check(not bool(avatar.get("_jump_buffered")), "stale input reset clears buffered jump")
	_check(not bool(avatar.get("_attack_requested")), "stale input reset clears queued attack")
	_check(not bool(avatar.get("_last_jump_down")), "stale input reset clears jump edge state")
	_check(not bool(avatar.get("_last_attack_down")), "stale input reset clears attack edge state")

	avatar.call("_set_requested_input", Vector3.ZERO, true, false, true)
	_check(bool(avatar.get("_jump_buffered")), "jump is recognized after input resumes")
	_check(bool(avatar.get("_attack_requested")), "attack is recognized after input resumes")


func _test_server_authority_guards() -> void:
	var avatar_file := FileAccess.open("res://scripts/networking/network_avatar.gd", FileAccess.READ)
	_check(avatar_file != null, "network avatar source is available for authority checks")
	if avatar_file != null:
		var avatar_source := avatar_file.get_as_text()
		avatar_file.close()
		_check(
			avatar_source.contains("if sender_id != owner_peer_id or sender_id <= 1 or is_dead:"),
			"movement RPC rejects non-owner, server-id and dead-player senders"
		)
		_check(
			avatar_source.contains("if not _consume_input_rate_token(now):"),
			"movement RPC applies per-avatar rate limiting before input mutation"
		)
		_check(
			avatar_source.contains("func apply_damage_from_server(amount: float, attacker_peer_id: int = 0) -> void:\n\tif not multiplayer.is_server() or amount <= 0.0"),
			"network player damage requires server authority and positive damage"
		)
		_check(
			avatar_source.contains("func register_enemy_defeat() -> void:\n\tif not multiplayer.is_server():"),
			"enemy-defeat progression requires server authority"
		)
		_check(
			avatar_source.contains("func server_grant_experience(amount: int) -> void:\n\tif not multiplayer.is_server() or amount <= 0"),
			"experience grants require server authority and positive amounts"
		)

	var enemy_file := FileAccess.open("res://scripts/networking/network_enemy.gd", FileAccess.READ)
	_check(enemy_file != null, "network enemy source is available for authority checks")
	if enemy_file != null:
		var enemy_source := enemy_file.get_as_text()
		enemy_file.close()
		_check(
			enemy_source.contains("func apply_damage_from_server(amount: float, attacker_peer_id: int) -> void:\n\tif not multiplayer.is_server() or amount <= 0.0"),
		"enemy damage requires server authority and positive damage"
		)
		_check(
			enemy_source.contains("func _physics_process(delta: float) -> void:\n\tif not multiplayer.is_server() or is_dead:"),
		"enemy AI simulation runs only on the server"
		)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
