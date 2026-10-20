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
	avatar.call("apply_damage_from_server", NAN, 0)
	_check(float(avatar.get("current_health")) == 100.0, "NaN damage cannot corrupt player health")
	avatar.call("apply_damage_from_server", INF, 0)
	_check(float(avatar.get("current_health")) == 100.0, "infinite damage is rejected")
	avatar.call("apply_damage_from_server", -1.0, 0)
	_check(float(avatar.get("current_health")) == 100.0, "negative damage is rejected")
	_check(bool(avatar.call("_is_valid_input_direction", Vector3(0.5, 0.0, -0.5))), "finite movement input is accepted")
	_check(not bool(avatar.call("_is_valid_input_direction", Vector3(NAN, 0.0, 0.0))), "NaN movement input is rejected")
	_check(not bool(avatar.call("_is_valid_input_direction", Vector3(0.0, 0.0, INF))), "infinite movement input is rejected")
	_check(not bool(avatar.call("_is_valid_input_direction", Vector3(100.0, 0.0, 0.0))), "out-of-range movement input is rejected")
	avatar.call("configure_owner", 2)
	_check(bool(avatar.call("_is_authorized_input_sender", 2)), "the owning remote peer is authorized to submit input")
	_check(not bool(avatar.call("_is_authorized_input_sender", 3)), "a different peer cannot submit input for this avatar")
	_check(not bool(avatar.call("_is_authorized_input_sender", 1)), "the server peer ID cannot impersonate a remote owner")
	_check(bool(avatar.call("_accept_input_timestamp", 1000)), "first movement input timestamp is accepted")
	_check(not bool(avatar.call("_accept_input_timestamp", 1019)), "movement input inside the 20 ms limit is rejected")
	_check(bool(avatar.call("_accept_input_timestamp", 1020)), "movement input at the 20 ms boundary is accepted")
	_check(bool(avatar.call("_accept_input_timestamp", 1070)), "normal 50 ms client cadence is accepted")

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
	enemy.call("apply_damage_from_server", NAN, 1)
	_check(float(enemy.get("current_health")) == 85.0, "NaN damage cannot corrupt enemy health")
	enemy.call("apply_damage_from_server", INF, 1)
	_check(float(enemy.get("current_health")) == 85.0, "infinite enemy damage is rejected")
	enemy.call("apply_damage_from_server", -1.0, 1)
	_check(float(enemy.get("current_health")) == 85.0, "negative enemy damage is rejected")
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
