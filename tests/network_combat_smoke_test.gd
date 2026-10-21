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

	var input_avatar := NetworkAvatarScene.instantiate() as CharacterBody3D
	input_avatar.call("configure_owner", 2)
	add_child(input_avatar)
	_check(bool(input_avatar.call("_accept_input_packet", 2, Vector3(0.5, 0.0, 0.5), 1000)), "network input accepts a finite packet from its owning peer")
	_check(not bool(input_avatar.call("_accept_input_packet", 2, Vector3.ZERO, 1010)), "network input rate limit rejects an early repeated packet")
	_check(bool(input_avatar.call("_accept_input_packet", 2, Vector3.ZERO, 1020)), "network input accepts the next packet after the minimum interval")
	_check(not bool(input_avatar.call("_accept_input_packet", 3, Vector3.ZERO, 1040)), "network input rejects a packet from a non-owning peer")
	_check(not bool(input_avatar.call("_accept_input_packet", 2, Vector3(NAN, 0.0, 0.0), 1040)), "network input rejects non-finite direction values")
	_check(not bool(input_avatar.call("_accept_input_packet", 2, Vector3(0.0, INF, 0.0), 1040)), "network input rejects infinite direction values")
	input_avatar.queue_free()

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


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
