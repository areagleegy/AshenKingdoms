extends Node3D

const NETWORK_ENEMY_SCENE: PackedScene = preload("res://scenes/network/NetworkEnemy.tscn")

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var enemy := NETWORK_ENEMY_SCENE.instantiate()
	_check(enemy != null, "network enemy scene instantiates")
	if enemy == null:
		get_tree().quit(1)
		return

	add_child(enemy)
	await get_tree().process_frame
	_check(
		is_equal_approx(float(enemy.get("current_health")), 85.0),
		"enemy starts at configured HP"
	)

	var death_events: Array[int] = []
	enemy.connect(
		"died",
		func(_dead_enemy: Node, attacker_peer_id: int) -> void:
			death_events.append(attacker_peer_id)
	)

	enemy.call("apply_damage_from_server", 20.0, 1)
	_check(
		is_equal_approx(float(enemy.get("current_health")), 65.0),
		"normal damage subtracts from HP"
	)

	enemy.call("apply_damage_from_server", 0.0, 1)
	_check(is_equal_approx(float(enemy.get("current_health")), 65.0), "zero damage is ignored")
	enemy.call("apply_damage_from_server", -10.0, 1)
	_check(is_equal_approx(float(enemy.get("current_health")), 65.0), "negative damage is ignored")

	enemy.call("apply_damage_from_server", 999.0, 7)
	_check(
		is_equal_approx(float(enemy.get("current_health")), 0.0),
		"lethal damage clamps HP at zero"
	)
	_check(bool(enemy.get("is_dead")), "lethal damage marks the enemy dead")
	_check(death_events.size() == 1, "lethal damage emits exactly one death event")
	_check(
		death_events.size() == 1 and death_events[0] == 7,
		"death event preserves attacker peer ID"
	)

	enemy.call("apply_damage_from_server", 10.0, 8)
	_check(
		is_equal_approx(float(enemy.get("current_health")), 0.0),
		"damage after death cannot change HP"
	)
	_check(death_events.size() == 1, "damage after death does not emit another death event")

	print("[combat-mechanics] checks: %d, failures: %d" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
