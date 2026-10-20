extends Node

const SAVE_PATH: String = "user://savegame.json"
const TEMP_SAVE_PATH: String = "user://savegame.json.tmp"
const BACKUP_SAVE_PATH: String = "user://savegame.json.bak"


func save_game(data: Dictionary) -> bool:
	var temp_absolute := ProjectSettings.globalize_path(TEMP_SAVE_PATH)
	var save_absolute := ProjectSettings.globalize_path(SAVE_PATH)
	var backup_absolute := ProjectSettings.globalize_path(BACKUP_SAVE_PATH)

	if FileAccess.file_exists(TEMP_SAVE_PATH):
		if DirAccess.remove_absolute(temp_absolute) != OK:
			push_error("Could not remove stale temporary save file.")
			return false

	var file := FileAccess.open(TEMP_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not open temporary save file for writing: %s" % FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		_remove_file_if_present(TEMP_SAVE_PATH)
		push_error("Could not finish writing temporary save file: %s" % error_string(write_error))
		return false

	var verified: Variant = _read_save_data(TEMP_SAVE_PATH)
	if not verified is Dictionary:
		_remove_file_if_present(TEMP_SAVE_PATH)
		push_error("Temporary save file failed JSON validation.")
		return false

	var had_save := FileAccess.file_exists(SAVE_PATH)
	if had_save and FileAccess.file_exists(BACKUP_SAVE_PATH):
		if DirAccess.remove_absolute(backup_absolute) != OK:
			_remove_file_if_present(TEMP_SAVE_PATH)
			push_error("Could not remove stale backup save file.")
			return false

	if had_save and DirAccess.rename_absolute(save_absolute, backup_absolute) != OK:
		_remove_file_if_present(TEMP_SAVE_PATH)
		push_error("Could not preserve the previous save file.")
		return false

	if DirAccess.rename_absolute(temp_absolute, save_absolute) != OK:
		if had_save:
			var rollback_error: Error = DirAccess.rename_absolute(backup_absolute, save_absolute)
			if rollback_error != OK:
				push_error("Save replacement failed and rollback also failed: %s" % error_string(rollback_error))
		_remove_file_if_present(TEMP_SAVE_PATH)
		push_error("Could not install the new save file.")
		return false

	if FileAccess.file_exists(BACKUP_SAVE_PATH):
		if DirAccess.remove_absolute(backup_absolute) != OK:
			push_warning("New save was written, but the backup file could not be removed.")
	return true


func load_game() -> Dictionary:
	var primary: Variant = _read_save_data(SAVE_PATH)
	if primary is Dictionary:
		return primary

	# A backup can remain if the app stops during replacement.
	var backup: Variant = _read_save_data(BACKUP_SAVE_PATH)
	if backup is Dictionary:
		push_warning("Primary save is invalid or missing; loaded the backup save.")
		return backup
	return {}


func _read_save_data(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parser := JSON.new()
	var parse_result: Error = parser.parse(file.get_as_text())
	file.close()
	if parse_result != OK:
		return null
	var parsed: Variant = parser.data
	return parsed if parsed is Dictionary else null


func _remove_file_if_present(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func delete_save() -> bool:
	var save_removed := _remove_file_if_present(SAVE_PATH)
	var temp_removed := _remove_file_if_present(TEMP_SAVE_PATH)
	var backup_removed := _remove_file_if_present(BACKUP_SAVE_PATH)
	return save_removed and temp_removed and backup_removed
