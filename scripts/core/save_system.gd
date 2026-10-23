extends Node

const SAVE_PATH: String = "user://savegame.json"
const SAVE_TEMP_PATH: String = "user://savegame.json.tmp"
const SAVE_BACKUP_PATH: String = "user://savegame.json.bak"
const SAVE_BACKUP_TEMP_PATH: String = "user://savegame.json.bak.tmp"
const SAVE_REPLACEMENT_PATH: String = "user://savegame.json.old"
const SAVE_BACKUP_REPLACEMENT_PATH: String = "user://savegame.json.bak.old"
const MAX_SAVE_BYTES: int = 1024 * 1024
const MAX_SAVE_NESTING_DEPTH: int = 32
const MAX_SAVE_CONTAINER_ITEMS: int = 10000
const SAVE_SCHEMA_VERSION: int = 1


func save_game(data: Dictionary) -> bool:
	if not _is_valid_save_data(data):
		push_error("Refusing to save data that is outside the supported save schema.")
		return false

	var serialized := JSON.stringify(data, "\t")
	if serialized.to_utf8_buffer().size() > MAX_SAVE_BYTES:
		push_error("Refusing to write a save file larger than the safety limit.")
		return false

	var write_error := _write_text_file(SAVE_TEMP_PATH, serialized)
	if write_error != OK:
		push_error("Could not write temporary save file: %s" % error_string(write_error))
		_remove_file_if_exists(SAVE_TEMP_PATH)
		return false

	var staged := _read_save_data(SAVE_TEMP_PATH)
	if not bool(staged.get("ok", false)):
		push_error("Temporary save failed validation; the previous save was preserved.")
		_remove_file_if_exists(SAVE_TEMP_PATH)
		return false

	if not _create_backup_from_current_save():
		push_error("Could not preserve the current save backup; the previous save was preserved.")
		_remove_file_if_exists(SAVE_TEMP_PATH)
		return false

	if not _promote_file(SAVE_TEMP_PATH, SAVE_PATH, SAVE_REPLACEMENT_PATH):
		push_error("Could not atomically replace the save file.")
		_remove_file_if_exists(SAVE_TEMP_PATH)
		return false

	return true


func load_game() -> Dictionary:
	var primary := _read_save_data(SAVE_PATH)
	if bool(primary.get("ok", false)):
		return primary["data"]

	var backup := _read_save_data(SAVE_BACKUP_PATH)
	if bool(backup.get("ok", false)):
		push_warning("The primary save is invalid or missing; recovering from the last valid backup.")
		var serialized := JSON.stringify(backup["data"], "\t")
		var write_error := _write_text_file(SAVE_TEMP_PATH, serialized)
		if write_error == OK and _promote_file(SAVE_TEMP_PATH, SAVE_PATH, SAVE_REPLACEMENT_PATH):
			return backup["data"]

		_remove_file_if_exists(SAVE_TEMP_PATH)
		push_warning("Backup data is valid but could not be restored to the primary save path.")
		return backup["data"]

	# A valid staged save can recover a first save interrupted before promotion,
	# but only when neither the primary file nor a valid backup is available.
	var staged := _read_save_data(SAVE_TEMP_PATH)
	if bool(staged.get("ok", false)):
		push_warning("Recovering a complete staged save after an interrupted write.")
		if _promote_file(SAVE_TEMP_PATH, SAVE_PATH, SAVE_REPLACEMENT_PATH):
			return staged["data"]
		push_warning("Staged save is valid but could not be promoted; using it in memory.")
		return staged["data"]

	return {}


func has_save() -> bool:
	return (
		bool(_read_save_data(SAVE_PATH).get("ok", false))
		or bool(_read_save_data(SAVE_BACKUP_PATH).get("ok", false))
		or bool(_read_save_data(SAVE_TEMP_PATH).get("ok", false))
	)


func delete_save() -> bool:
	var all_removed := true
	for path in [
		SAVE_PATH,
		SAVE_TEMP_PATH,
		SAVE_BACKUP_PATH,
		SAVE_BACKUP_TEMP_PATH,
		SAVE_REPLACEMENT_PATH,
		SAVE_BACKUP_REPLACEMENT_PATH
	]:
		if not _remove_file_if_exists(path):
			all_removed = false
	return all_removed


func _read_save_data(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "Save file does not exist."}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Save file cannot be opened."}

	var file_size := file.get_length()
	if file_size < 1 or file_size > MAX_SAVE_BYTES:
		file.close()
		return {"ok": false, "error": "Save file size is outside allowed limits."}

	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {"ok": false, "error": "Save file is not valid JSON."}

	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		return {"ok": false, "error": "Save data root must be a dictionary."}
	if not _is_valid_save_data(parsed):
		return {"ok": false, "error": "Save data does not match the supported schema."}
	return {"ok": true, "error": "", "data": parsed}


