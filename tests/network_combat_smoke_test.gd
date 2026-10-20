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
	_check(
		NetworkManager.start_websocket_client("localhost:7778") == ERR_INVALID_PARAMETER,
		"WebSocket client rejects endpoints without an explicit ws:// or wss:// scheme"
	)

	var input_probe := NetworkAvatarScene.instantiate() as CharacterBody3D
	input_probe.call("configure_owner", 2)
	add_child(input_probe)
	input_probe.global_position = Vector3(1000.0, 0.92, 1000.0)
	var input_test_time := Time.get_ticks_msec() + 100
	_check(
		not bool(input_probe.call("_accept_remote_input", 3, Vector3.ZERO, false, false, false, input_test_time)),
		"network input rejects a sender that does not own the avatar"
	)
	_check(
		not bool(input_probe.call("_accept_remote_input", 2, Vector3(INF, 0.0, 0.0), false, false, false, input_test_time)),
		"network input rejects non-finite direction values"
	)
	_check(
		not bool(input_probe.call("_accept_remote_input", 2, Vector3(0.0, 1.0, 0.0), false, false, false, input_test_time)),
		"network input rejects vertical movement components"
	)
	_check(
		not bool(input_probe.call("_accept_remote_input", 2, Vector3(1.5, 0.0, 0.0), false, false, false, input_test_time)),
		"network input rejects over-range direction vectors"
	)
	_check(
		bool(input_probe.call("_accept_remote_input", 2, Vector3(0.0, 0.0, -1.0), false, false, false, input_test_time)),
		"network input accepts valid bounded input from its owner"
	)
	_check(
		not bool(input_probe.call("_accept_remote_input", 2, Vector3.ZERO, false, false, false, input_test_time + 10)),
		"network input rejects samples inside the 20 ms rate-limit window"
	)
	_check(
		bool(input_probe.call("_accept_remote_input", 2, Vector3.ZERO, false, false, false, input_test_time + 20)),
		"network input accepts a new sample after the rate-limit window"
	)
	input_probe.queue_free()

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

	var rival := NetworkAvatarScene.instantiate() as CharacterBody3D
	if rival == null or not rival.has_method("configure_owner"):
		_check(false, "second network avatar scene loads for PvP testing")
		get_tree().quit(1)
		return
	rival.name = "PvPRival"
	rival.call("configure_owner", 2)
	rival.call("configure_battle_royale", true)
	add_child(rival)
	rival.global_position = avatar.global_position - avatar.global_transform.basis.z * 1.5
	avatar.set("_next_attack_msec", 0)
	print("[network-smoke] PvP test distance: %.2f" % avatar.global_position.distance_to(rival.global_position))
	avatar.call("_server_try_attack")
	_check(is_equal_approx(float(rival.get("current_health")), 80.0), "server attack damages an enemy player in range and in front")
	rival.call("apply_damage_from_server", 999.0, 1)
	_check(bool(rival.get("is_dead")), "lethal PvP damage eliminates the rival")
	await get_tree().create_timer(2.1).timeout
	_check(bool(rival.get("is_dead")), "battle royale elimination does not respawn after the normal respawn delay")
	rival.queue_free()

	print("[network-smoke] failures: %d" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
