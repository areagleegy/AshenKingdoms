extends Node

const SAVE_PATH: String = "user://savegame.json"
const TEMP_SAVE_PATH: String = "user://savegame.json.tmp"
const BACKUP_SAVE_PATH: String = "user://savegame.json.bak"
const SAVE_SCHEMA_VERSION: int = 1


func save_game(data: Dictionary) -> bool:
	var payload := data.duplicate(true)
	payload["schema_version"] = SAVE_SCHEMA_VERSION
	var json_text := JSON.stringify(payload, "\t")
	if json_text.is_empty():
		push_error("Could not serialize save data.")
		return false

	var file := FileAccess.open(TEMP_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not open temporary save file: %s" % FileAccess.get_open_error())
		return false

	file.store_string(json_text)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		push_error("Could not write temporary save file: %s" % error_string(write_error))
		_remove_if_exists(TEMP_SAVE_PATH)
		return false

	var save_absolute := ProjectSettings.globalize_path(SAVE_PATH)
	var temp_absolute := ProjectSettings.globalize_path(TEMP_SAVE_PATH)
	var backup_absolute := ProjectSettings.globalize_path(BACKUP_SAVE_PATH)
	var had_previous_save := FileAccess.file_exists(SAVE_PATH)

	if had_previous_save:
		_remove_if_exists(BACKUP_SAVE_PATH)
		var backup_error := DirAccess.rename_absolute(save_absolute, backup_absolute)
		if backup_error != OK:
			push_error("Could not back up existing save: %s" % error_string(backup_error))
			_remove_if_exists(TEMP_SAVE_PATH)
			return false

	var install_error := DirAccess.rename_absolute(temp_absolute, save_absolute)
	if install_error != OK:
		push_error("Could not install new save: %s" % error_string(install_error))
		if had_previous_save and FileAccess.file_exists(BACKUP_SAVE_PATH):
			var restore_error := DirAccess.rename_absolute(backup_absolute, save_absolute)
			if restore_error != OK:
				push_error("Could not restore backup save: %s" % error_string(restore_error))
		_remove_if_exists(TEMP_SAVE_PATH)
		return false

	return true


func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return _load_backup_if_available()

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("Could not open save file for reading: %s" % FileAccess.get_open_error())
		return _load_backup_if_available()

	var parser := JSON.new()
	var parse_result: Error = parser.parse(file.get_as_text())
	file.close()
	if parse_result != OK or not (parser.data is Dictionary):
		push_error("Save file contains invalid JSON or is not a dictionary.")
		return _load_backup_if_available()

	var parsed: Dictionary = parser.data
	if not _has_supported_schema(parsed):
		push_error("Save file schema version is unsupported.")
		return _load_backup_if_available()

	return parsed


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(BACKUP_SAVE_PATH)


func delete_save() -> bool:
	var success := true
	for path in [SAVE_PATH, TEMP_SAVE_PATH, BACKUP_SAVE_PATH]:
		if FileAccess.file_exists(path):
			var absolute_path := ProjectSettings.globalize_path(path)
			if DirAccess.remove_absolute(absolute_path) != OK:
				success = false
	return success


func _load_backup_if_available() -> Dictionary:
	if not FileAccess.file_exists(BACKUP_SAVE_PATH):
		return {}
	var backup := FileAccess.open(BACKUP_SAVE_PATH, FileAccess.READ)
	if backup == null:
		push_error("Could not open backup save file: %s" % FileAccess.get_open_error())
		return {}
	var parser := JSON.new()
	var parse_result: Error = parser.parse(backup.get_as_text())
	backup.close()
	if parse_result != OK or not (parser.data is Dictionary):
		push_error("Backup save file is invalid.")
		return {}
	var parsed: Dictionary = parser.data
	if not _has_supported_schema(parsed):
		push_error("Backup save schema version is unsupported.")
		return {}
	return parsed


func _has_supported_schema(data: Dictionary) -> bool:
	# Godot's JSON parser may represent JSON numbers as integers or floats.
	# Accept both numeric representations, but only integral finite versions.
	var schema_value: Variant = data.get("schema_version", 0)
	var schema_version: int
	match typeof(schema_value):
		TYPE_INT:
			schema_version = int(schema_value)
		TYPE_FLOAT:
			var numeric_version := float(schema_value)
			if not is_finite(numeric_version) or numeric_version != floorf(numeric_version):
				return false
			schema_version = int(numeric_version)
		_:
			return false
	return schema_version >= 0 and schema_version <= SAVE_SCHEMA_VERSION


func _remove_if_exists(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var absolute_path := ProjectSettings.globalize_path(path)
	var error := DirAccess.remove_absolute(absolute_path)
	if error != OK:
		push_warning("Could not remove temporary file %s: %s" % [path, error_string(error)])