func _is_valid_save_data(data: Dictionary) -> bool:
	if data.size() > 128 or not _is_json_compatible(data):
		return false

	for version_key in ["version", "schema_version"]:
		if data.has(version_key):
			if typeof(data[version_key]) != TYPE_INT or int(data[version_key]) != SAVE_SCHEMA_VERSION:
				return false

	if data.has("player_position"):
		var position_value: Variant = data["player_position"]
		if not position_value is Dictionary:
			return false
		var position_data: Dictionary = position_value
		for axis in ["x", "y", "z"]:
			if not position_data.has(axis):
				return false
			var coordinate: Variant = position_data[axis]
			if typeof(coordinate) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(coordinate)):
				return false
			if absf(float(coordinate)) > 1000000.0:
				return false

	if data.has("player_health"):
		var health_value: Variant = data["player_health"]
		if typeof(health_value) not in [TYPE_INT, TYPE_FLOAT]:
			return false
		if not is_finite(float(health_value)) or float(health_value) < 0.0 or float(health_value) > 1000000.0:
			return false

	if data.has("level"):
		if typeof(data["level"]) != TYPE_INT or int(data["level"]) < 1 or int(data["level"]) > 10000:
			return false

	if data.has("experience"):
		if typeof(data["experience"]) != TYPE_INT or int(data["experience"]) < 0 or int(data["experience"]) > 2147483647:
			return false

	if data.has("inventory"):
		var inventory_value: Variant = data["inventory"]
		if not inventory_value is Array or inventory_value.size() > 1000:
			return false

	for dictionary_key in ["quest", "dialogue"]:
		if data.has(dictionary_key) and not data[dictionary_key] is Dictionary:
			return false

	return true


func _is_json_compatible(value: Variant, depth: int = 0) -> bool:
	if depth > MAX_SAVE_NESTING_DEPTH:
		return false

	var value_type := typeof(value)
	if value_type in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING]:
		return true
	if value_type == TYPE_FLOAT:
		return is_finite(float(value))
	if value is Array:
		if value.size() > MAX_SAVE_CONTAINER_ITEMS:
			return false
		for item in value:
			if not _is_json_compatible(item, depth + 1):
				return false
		return true
	if value is Dictionary:
		if value.size() > MAX_SAVE_CONTAINER_ITEMS:
			return false
		for key in value.keys():
			if typeof(key) != TYPE_STRING:
				return false
			if not _is_json_compatible(value[key], depth + 1):
				return false
		return true
	return false


func _create_backup_from_current_save() -> bool:
	var current := _read_save_data(SAVE_PATH)
	if not bool(current.get("ok", false)):
		# Keep any earlier valid backup when the primary file is missing or corrupt.
		return true

	if not _remove_file_if_exists(SAVE_BACKUP_TEMP_PATH):
		return false
	var copy_error := DirAccess.copy_absolute(
		ProjectSettings.globalize_path(SAVE_PATH),
		ProjectSettings.globalize_path(SAVE_BACKUP_TEMP_PATH)
	)
	if copy_error != OK:
		return false

	var backup_candidate := _read_save_data(SAVE_BACKUP_TEMP_PATH)
	if not bool(backup_candidate.get("ok", false)):
		_remove_file_if_exists(SAVE_BACKUP_TEMP_PATH)
		return false

	return _promote_file(
		SAVE_BACKUP_TEMP_PATH,
		SAVE_BACKUP_PATH,
		SAVE_BACKUP_REPLACEMENT_PATH
	)


func _write_text_file(path: String, text: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		_remove_file_if_exists(path)
		return write_error
	return OK


func _promote_file(source_path: String, destination_path: String, recovery_path: String) -> bool:
	var source_absolute := ProjectSettings.globalize_path(source_path)
	var destination_absolute := ProjectSettings.globalize_path(destination_path)
	var recovery_absolute := ProjectSettings.globalize_path(recovery_path)

	var direct_error := DirAccess.rename_absolute(source_absolute, destination_absolute)
	if direct_error == OK:
		_remove_file_if_exists(recovery_path)
		return true

	# If direct replacement fails, rotate the previous file out of the way and
	# roll it back if promotion then fails.
	if not FileAccess.file_exists(destination_path):
		return false
	if not _remove_file_if_exists(recovery_path):
		return false

	var rotate_error := DirAccess.rename_absolute(destination_absolute, recovery_absolute)
	if rotate_error != OK:
		return false

	var promote_error := DirAccess.rename_absolute(source_absolute, destination_absolute)
	if promote_error != OK:
		var rollback_error := DirAccess.rename_absolute(recovery_absolute, destination_absolute)
		if rollback_error != OK:
			push_error("Save replacement and rollback both failed: %s / %s" % [
				error_string(promote_error),
				error_string(rollback_error)
			])
		return false

	_remove_file_if_exists(recovery_path)
	return true


func _remove_file_if_exists(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK
