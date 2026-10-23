extends Node

const SAVE_PATH: String = "user://savegame.json"
const SAVE_BACKUP_PATH: String = "user://savegame.bak.json"
const SAVE_TEMP_PATH: String = "user://savegame.tmp.json"
const SAVE_VERSION: int = 2
const MAX_SAVE_SIZE: int = 1_048_576
const MAX_INVENTORY_SLOTS: int = 80
const MAX_POSITION_ABS: float = 100_000.0
const MAX_LEVEL: int = 50
const MAX_EXPERIENCE: int = 10_000


func save_game(data: Dictionary) -> bool:
	var normalized := _normalize_save(data)
	if normalized.is_empty():
		push_error("Save data failed schema validation.")
		return false

	var serialized := JSON.stringify(normalized, "\t")
	if serialized.to_utf8_buffer().size() > MAX_SAVE_SIZE:
		push_error("Save data exceeds the maximum allowed size.")
		return false

	var temp_file := FileAccess.open(SAVE_TEMP_PATH, FileAccess.WRITE)
	if temp_file == null:
		push_error("Could not open temporary save file: %s" % FileAccess.get_open_error())
		return false
	temp_file.store_string(serialized)
	temp_file.flush()
	var write_error: Error = temp_file.get_error()
	temp_file.close()
	if write_error != OK:
		_remove_if_exists(SAVE_TEMP_PATH)
		push_error("Could not flush temporary save file: %s" % error_string(write_error))
		return false

	var save_absolute := ProjectSettings.globalize_path(SAVE_PATH)
	var temp_absolute := ProjectSettings.globalize_path(SAVE_TEMP_PATH)
	var backup_absolute := ProjectSettings.globalize_path(SAVE_BACKUP_PATH)

	if FileAccess.file_exists(SAVE_PATH):
		if DirAccess.copy_absolute(save_absolute, backup_absolute) != OK:
			_remove_if_exists(SAVE_TEMP_PATH)
			push_error("Could not preserve the previous save as a backup.")
			return false

	var promote_error: Error = DirAccess.rename_absolute(temp_absolute, save_absolute)
	if promote_error != OK:
		_remove_if_exists(SAVE_TEMP_PATH)
		push_error("Could not replace the save file: %s" % error_string(promote_error))
		return false
	return true


func load_game() -> Dictionary:
	var primary := _read_save(SAVE_PATH)
	if not primary.is_empty():
		return primary

	var backup := _read_save(SAVE_BACKUP_PATH)
	if not backup.is_empty():
		push_warning("Primary save is missing or invalid; recovered data from backup.")
		return backup
	return {}


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(SAVE_BACKUP_PATH)


func delete_save() -> bool:
	var all_removed := true
	for path in [SAVE_PATH, SAVE_BACKUP_PATH, SAVE_TEMP_PATH]:
		if FileAccess.file_exists(path):
			if DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) != OK:
				all_removed = false
	return all_removed


func _read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Could not open save file for reading: %s" % FileAccess.get_open_error())
		return {}
	if file.get_length() <= 0 or file.get_length() > MAX_SAVE_SIZE:
		file.close()
		push_warning("Save file is empty or exceeds the size limit: %s" % path)
		return {}

	var parser := JSON.new()
	var parse_result: Error = parser.parse(file.get_as_text())
	file.close()
	if parse_result != OK or not (parser.data is Dictionary):
		push_warning("Save file contains invalid JSON or an invalid root type: %s" % path)
		return {}
	return _normalize_save(parser.data)


func _normalize_save(data: Dictionary) -> Dictionary:
	var version_value = data.get("version")
	if typeof(version_value) != TYPE_INT:
		return {}
	var version: int = int(version_value)
	if version < 1 or version > SAVE_VERSION:
		push_warning("Unsupported save version: %s" % str(version_value))
		return {}

	var required_keys: Array[String] = [
		"player_position", "player_health", "level", "experience",
		"inventory", "quest", "dialogue"
	]
	for key in required_keys:
		if not data.has(key):
			push_warning("Save file is missing required field: %s" % key)
			return {}

	var position_data = data.get("player_position")
	if not (position_data is Dictionary):
		return {}
	for axis in ["x", "y", "z"]:
		var coordinate = position_data.get(axis)
		if not _is_finite_number(coordinate):
			return {}
		if absf(float(coordinate)) > MAX_POSITION_ABS:
			return {}

	if not _is_finite_number(data.get("player_health")):
		return {}
	if float(data["player_health"]) < 0.0 or float(data["player_health"]) > 10_000.0:
		return {}
	if typeof(data.get("level")) != TYPE_INT:
		return {}
	if int(data["level"]) < 1 or int(data["level"]) > MAX_LEVEL:
		return {}
	if typeof(data.get("experience")) != TYPE_INT:
		return {}
	if int(data["experience"]) < 0 or int(data["experience"]) > MAX_EXPERIENCE:
		return {}

	var inventory = data.get("inventory")
	if not (inventory is Array) or inventory.size() > MAX_INVENTORY_SLOTS:
		return {}
	for entry in inventory:
		if entry == null:
			continue
		if not (entry is Dictionary):
			return {}
		var item_id = entry.get("id")
		var amount = entry.get("amount")
		if typeof(item_id) != TYPE_STRING or String(item_id).is_empty() or String(item_id).length() > 64:
			return {}
		if typeof(amount) != TYPE_INT or int(amount) < 1 or int(amount) > 999:
			return {}

	var quest = data.get("quest")
	if not (quest is Dictionary):
		return {}
	if quest.has("id") and typeof(quest["id"]) != TYPE_STRING:
		return {}
	if quest.has("progress") and typeof(quest["progress"]) != TYPE_INT:
		return {}
	if quest.has("active") and typeof(quest["active"]) != TYPE_BOOL:
		return {}
	if quest.has("progress") and (int(quest["progress"]) < 0 or int(quest["progress"]) > 3):
		return {}

	var dialogue = data.get("dialogue")
	if not (dialogue is Dictionary):
		return {}
	if dialogue.has("flags"):
		if not (dialogue["flags"] is Dictionary):
			return {}
		for flag_value in dialogue["flags"].values():
			if typeof(flag_value) != TYPE_BOOL:
				return {}

	var normalized := data.duplicate(true)
	# Version 1 used the same field layout; this migration preserves all saved state.
	normalized["version"] = SAVE_VERSION
	return normalized


func _is_finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value))


func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
