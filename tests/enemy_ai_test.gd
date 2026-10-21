extends Node3D

const LocalEnemyScript: Script = preload("res://scripts/enemies/enemy.gd")
const HealthScript: Script = preload("res://scripts/components/health.gd")
const AITestTargetScript: Script = preload("res://tests/fixtures/ai_test_target.gd")
const NetworkEnemyScene: PackedScene = preload("res://scenes/network/NetworkEnemy.tscn")
const NetworkAvatarScene: PackedScene = preload("res://scenes/network/NetworkAvatar.tscn")

const AI_IDLE: int = 0
const AI_PATROL: int = 1
const AI_CHASE: int = 2
const AI_ATTACK_WINDUP: int = 3
const AI_ATTACK_COOLDOWN: int = 4
const AI_RETURN_HOME: int = 5
const AI_DEAD: int = 6

var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[enemy-ai] start")
	await _test_local_enemy_behavior()
	await _test_network_enemy_state_machine()
	print("[enemy-ai] checks: %d, failures: %d" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_local_enemy_behavior() -> void:
	var enemy := CharacterBody3D.new()
	enemy.name = "LocalEnemyAITest"
	enemy.set_script(LocalEnemyScript)

	var health := Node.new()
	health.name = "Health"
	health.set_script(HealthScript)
	enemy.add_child(health)
	add_child(enemy)
	enemy.set_physics_process(false)

	var target := Node3D.new()
	target.name = "AITestTarget"
	target.set_script(AITestTargetScript)
	add_child(target)
	await get_tree().process_frame

	_check(enemy.is_in_group("enemies"), "local enemy registers in the enemies group")
	_check(is_equal_approx(float(health.get("current")), float(health.get("max_health"))), "local enemy health initializes")

	enemy.set("player", null)
	enemy.velocity = Vector3(2.0, 0.0, 2.0)
	enemy.set_physics_process(true)
	await get_tree().physics_frame
	enemy.set_physics_process(false)
	_check(is_zero_approx(enemy.velocity.x) and is_zero_approx(enemy.velocity.z), "local enemy stops horizontal motion without a target")

	target.global_position = enemy.global_position + Vector3(0.0, 0.0, -5.0)
	enemy.set("player", target)
	enemy.velocity = Vector3.ZERO
	enemy.set_physics_process(true)
	await get_tree().physics_frame
	enemy.set_physics_process(false)
	_check(enemy.velocity.z < -0.1, "local enemy chases a target inside detection range")
	_check(absf(enemy.velocity.length()) <= float(enemy.get("speed")) + 0.01, "local enemy chase speed stays within its configured limit")

	target.global_position = enemy.global_position + Vector3(0.0, 0.0, -1.0)
	var damage_before := float(target.get("damage_received"))
	enemy.set_physics_process(true)
	await get_tree().physics_frame
	enemy.set_physics_process(false)
	var damage_after := float(target.get("damage_received"))
	_check(damage_after > damage_before, "local enemy damages a target inside attack range")

	enemy.set_physics_process(true)
	await get_tree().physics_frame
	enemy.set_physics_process(false)
	_check(
		is_equal_approx(float(target.get("damage_received")), damage_after),
		"local enemy attack cooldown prevents an immediate repeated hit"
	)

	target.global_position = enemy.global_position + Vector3(0.0, 0.0, -20.0)
	enemy.velocity = Vector3.ZERO
	enemy.set_physics_process(true)
	await get_tree().physics_frame
	enemy.set_physics_process(false)
	_check(absf(enemy.velocity.x) < 0.1 and absf(enemy.velocity.z) < 0.1, "local enemy does not chase a target outside detection range")

	var local_death_events: Array[Node] = []
	enemy.died.connect(func(dead_enemy: Node) -> void: local_death_events.append(dead_enemy))
	enemy.call("take_damage", 9999.0)
	_check(local_death_events.size() == 1, "local enemy emits one death event after lethal damage")
	await get_tree().process_frame
	target.queue_free()


func _test_network_enemy_state_machine() -> void:
	_check(bool(multiplayer.is_server()), "offline test harness can exercise authoritative AI logic")

	var enemy := _make_network_enemy(1)
	var farther_player := _make_network_avatar(2)
	var nearer_player := _make_network_avatar(3)
	await get_tree().process_frame
	enemy.set_physics_process(false)
	farther_player.set_physics_process(false)
	nearer_player.set_physics_process(false)

	farther_player.global_position = enemy.global_position + Vector3(0.0, 0.0, -9.0)
	nearer_player.global_position = enemy.global_position + Vector3(0.0, 0.0, -5.0)
	_check(
		enemy.call("_find_nearest_living_player") == nearer_player,
		"network enemy chooses the nearest living player"
	)

	nearer_player.set("is_dead", true)
	_check(
		enemy.call("_find_nearest_living_player") == farther_player,
		"network enemy ignores a dead player when choosing a target"
	)
	farther_player.set("current_health", 0.0)
	_check(
		enemy.call("_find_nearest_living_player") == null,
		"network enemy ignores players with zero health"
	)
	farther_player.set("current_health", 100.0)
	farther_player.set("is_dead", false)
	farther_player.global_position = enemy.global_position + Vector3(0.0, 0.0, -8.0)

	enemy.set_physics_process(true)
	await get_tree().physics_frame
	enemy.set_physics_process(false)
	_check(int(enemy.get("ai_state")) == AI_CHASE, "network enemy enters chase state for a target in detection range")

	farther_player.global_position = enemy.global_position + Vector3(0.0, 0.0, -1.5)
	enemy.call("_server_update_attack_state", farther_player, 0.016)
	_check(int(enemy.get("ai_state")) == AI_ATTACK_WINDUP, "network enemy enters attack windup at close range")
	enemy.set("_state_elapsed", 0.5)
	var health_before_attack := float(farther_player.get("current_health"))
	enemy.call("_server_update_attack_state", farther_player, 0.016)
	_check(
		is_equal_approx(float(farther_player.get("current_health")), health_before_attack - 12.0),
		"network enemy applies configured damage after attack windup"
	)
	_check(int(enemy.get("ai_state")) == AI_ATTACK_COOLDOWN, "network enemy enters cooldown after its attack")

	enemy.set("_state_elapsed", 0.4)
	var health_during_cooldown := float(farther_player.get("current_health"))
	enemy.call("_server_update_attack_state", farther_player, 0.016)
	_check(
		is_equal_approx(float(farther_player.get("current_health")), health_during_cooldown),
		"network enemy does not deal a second hit during cooldown"
	)
	enemy.set("_state_elapsed", 1.2)
	enemy.call("_server_update_attack_state", farther_player, 0.016)
	_check(int(enemy.get("ai_state")) == AI_CHASE, "network enemy returns to chase after cooldown expires")

	var escape_enemy := _make_network_enemy(2)
	escape_enemy.set_physics_process(false)
	farther_player.global_position = escape_enemy.global_position + Vector3(0.0, 0.0, -1.5)
	escape_enemy.call("_server_update_attack_state", farther_player, 0.016)
	escape_enemy.set("_state_elapsed", 0.5)
	farther_player.global_position = escape_enemy.global_position + Vector3(0.0, 0.0, -5.0)
	var health_after_escape := float(farther_player.get("current_health"))
	escape_enemy.call("_server_update_attack_state", farther_player, 0.016)
	_check(
		is_equal_approx(float(farther_player.get("current_health")), health_after_escape),
		"network enemy cancels hit when the target leaves attack range during windup"
	)
	_check(int(escape_enemy.get("ai_state")) == AI_ATTACK_COOLDOWN, "interrupted network attack still exits windup safely")

	var patrol_enemy := _make_network_enemy(3)
	patrol_enemy.set_physics_process(false)
	patrol_enemy.set("_state_elapsed", 1.1)
	patrol_enemy.call("_server_patrol", 0.016)
	_check(int(patrol_enemy.get("ai_state")) == AI_PATROL, "network enemy transitions from idle to patrol")
	patrol_enemy.call("_server_patrol", 0.016)
	_check(
		absf(float(patrol_enemy.velocity.x)) + absf(float(patrol_enemy.velocity.z)) > 0.0,
		"network enemy patrol assigns movement toward a patrol point"
	)

	farther_player.set("is_dead", true)
	nearer_player.set("is_dead", true)
	var leash_enemy := _make_network_enemy(4)
	leash_enemy.set_physics_process(false)
	var home_position: Vector3 = leash_enemy.get("_home_position")
	leash_enemy.global_position = home_position + Vector3(30.0, 0.0, 0.0)
	leash_enemy.set_physics_process(true)
	await get_tree().physics_frame
	leash_enemy.set_physics_process(false)
	_check(int(leash_enemy.get("ai_state")) == AI_RETURN_HOME, "network enemy returns home after exceeding its leash radius")
	_check(leash_enemy.velocity.x < 0.0, "network enemy moves back toward its home position")

	var death_enemy := _make_network_enemy(5)
	death_enemy.set_physics_process(false)
	var death_events: Array[Dictionary] = []
	death_enemy.died.connect(func(dead_enemy: Node, attacker_peer_id: int) -> void:
		death_events.append({"enemy": dead_enemy, "attacker_peer_id": attacker_peer_id})
	)
	var full_health := float(death_enemy.get("current_health"))
	death_enemy.call("apply_damage_from_server", 0.0, 2)
	death_enemy.call("apply_damage_from_server", -10.0, 2)
	_check(is_equal_approx(float(death_enemy.get("current_health")), full_health), "network enemy rejects zero and negative damage")
	death_enemy.call("apply_damage_from_server", 9999.0, 2)
	_check(float(death_enemy.get("current_health")) == 0.0, "network enemy clamps lethal damage to zero health")
	_check(int(death_enemy.get("ai_state")) == AI_DEAD and bool(death_enemy.get("is_dead")), "network enemy enters dead state after lethal damage")
	_check(
		death_events.size() == 1 and int(death_events[0].get("attacker_peer_id", 0)) == 2,
		"network enemy emits one death event with the attacker peer ID"
	)
	death_enemy.call("apply_damage_from_server", 9999.0, 2)
	_check(death_events.size() == 1, "network enemy does not emit duplicate death events")

	print("[enemy-ai] local AI and network AI state coverage complete")


func _make_network_enemy(slot: int) -> CharacterBody3D:
	var enemy := NetworkEnemyScene.instantiate() as CharacterBody3D
	if enemy == null:
		_check(false, "network enemy scene instantiates")
		return CharacterBody3D.new()
	enemy.call("configure_spawn", slot)
	add_child(enemy)
	enemy.set_physics_process(false)
	return enemy


func _make_network_avatar(peer_id: int) -> CharacterBody3D:
	var avatar := NetworkAvatarScene.instantiate() as CharacterBody3D
	if avatar == null:
		_check(false, "network avatar scene instantiates")
		return CharacterBody3D.new()
	avatar.call("configure_owner", peer_id)
	add_child(avatar)
	avatar.set_physics_process(false)
	return avatar


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
