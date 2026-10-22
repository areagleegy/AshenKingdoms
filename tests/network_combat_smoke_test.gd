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
	avatar.set_physics_process(false)
	print("[network-smoke] avatar ready")
	_check(float(avatar.get("current_health")) == 100.0, "network avatar starts with expected health")
	_check(bool(multiplayer.is_server()), "offline smoke harness is allowed to exercise server logic")

	# Test the exact rolling-window policy with controlled timestamps instead
	# of relying on frame scheduling in the remote ENet integration harness.
	var rate_window_start := 100000
	avatar.set("_input_rate_window_start_msec", rate_window_start)
	avatar.set("_input_rate_window_count", 40)
	avatar.set("_last_input_packet_msec", rate_window_start + 100)
	_check(
		str(avatar.call("_input_rate_rejection_reason", rate_window_start + 200)) == "rate_window",
		"input RPC rate guard rejects packets after forty accepted requests in one window"
	)

	avatar.set("_input_rate_window_start_msec", rate_window_start)
	avatar.set("_input_rate_window_count", 0)
	avatar.set("_last_input_packet_msec", rate_window_start + 100)
	_check(
		str(avatar.call("_input_rate_rejection_reason", rate_window_start + 110)) == "min_interval",
		"input RPC rate guard rejects packets inside the minimum interval"
	)

	avatar.set("_input_rate_window_start_msec", rate_window_start)
	avatar.set("_input_rate_window_count", 40)
	avatar.set("_last_input_packet_msec", rate_window_start + 900)
	var reset_window_reason := str(avatar.call("_input_rate_rejection_reason", rate_window_start + 1000))
	_check(
		reset_window_reason.is_empty() and int(avatar.get("_input_rate_window_count")) == 1,
		"input RPC rate window resets after one second and accepts the next packet"
	)

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
	enemy.died.connect(func(_dead_enemy: Node, _attacker_peer_id: int) -> void:
		avatar.call("register_enemy_defeat")
	)
	avatar.call("_server_try_attack")
	_check(is_equal_approx(float(enemy.get("current_health")), 65.0), "server attack damages an enemy within range and in front")
	avatar.call("_server_try_attack")
	_check(is_equal_approx(float(enemy.get("current_health")), 65.0), "server attack cooldown rejects an immediate repeat")

	await get_tree().create_timer(0.7).timeout
	enemy.global_position = avatar.global_position + Vector3(0.0, 0.0, -4.0)
	avatar.call("_server_try_attack")
	_check(is_equal_approx(float(enemy.get("current_health")), 65.0), "server attack rejects an enemy outside attack range")

	await get_tree().create_timer(0.7).timeout
	enemy.global_position = avatar.global_position + Vector3(0.0, 0.0, 2.0)
	avatar.call("_server_try_attack")
	_check(is_equal_approx(float(enemy.get("current_health")), 65.0), "server attack rejects an enemy behind the avatar")

	enemy.global_position = avatar.global_position + Vector3(0.0, 0.0, -2.0)
	await get_tree().create_timer(0.7).timeout
	var total_xp_before_death := _total_experience(avatar)
	enemy.call("apply_damage_from_server", 999.0, 1)
	print("[network-smoke] lethal hit applied")
	_check(bool(enemy.get("is_dead")), "lethal server damage marks the enemy dead")
	_check(float(enemy.get("current_health")) == 0.0, "enemy health is clamped at zero")
	_check(int(death_event["count"]) == 1 and int(death_event["attacker"]) == 1, "enemy death emits one attacker event")
	_check(
		_total_experience(avatar) - total_xp_before_death == 35,
		"one enemy death grants exactly one standard XP reward"
	)
	var level_after_death := int(avatar.get("level"))
	var xp_after_death := int(avatar.get("experience"))
	var quest_after_death := int(avatar.get("quest_progress"))
	enemy.call("apply_damage_from_server", 999.0, 1)
	_check(int(death_event["count"]) == 1, "repeated lethal damage cannot emit a duplicate death event")
	_check(
		int(avatar.get("level")) == level_after_death
		and int(avatar.get("experience")) == xp_after_death
		and int(avatar.get("quest_progress")) == quest_after_death,
		"repeated lethal damage cannot grant duplicate XP or quest progress"
	)

	var player_max_health := float(avatar.get("max_health"))
	avatar.call("apply_damage_from_server", player_max_health + 1.0, 2)
	var death_generation := int(avatar.get("_death_generation"))
	_check(
		bool(avatar.get("is_dead")) and is_equal_approx(float(avatar.get("current_health")), 0.0),
		"lethal server damage marks the player dead at zero health"
	)
	avatar.call("_server_respawn", death_generation - 1)
	_check(
		bool(avatar.get("is_dead")) and is_equal_approx(float(avatar.get("current_health")), 0.0),
		"stale respawn generation cannot revive a dead player"
	)
	await get_tree().create_timer(2.1).timeout
	_check(
		not bool(avatar.get("is_dead")) and is_equal_approx(float(avatar.get("current_health")), player_max_health),
		"player respawns at full health after the current death timer"
	)

	print("[network-smoke] failures: %d" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _total_experience(avatar: Node) -> int:
	var total := int(avatar.get("experience"))
	var current_level := int(avatar.get("level"))
	for level_index in range(1, current_level):
		total += 100 + ((level_index - 1) * 50)
	return total


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
