extends Node

const SAVE_PATH: String = "user://savegame.json"
const TEMP_SAVE_PATH: String = "user://savegame.json.tmp"
const BACKUP_SAVE_PATH: String = "user://savegame.json.bak"


func save_game(data: Dictionary) -> bool:
	# Write a complete candidate first; never truncate the last known-good save.
	var temporary_file := FileAccess.open(TEMP_SAVE_PATH, FileAccess.WRITE)
	if temporary_file == null:
		push_error("Could not open temporary save file: %s" % FileAccess.get_open_error())
		return false

	temporary_file.store_string(JSON.stringify(data, "\t"))
	temporary_file.flush()
	var write_error: Error = temporary_file.get_error()
	temporary_file.close()
	if write_error != OK:
		push_error("Could not finish writing temporary save file: %s" % error_string(write_error))
		_remove_if_exists(TEMP_SAVE_PATH)
		return false

	var save_absolute := ProjectSettings.globalize_path(SAVE_PATH)
	var temp_absolute := ProjectSettings.globalize_path(TEMP_SAVE_PATH)
	var backup_absolute := ProjectSettings.globalize_path(BACKUP_SAVE_PATH)
	var had_previous_save := FileAccess.file_exists(SAVE_PATH)

	if FileAccess.file_exists(BACKUP_SAVE_PATH) and not _remove_if_exists(BACKUP_SAVE_PATH):
		push_error("Could not clear stale save backup.")
		_remove_if_exists(TEMP_SAVE_PATH)
		return false

	if had_previous_save:
		var backup_error: Error = DirAccess.rename_absolute(save_absolute, backup_absolute)
		if backup_error != OK:
			push_error("Could not protect previous save before replacement: %s" % error_string(backup_error))
			_remove_if_exists(TEMP_SAVE_PATH)
			return false

	var replace_error: Error = DirAccess.rename_absolute(temp_absolute, save_absolute)
	if replace_error != OK:
		push_error("Could not install new save: %s" % error_string(replace_error))
		if had_previous_save:
			var rollback_error: Error = DirAccess.rename_absolute(backup_absolute, save_absolute)
			if rollback_error != OK:
				push_error("CRITICAL: save rollback failed: %s" % error_string(rollback_error))
		_remove_if_exists(TEMP_SAVE_PATH)
		return false

	if had_previous_save and not _remove_if_exists(BACKUP_SAVE_PATH):
		# The new save is valid; retain the backup for recovery if cleanup fails.
		push_warning("New save was written, but the previous save backup could not be removed.")
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
		push_warning("Save file contains invalid JSON; refusing to load it.")
		return {}
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		push_warning("Save file root must be a JSON object; refusing to load it.")
		return {}
	return parsed


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func delete_save() -> bool:
	var paths: Array[String] = [SAVE_PATH, TEMP_SAVE_PATH, BACKUP_SAVE_PATH]
	for path in paths:
		if not _remove_if_exists(path):
			return false
	return true


func _remove_if_exists(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	var absolute_path := ProjectSettings.globalize_path(path)
	return DirAccess.remove_absolute(absolute_path) == OK
