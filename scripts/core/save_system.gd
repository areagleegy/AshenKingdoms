extends Node

const SAVE_PATH: String = "user://savegame.json"
const TEMP_PATH: String = "user://savegame.json.tmp"
const BACKUP_PATH: String = "user://savegame.json.bak"


func save_game(data: Dictionary) -> bool:
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not open temporary save file: %s" % FileAccess.get_open_error())
		return false

	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		push_error("Could not write temporary save file: %s" % error_string(write_error))
		_remove_file(TEMP_PATH)
		return false

	var save_absolute := ProjectSettings.globalize_path(SAVE_PATH)
	var temp_absolute := ProjectSettings.globalize_path(TEMP_PATH)
	var backup_absolute := ProjectSettings.globalize_path(BACKUP_PATH)
	var had_previous_save := FileAccess.file_exists(SAVE_PATH)

	if FileAccess.file_exists(BACKUP_PATH) and DirAccess.remove_absolute(backup_absolute) != OK:
		push_error("Could not remove stale save backup.")
		_remove_file(TEMP_PATH)
		return false

	if had_previous_save:
		var backup_error: Error = DirAccess.rename_absolute(save_absolute, backup_absolute)
		if backup_error != OK:
			push_error("Could not back up existing save: %s" % error_string(backup_error))
			_remove_file(TEMP_PATH)
			return false

	var replace_error: Error = DirAccess.rename_absolute(temp_absolute, save_absolute)
	if replace_error != OK:
		push_error("Could not replace save file: %s" % error_string(replace_error))
		if had_previous_save:
			var restore_error: Error = DirAccess.rename_absolute(backup_absolute, save_absolute)
			if restore_error != OK:
				push_error("Could not restore previous save: %s" % error_string(restore_error))
		_remove_file(TEMP_PATH)
		return false

	if FileAccess.file_exists(BACKUP_PATH):
		var cleanup_error: Error = DirAccess.remove_absolute(backup_absolute)
		if cleanup_error != OK:
			push_warning("Save succeeded, but the backup could not be removed.")
	return true


func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		if FileAccess.file_exists(BACKUP_PATH):
			var recovery_error: Error = DirAccess.rename_absolute(
				ProjectSettings.globalize_path(BACKUP_PATH),
				ProjectSettings.globalize_path(SAVE_PATH)
			)
			if recovery_error != OK:
				push_error("Could not restore save backup: %s" % error_string(recovery_error))
				return {}
			push_warning("Recovered save file from backup.")
		else:
			return {}

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("Could not open save file for reading: %s" % FileAccess.get_open_error())
		return {}

	var parser := JSON.new()
	var parse_result: Error = parser.parse(file.get_as_text())
	file.close()
	if parse_result != OK:
		push_error("Save file contains invalid JSON at line %d: %s" % [parser.get_error_line(), parser.get_error_message()])
		return {}

	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		push_error("Save file root must be a JSON object.")
		return {}
	return parsed


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(BACKUP_PATH)


func delete_save() -> bool:
	var success := true
	for path in [SAVE_PATH, TEMP_PATH, BACKUP_PATH]:
		if FileAccess.file_exists(path) and _remove_file(path) != OK:
			success = false
	return success


func _remove_file(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
