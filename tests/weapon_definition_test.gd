extends SceneTree

const WeaponDefinitionScript: Script = preload("res://scripts/combat/weapon_definition.gd")

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var weapon: Resource = WeaponDefinitionScript.new()
	weapon.set("weapon_id", &"test_blade")
	weapon.set("category", &"light")
	weapon.set("damage", 18.0)
	weapon.set("range_m", 1.5)
	weapon.set("windup_seconds", 0.15)
	weapon.set("active_seconds", 0.12)
	weapon.set("recovery_seconds", 0.25)
	_check(bool(weapon.call("is_valid_definition")), "valid light weapon definition is accepted")

	weapon.set("weapon_id", &"")
	_check(_has_error(weapon, "weapon_id"), "empty weapon id is rejected")
	weapon.set("weapon_id", &"test_blade")

	weapon.set("damage", -1.0)
	_check(_has_error(weapon, "damage"), "negative damage is rejected")
	weapon.set("damage", INF)
	_check(_has_error(weapon, "damage"), "infinite damage is rejected")
	weapon.set("damage", 18.0)

	weapon.set("range_m", -0.1)
	_check(_has_error(weapon, "range_m"), "negative range is rejected")
	weapon.set("range_m", 1.5)

	weapon.set("category", &"unknown")
	_check(_has_error(weapon, "category"), "unsupported weapon category is rejected")
	weapon.set("category", &"charged")
	_check(_has_error(weapon, "charge_seconds"), "charged weapon without charge time is rejected")
	weapon.set("charge_seconds", 1.5)
	_check(bool(weapon.call("is_valid_definition")), "charged weapon with charge time is accepted")

	weapon.set("category", &"limited")
	weapon.set("charge_seconds", 0.0)
	weapon.set("ammo_capacity", 0)
	weapon.set("charges", 0)
	_check(_has_error(weapon, "limited weapons"), "limited weapon without ammo or charges is rejected")
	weapon.set("ammo_capacity", 3)
	_check(bool(weapon.call("is_valid_definition")), "limited weapon with ammunition is accepted")

	print("[weapon-definition] failures: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _has_error(weapon: Resource, fragment: String) -> bool:
	var errors: PackedStringArray = weapon.call("validation_errors")
	for error_text in errors:
		if String(error_text).contains(fragment):
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] ", message)
	else:
		_failures += 1
		push_error("[FAIL] " + message)
