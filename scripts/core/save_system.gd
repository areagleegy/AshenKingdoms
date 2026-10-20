extends Node

const SAVE_PATH: String = "user://savegame.json"
const TEMP_SAVE_PATH: String = "user://savegame.json.tmp"
const BACKUP_SAVE_PATH: String = "user://savegame.json.bak"
const SAVE_SCHEMA_VERSION: int = 1


func save_game(data: Dictionary) -> bool:
	var payload := data.duplicate(true)
	payload["_schema_version"] = SAVE_SCHEMA_VERSION
	var serialized := JSON.stringify(payload, "\t")
	if serialized.is_empty():
		push_error("Could not serialize save data.")
		return false

	# Validate the serialized payload before touching the last known-good save.
	var parser := JSON.new()
	if parser.parse(serialized) != OK or not (parser.data is Dictionary):
		push_error("Serialized save data failed validation.")
		return false

	var file := FileAccess.open(TEMP_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not open temporary save file: %s" % FileAccess.get_open_error())
		return false
	file.store_string(serialized)
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		_remove_if_exists(TEMP_SAVE_PATH)
		push_error("Writing temporary save failed: %s" % error_string(write_error))
		return false

	# Read back the temporary file so a truncated or malformed write cannot
	# replace the previous save.
	var verify_file := FileAccess.open(TEMP_SAVE_PATH, FileAccess.READ)
	if verify_file == null:
		_remove_if_exists(TEMP_SAVE_PATH)
		push_error("Could not verify temporary save: %s" % FileAccess.get_open_error())
		return false
	var verify_parser := JSON.new()
	var verify_error := verify_parser.parse(verify_file.get_as_text())
	verify_file.close()
	if verify_error != OK or not (verify_parser.data is Dictionary):
		_remove_if_exists(TEMP_SAVE_PATH)
		push_error("Temporary save failed read-back validation.")
		return false

	var save_absolute := ProjectSettings.globalize_path(SAVE_PATH)
	var temp_absolute := ProjectSettings.globalize_path(TEMP_SAVE_PATH)
	var backup_absolute := ProjectSettings.globalize_path(BACKUP_SAVE_PATH)
	var had_previous_save := FileAccess.file_exists(SAVE_PATH)

	_remove_if_exists(BACKUP_SAVE_PATH)
	if had_previous_save:
		var backup_error := DirAccess.rename_absolute(save_absolute, backup_absolute)
		if backup_error != OK:
			_remove_if_exists(TEMP_SAVE_PATH)
			push_error("Could not preserve previous save: %s" % error_string(backup_error))
			return false

	var replace_error := DirAccess.rename_absolute(temp_absolute, save_absolute)
	if replace_error != OK:
		if had_previous_save:
			var restore_error := DirAccess.rename_absolute(backup_absolute, save_absolute)
			if restore_error != OK:
				push_error("Save replacement and backup restoration both failed: %s" % error_string(restore_error))
		_remove_if_exists(TEMP_SAVE_PATH)
		push_error("Could not replace save file: %s" % error_string(replace_error))
		return false

	_remove_if_exists(BACKUP_SAVE_PATH)
	return true


func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("Could not open save file for reading: %s" % FileAccess.get_open_error())
		return {}

	var parser := JSON.new()
	var parse_result: Error = parser.parse(file.get_as_text())
	file.close()
	if parse_result != OK:
		push_error("Save file contains invalid JSON.")
		return {}

	var parsed: Variant = parser.data
	if not (parsed is Dictionary):
		push_error("Save file root must be a JSON object.")
		return {}

	var result: Dictionary = parsed
	var schema_version := int(result.get("_schema_version", 0))
	if schema_version < 0 or schema_version > SAVE_SCHEMA_VERSION:
		push_error("Unsupported save schema version: %d" % schema_version)
		return {}
	return result


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func delete_save() -> bool:
	var success := true
	for path in [SAVE_PATH, TEMP_SAVE_PATH, BACKUP_SAVE_PATH]:
		if FileAccess.file_exists(path) and not _remove_if_exists(path):
			success = false
	return success


func _remove_if_exists(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK
