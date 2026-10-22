extends Node

const SAVE_PATH: String = "user://savegame.json"
const CURRENT_SAVE_VERSION: int = 1
const MAX_SAVE_BYTES: int = 2 * 1024 * 1024
const MAX_WORLD_COORDINATE: float = 1000000.0
const MAX_LEVEL: int = 100000
const MAX_EXPERIENCE: int = 1000000000
const MAX_INVENTORY_SLOTS: int = 80
const MAX_STACK_AMOUNT: int = 9999

# Kept writable for isolated reliability tests; normal game instances use SAVE_PATH.
var save_path: String = SAVE_PATH


func save_game(data: Dictionary) -> bool:
	var normalized := _normalize_save_data(data)
	if normalized.is_empty():
		push_error("Refusing to save invalid or unsupported save data.")
		return false

	var serialized := JSON.stringify(normalized, "\t")
	if serialized.is_empty() or serialized.to_utf8_buffer().size() > MAX_SAVE_BYTES:
		push_error("Save data is empty or exceeds the %d-byte limit." % MAX_SAVE_BYTES)
		return false

	var temp_path := _temp_path()
	var backup_path := _backup_path()
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not open temporary save file: %s" % FileAccess.get_open_error())
		return false

	file.store_string(serialized)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		_remove_file_if_present(temp_path)
		push_error("Writing temporary save failed: %s" % error_string(write_error))
		return false

	# Do not rotate a valid backup away when the primary is corrupt and needs recovery.
	var primary_is_valid := not _read_valid_save(save_path).is_empty()
	var backup_is_valid := not _read_valid_save(backup_path).is_empty()
	if FileAccess.file_exists(save_path):
		if backup_is_valid and not primary_is_valid:
			if not _remove_file_if_present(save_path):
				_remove_file_if_present(temp_path)
				return false
		else:
			if FileAccess.file_exists(backup_path) and not _remove_file_if_present(backup_path):
				_remove_file_if_present(temp_path)
				push_error("Could not rotate the previous backup save.")
				return false
			var rotate_error := DirAccess.rename_absolute(
				ProjectSettings.globalize_path(save_path),
				ProjectSettings.globalize_path(backup_path)
			)
			if rotate_error != OK:
				_remove_file_if_present(temp_path)
				push_error("Could not preserve the previous save: %s" % error_string(rotate_error))
				return false

	var promote_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temp_path),
		ProjectSettings.globalize_path(save_path)
	)
	if promote_error != OK:
		# Restore the previous save if promotion fails after it was rotated.
		if not FileAccess.file_exists(save_path) and FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(
				ProjectSettings.globalize_path(backup_path),
				ProjectSettings.globalize_path(save_path)
			)
		_remove_file_if_present(temp_path)
		push_error("Could not promote the temporary save: %s" % error_string(promote_error))
		return false

	return true


func load_game() -> Dictionary:
	var primary := _read_valid_save(save_path)
	if not primary.is_empty():
		return primary

	var backup_path := _backup_path()
	var backup := _read_valid_save(backup_path)
	if not backup.is_empty():
		push_warning("Primary save is invalid or missing; recovered the previous backup save.")
		return backup

	return {}


func has_save() -> bool:
	return not _read_valid_save(save_path).is_empty() or not _read_valid_save(_backup_path()).is_empty()


func delete_save() -> bool:
	var success := true
	for path in [save_path, _temp_path(), _backup_path()]:
		if not _remove_file_if_present(path):
			success = false
	return success


func _normalize_save_data(data: Dictionary) -> Dictionary:
	if data.is_empty():
		return {}
	var normalized: Dictionary = data.duplicate(true)
	# Versionless saves from the earliest prototype are accepted only if their full
	# structure passes the current schema; this is a safe v0 -> v1 migration.
	if not normalized.has("version"):
		if not _has_required_fields(normalized):
			return {}
		normalized["version"] = CURRENT_SAVE_VERSION
	if not (normalized.get("version") is int):
		return {}
	if int(normalized["version"]) != CURRENT_SAVE_VERSION:
		return {}
	if not _has_required_fields(normalized):
		return {}
	return normalized


func _has_required_fields(data: Dictionary) -> bool:
	for key in ["player_position", "player_health", "level", "experience", "inventory", "quest", "dialogue"]:
		if not data.has(key):
			return false

	var position_data: Variant = data.get("player_position")
	if not (position_data is Dictionary):
		return false
	var position: Dictionary = position_data
	for axis in ["x", "y", "z"]:
		var coordinate: Variant = position.get(axis)
		if not _is_finite_number(coordinate) or absf(float(coordinate)) > MAX_WORLD_COORDINATE:
			return false

	var level_value: Variant = data.get("level")
	var experience_value: Variant = data.get("experience")
	var health_value: Variant = data.get("player_health")
	if not (level_value is int) or not (experience_value is int) or not _is_finite_number(health_value):
		return false
	var level := int(level_value)
	var experience := int(experience_value)
	var health := float(health_value)
	if level < 1 or level > MAX_LEVEL or experience < 0 or experience > MAX_EXPERIENCE:
		return false
	var max_health := 100.0 + float(level - 1) * 10.0
	if health < 0.0 or health > max_health:
		return false

	var inventory_value: Variant = data.get("inventory")
	if not (inventory_value is Array):
		return false
	var inventory: Array = inventory_value
	if inventory.size() > MAX_INVENTORY_SLOTS:
		return false
	for entry in inventory:
		if entry == null:
			continue
		if not (entry is Dictionary):
			return false
		var item: Dictionary = entry
		var item_id: Variant = item.get("id")
		var amount: Variant = item.get("amount")
		if not (item_id is String) or String(item_id).is_empty() or String(item_id).length() > 128:
			return false
		if not (amount is int) or int(amount) < 1 or int(amount) > MAX_STACK_AMOUNT:
			return false

	var quest_value: Variant = data.get("quest")
	if not (quest_value is Dictionary):
		return false
	var quest: Dictionary = quest_value
	if not (quest.get("id", "") is String) or not (quest.get("title", "") is String):
		return false
	if not (quest.get("progress", 0) is int) or not (quest.get("active", false) is bool):
		return false
	if int(quest.get("progress", 0)) < 0 or int(quest.get("progress", 0)) > 100000:
		return false

	if not (data.get("dialogue") is Dictionary):
		return false
	return true


func _is_finite_number(value: Variant) -> bool:
	if not (value is int or value is float):
		return false
	return is_finite(float(value))


func _read_valid_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	if file.get_length() <= 0 or file.get_length() > MAX_SAVE_BYTES:
		file.close()
		return {}
	var raw := file.get_as_text()
	var read_error: Error = file.get_error()
	file.close()
	if read_error != OK:
		return {}

	var parser := JSON.new()
	if parser.parse(raw) != OK:
		return {}
	var parsed: Variant = parser.data
	if not (parsed is Dictionary):
		return {}
	return _normalize_save_data(parsed)


func _temp_path() -> String:
	return save_path + ".tmp"


func _backup_path() -> String:
	return save_path + ".bak"


func _remove_file_if_present(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	var result := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if result != OK:
		push_error("Could not remove save file %s: %s" % [path, error_string(result)])
		return false
	return true
