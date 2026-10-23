extends SceneTree

const LOADER_SCRIPT := "res://scripts/world/world_catalog_loader.gd"
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var loader_script := load(LOADER_SCRIPT) as Script
	_check(loader_script != null, "world catalog loader script loads")
	if loader_script == null:
		quit(1)
		return

	var loader := loader_script.new() as Node
	root.add_child(loader)
	_check(not loader.call("get_catalog").is_empty(), "default world catalog loads")
	_check(loader.call("get_region", "ashen_basin").get("id", "") == "ashen_basin", "region lookup returns the requested region")
	_check(loader.call("get_equipment", "weapons", "basin_sword").get("damage", 0) == 30, "weapon lookup returns structured combat data")
	_check(loader.call("get_record", "world_events", "ashfall").get("id", "") == "ashfall", "world event lookup returns the requested event")
	_check(loader.call("get_last_error").is_empty(), "successful default load leaves no validation error")

	var valid_catalog: Dictionary = loader.call("get_catalog")
	var temp_path := "user://world_catalog_loader_test.json"
	_check(_write_json(temp_path, valid_catalog), "valid fixture can be written")
	_check(loader.call("load_catalog", temp_path), "valid catalog fixture is accepted")

	var invalid_schema: Dictionary = valid_catalog.duplicate(true)
	invalid_schema["schema_version"] = 999
	_check(_write_json(temp_path, invalid_schema), "invalid schema fixture can be written")
	_check(not loader.call("load_catalog", temp_path), "unsupported schema version is rejected")
	_check(loader.call("get_catalog").is_empty(), "failed load clears stale catalog data")

	_check(_write_text(temp_path, "{invalid json"), "malformed JSON fixture can be written")
	_check(not loader.call("load_catalog", temp_path), "malformed JSON is rejected")

	var duplicate_id: Dictionary = valid_catalog.duplicate(true)
	duplicate_id["regions"].append((duplicate_id["regions"][0] as Dictionary).duplicate(true))
	_check(_write_json(temp_path, duplicate_id), "duplicate ID fixture can be written")
	_check(not loader.call("load_catalog", temp_path), "duplicate IDs are rejected")

	var unknown_threat: Dictionary = valid_catalog.duplicate(true)
	unknown_threat["regions"][0]["threats"] = ["missing_creature"]
	_check(_write_json(temp_path, unknown_threat), "unknown creature fixture can be written")
	_check(not loader.call("load_catalog", temp_path), "unknown creature references are rejected")

	var unknown_habitat: Dictionary = valid_catalog.duplicate(true)
	unknown_habitat["creatures"][0]["habitats"] = ["missing_region"]
	_check(_write_json(temp_path, unknown_habitat), "unknown habitat fixture can be written")
	_check(not loader.call("load_catalog", temp_path), "unknown creature habitats are rejected")

	var unknown_waterway_region: Dictionary = valid_catalog.duplicate(true)
	unknown_waterway_region["waterways"][0]["connects"] = ["missing_region"]
	_check(_write_json(temp_path, unknown_waterway_region), "unknown waterway fixture can be written")
	_check(not loader.call("load_catalog", temp_path), "unknown waterway region references are rejected")

	var malformed_terrain_bonus: Dictionary = valid_catalog.duplicate(true)
	malformed_terrain_bonus["transport"]["mounts"][0]["terrain_bonus"] = {"ashen_basin": true}
	_check(_write_json(temp_path, malformed_terrain_bonus), "malformed transport fixture can be written")
	_check(not loader.call("load_catalog", temp_path), "non-array transport terrain bonuses are rejected")

	var unknown_home: Dictionary = valid_catalog.duplicate(true)
	unknown_home["characters"][0]["home"] = "missing_settlement"
	_check(_write_json(temp_path, unknown_home), "unknown home fixture can be written")
	_check(not loader.call("load_catalog", temp_path), "unknown character home is rejected")

	var negative_damage: Dictionary = valid_catalog.duplicate(true)
	negative_damage["equipment"]["weapons"][0]["damage"] = -1
	_check(_write_json(temp_path, negative_damage), "negative damage fixture can be written")
	_check(not loader.call("load_catalog", temp_path), "negative weapon damage is rejected")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
	loader.queue_free()
	print("[world-catalog-loader] failures: %d" % failures)
	quit(1 if failures > 0 else 0)


func _write_json(path: String, value: Dictionary) -> bool:
	return _write_text(path, JSON.stringify(value))


func _write_text(path: String, value: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(value)
	file.close()
	return true


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] %s" % message)
	else:
		failures += 1
		push_error("[FAIL] %s" % message)
