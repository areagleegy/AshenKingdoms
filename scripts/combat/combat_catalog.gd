extends Node
## Runtime reader for prototype weapon and armor data. It does not apply combat rules by itself.

const WEAPONS_PATH := "res://data/combat/weapons.json"
const ARMOR_PATH := "res://data/combat/armor.json"

var _weapons: Dictionary = {}
var _armor: Dictionary = {}
var _max_carry_weight: float = 30.0
var _encumbrance_thresholds_percent: Array[float] = [50.0, 80.0, 100.0]
var _load_error := ""


func _ready() -> void:
	_load_catalogs()


func reload_catalogs() -> bool:
	return _load_catalogs()


func get_load_error() -> String:
	return _load_error


func get_weapon_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for item_id in _weapons.keys():
		ids.append(str(item_id))
	ids.sort()
	return ids


func get_max_carry_weight() -> float:
	return _max_carry_weight


func get_encumbrance_thresholds_percent() -> Array[float]:
	return _encumbrance_thresholds_percent.duplicate()


func get_armor_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for item_id in _armor.keys():
		ids.append(str(item_id))
	ids.sort()
	return ids


func get_weapon(item_id: String) -> Dictionary:
	if not _weapons.has(item_id):
		return {}
	return (_weapons[item_id] as Dictionary).duplicate(true)


func get_armor(item_id: String) -> Dictionary:
	if not _armor.has(item_id):
		return {}
	return (_armor[item_id] as Dictionary).duplicate(true)


func calculate_damage_after_armor(raw_damage: float, armor_id: String = "") -> float:
	if not is_finite(raw_damage) or raw_damage <= 0.0:
		return 0.0
	var armor_profile := get_armor(armor_id)
	var reduction := clampf(float(armor_profile.get("damage_reduction", 0.0)), 0.0, 1.0)
	return maxf(0.0, raw_damage * (1.0 - reduction))


func _load_catalogs() -> bool:
	_load_error = ""
	var weapon_data := _read_json_object(WEAPONS_PATH)
	if weapon_data.is_empty():
		_weapons.clear()
		_armor.clear()
		if _load_error.is_empty():
			_load_error = "Weapon catalog is empty or invalid."
		return false
	var armor_data := _read_json_object(ARMOR_PATH)
	if armor_data.is_empty():
		_weapons.clear()
		_armor.clear()
		if _load_error.is_empty():
			_load_error = "Armor catalog is empty or invalid."
		return false
	if int(weapon_data.get("schema_version", 0)) != 1 or int(armor_data.get("schema_version", 0)) != 1:
		_weapons.clear()
		_armor.clear()
		_load_error = "Unsupported combat catalog schema version."
		return false
	var thresholds: Variant = armor_data.get("encumbrance_thresholds_percent", null)
	if not _valid_encumbrance_thresholds(thresholds):
		_weapons.clear()
		_armor.clear()
		_load_error = "Encumbrance thresholds must be finite, strictly increasing percentages in (0, 100]."
		return false
	var weapon_records: Variant = weapon_data.get("weapons", [])
	var armor_records: Variant = armor_data.get("armor", [])
	if not weapon_records is Array or not armor_records is Array:
		_weapons.clear()
		_armor.clear()
		_load_error = "Combat catalog collections must be arrays."
		return false
	var next_weapons: Dictionary = {}
	for record in weapon_records:
		if not record is Dictionary:
			_load_error = "Weapon record must be an object."
			return false
		var item_id := str(record.get("id", ""))
		if item_id.is_empty() or next_weapons.has(item_id):
			_load_error = "Weapon ID is empty or duplicated."
			return false
		next_weapons[item_id] = record.duplicate(true)
	var next_armor: Dictionary = {}
	for record in armor_records:
		if not record is Dictionary:
			_load_error = "Armor record must be an object."
			return false
		var item_id := str(record.get("id", ""))
		if item_id.is_empty() or next_armor.has(item_id):
			_load_error = "Armor ID is empty or duplicated."
			return false
		next_armor[item_id] = record.duplicate(true)
	if next_weapons.is_empty() or next_armor.is_empty():
		_load_error = "Combat catalogs must contain at least one weapon and armor."
		return false
	_weapons = next_weapons
	_armor = next_armor
	_max_carry_weight = maxf(1.0, float(armor_data.get("max_carry_weight", 30.0)))
	_encumbrance_thresholds_percent.clear()
	for threshold in thresholds:
		_encumbrance_thresholds_percent.append(float(threshold))
	return true


func _valid_encumbrance_thresholds(value: Variant) -> bool:
	if not value is Array or value.is_empty():
		return false
	var previous := 0.0
	for threshold in value:
		if threshold is bool or not (threshold is int or threshold is float):
			return false
		var percent := float(threshold)
		if not is_finite(percent) or percent <= previous or percent > 100.0:
			return false
		previous = percent
	return true


func _read_json_object(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_load_error = "Missing combat catalog: %s" % path
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_load_error = "Could not open combat catalog: %s" % path
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		_load_error = "Combat catalog must be a JSON object: %s" % path
		return {}
	return parsed
