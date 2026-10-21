extends SceneTree

const WeaponDefinitionScript: Script = preload("res://scripts/combat/weapon_definition.gd")
const CombatRuntimeScript: Script = preload("res://scripts/combat/combat_runtime.gd")

var _failures: int = 0
var _hit_count: int = 0
var _finished_count: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var weapon: Resource = WeaponDefinitionScript.new()
	weapon.set("weapon_id", &"runtime_test_blade")
	weapon.set("category", &"light")
	weapon.set("damage", 20.0)
	weapon.set("range_m", 2.0)
	weapon.set("windup_seconds", 0.2)
	weapon.set("active_seconds", 0.1)
	weapon.set("recovery_seconds", 0.2)
	weapon.set("cooldown_seconds", 0.5)
	weapon.set("stamina_cost", 12.0)

	var combat: Node = CombatRuntimeScript.new()
	root.add_child(combat)
	combat.hit_window_opened.connect(_on_hit_window)
	combat.attack_finished.connect(_on_attack_finished)
	_check(bool(combat.call("configure", weapon, 50.0)), "valid weapon configures runtime")
	_check(bool(combat.call("can_start_attack")), "runtime starts ready")
	_check(bool(combat.call("start_attack")), "attack starts")
	_check(is_equal_approx(float(combat.get("stamina")), 38.0), "attack spends stamina once")
	_check(StringName(combat.get("phase")) == &"windup", "attack begins in windup")
	_check(not bool(combat.call("start_attack")), "second attack is rejected during windup")

	combat.call("advance", 0.19)
	_check(StringName(combat.get("phase")) == &"windup", "windup does not end early")
	_check(_hit_count == 0, "hit window remains closed during windup")
	combat.call("advance", 0.02)
	_check(StringName(combat.get("phase")) == &"active", "windup transitions to active")
	_check(_hit_count == 1, "hit window emits exactly once")
	combat.call("advance", 0.11)
	_check(StringName(combat.get("phase")) == &"recovery", "active phase transitions to recovery")
	combat.call("advance", 0.21)
	_check(StringName(combat.get("phase")) == &"cooldown", "recovery enters cooldown")
	_check(_finished_count == 0, "attack is not finished before cooldown ends")
	_check(not bool(combat.call("can_start_attack")), "new attack blocked during cooldown")
	combat.call("advance", 0.49)
	_check(StringName(combat.get("phase")) == &"cooldown", "cooldown respects its configured duration")
	combat.call("advance", 0.02)
	_check(StringName(combat.get("phase")) == &"ready", "runtime returns to ready after cooldown")
	_check(_finished_count == 1, "attack completion emits once")

	weapon.set("stamina_cost", 100.0)
	_check(bool(combat.call("configure", weapon, 20.0)), "runtime can be reset with valid configuration")
	_check(not bool(combat.call("can_start_attack")), "insufficient stamina blocks attack")
	weapon.set("stamina_cost", 0.0)
	weapon.set("category", &"limited")
	weapon.set("ammo_capacity", 1)
	_check(bool(combat.call("configure", weapon, 20.0)), "limited-ammo weapon configures")
	_check(bool(combat.call("start_attack")), "limited-ammo weapon can fire with ammo")
	_check(int(combat.get("ammunition")) == 0, "limited-ammo weapon consumes one round on start")
	_check(not bool(combat.call("can_start_attack")), "empty limited-ammo weapon cannot fire again")

	print("[combat-runtime] failures: %d" % _failures)
	combat.queue_free()
	quit(1 if _failures > 0 else 0)


func _on_hit_window(_weapon_id: StringName) -> void:
	_hit_count += 1


func _on_attack_finished(_weapon_id: StringName) -> void:
	_finished_count += 1


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] ", message)
	else:
		_failures += 1
		push_error("[FAIL] " + message)
