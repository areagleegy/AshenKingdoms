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
	_check(not bool(avatar.call("_is_valid_input_direction", Vector3(NAN, 0.0, 0.0))), "network input rejects NaN direction components")
	_check(not bool(avatar.call("_is_valid_input_direction", Vector3(INF, 0.0, 0.0))), "network input rejects infinite direction components")
	_check(not bool(avatar.call("_is_valid_input_direction", Vector3(2.0, 0.0, 0.0))), "network input rejects magnitudes above the allowed range")
	_check(not bool(avatar.call("_is_valid_input_direction", Vector3(0.0, 1.0, 0.0))), "network input rejects vertical movement components")
	_check(bool(avatar.call("_is_valid_input_direction", Vector3(0.6, 0.0, 0.8))), "network input accepts finite normalized world directions")

	var network_manager := get_node_or_null("/root/NetworkManager")
	_check(network_manager != null, "network manager is available for RPC rate-limit checks")
	if network_manager != null:
		_check(bool(network_manager.call("_accept_rpc_rate_limit_at", 987654, &"test_input", 50, 1000)), "first request in a peer rate-limit window is accepted")
		_check(not bool(network_manager.call("_accept_rpc_rate_limit_at", 987654, &"test_input", 50, 1020)), "requests inside a peer rate-limit window are rejected")
		_check(bool(network_manager.call("_accept_rpc_rate_limit_at", 987654, &"test_input", 50, 1050)), "request is accepted at the rate-limit boundary")
		_check(bool(network_manager.call("_accept_rpc_rate_limit_at", 987655, &"test_input", 50, 1020)), "rate limits are isolated per peer")
		_check(not bool(network_manager.call("accept_rpc_rate_limit", 987654, &"unconnected_peer", 50)), "live RPC rate limiter rejects unconnected peers")
		network_manager.call("_clear_peer_rpc_rate_limits", 987654)
		_check(bool(network_manager.call("_accept_rpc_rate_limit_at", 987654, &"test_input", 50, 1020)), "disconnect cleanup clears a peer's rate-limit state")

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

	avatar.set("current_health", 0.0)
	avatar.global_position = Vector3(50.0, 50.0, 50.0)
	avatar.call("_server_begin_respawn")
	var stale_generation := int(avatar.get("_death_generation"))
	avatar.call("_server_begin_respawn")
	var current_generation := int(avatar.get("_death_generation"))
	avatar.call("_server_respawn", stale_generation)
	_check(bool(avatar.get("is_dead")), "stale respawn generation cannot revive a newer death state")
	avatar.call("_server_respawn", current_generation)
	_check(not bool(avatar.get("is_dead")), "current respawn generation restores the player")
	_check(is_equal_approx(float(avatar.get("current_health")), float(avatar.get("max_health"))), "respawn restores authoritative health")
	_check((avatar.global_position - Vector3.ZERO).length() < 2.0, "respawn returns the host avatar to its spawn point")

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


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
