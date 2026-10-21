extends SceneTree

const CombatCatalogScript: Script = preload("res://scripts/combat/combat_catalog.gd")

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog: Node = root.get_node_or_null("CombatCatalog")
	var owns_catalog := catalog == null
	if owns_catalog:
		catalog = CombatCatalogScript.new()
		catalog.name = "CombatCatalogSmokeTest"
		root.add_child(catalog)
	else:
		catalog = catalog.duplicate() if false else catalog
		_check(bool(catalog.call("reload_catalogs")), "autoload reloads combat JSON catalogs")
	_check(String(catalog.call("get_load_error")).is_empty(), "valid catalog has no load error")
	var weapon_ids: PackedStringArray = catalog.call("get_weapon_ids")
	var armor_ids: PackedStringArray = catalog.call("get_armor_ids")
	_check(weapon_ids.size() == 7, "seven prototype weapons load")
	_check(armor_ids.size() == 4, "four prototype armor records load")
	_check(weapon_ids.has("cinder_maul"), "heavy weapon is addressable by stable ID")
	_check(weapon_ids.has("ash_lance"), "charged weapon is addressable by stable ID")
	_check(armor_ids.has("cinder_plate"), "heavy armor is addressable by stable ID")
	var heavy_weapon: Dictionary = catalog.call("get_weapon", "cinder_maul")
	_check(int(heavy_weapon.get("damage", 0)) == 56, "weapon profile returns expected prototype damage")
	_check((catalog.call("get_weapon", "missing_weapon") as Dictionary).is_empty(), "unknown weapon returns empty profile")
	_check(is_equal_approx(float(catalog.call("calculate_damage_after_armor", 100.0, "cinder_plate")), 60.0), "armor mitigation returns 60 damage from 100")
	_check(is_equal_approx(float(catalog.call("calculate_damage_after_armor", 100.0, "unknown_armor")), 100.0), "unknown armor safely applies no mitigation")
	_check(is_equal_approx(float(catalog.call("calculate_damage_after_armor", -1.0, "")), 0.0), "non-positive incoming damage becomes zero")
	var mutable_profile: Dictionary = catalog.call("get_weapon", "ash_dagger")
	mutable_profile["damage"] = 999
	var fresh_profile: Dictionary = catalog.call("get_weapon", "ash_dagger")
	_check(int(fresh_profile.get("damage", 0)) == 15, "callers cannot mutate the stored weapon profile")
	print("[combat-catalog-smoke] failures: %d" % _failures)
	if owns_catalog and is_instance_valid(catalog):
		catalog.free()
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
