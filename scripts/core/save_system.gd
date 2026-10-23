extends Node

const SAVE_PATH: String = "user://savegame.json"
const TEMP_SAVE_PATH: String = "user://savegame.json.tmp"
const BACKUP_SAVE_PATH: String = "user://savegame.json.bak"


func save_game(data: Dictionary) -> bool:
	var save_absolute := ProjectSettings.globalize_path(SAVE_PATH)
	var temp_absolute := ProjectSettings.globalize_path(TEMP_SAVE_PATH)
	var backup_absolute := ProjectSettings.globalize_path(BACKUP_SAVE_PATH)

	# Recover a valid backup before any new save can discard it.
	if not FileAccess.file_exists(SAVE_PATH) and FileAccess.file_exists(BACKUP_SAVE_PATH):
		if DirAccess.rename_absolute(backup_absolute, save_absolute) != OK:
			push_error("Could not recover backup save file.")
			return false
	elif FileAccess.file_exists(SAVE_PATH) and FileAccess.file_exists(BACKUP_SAVE_PATH):
		var primary_data: Variant = _read_save_file(SAVE_PATH)
		if primary_data is Dictionary:
			if DirAccess.remove_absolute(backup_absolute) != OK:
				push_error("Could not remove stale backup save file.")
				return false
		else:
			var backup_data: Variant = _read_save_file(BACKUP_SAVE_PATH)
			if not backup_data is Dictionary:
				push_error("Both primary and backup save files are invalid; refusing to discard either file.")
				return false
			if DirAccess.remove_absolute(save_absolute) != OK:
				push_error("Could not remove invalid primary save file.")
				return false
			if DirAccess.rename_absolute(backup_absolute, save_absolute) != OK:
				push_error("Could not restore valid backup save file.")
				return false

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
		DirAccess.remove_absolute(temp_absolute)
		push_error("Could not write complete temporary save file: %s" % error_string(write_error))
		return false

	# Keep the old save until the new file has been written successfully.
	var had_previous_save := FileAccess.file_exists(SAVE_PATH)
	if had_previous_save and DirAccess.rename_absolute(save_absolute, backup_absolute) != OK:
		DirAccess.remove_absolute(temp_absolute)
		push_error("Could not move existing save file to backup.")
		return false

	if DirAccess.rename_absolute(temp_absolute, save_absolute) != OK:
		if had_previous_save:
			DirAccess.rename_absolute(backup_absolute, save_absolute)
		push_error("Could not replace save file with the new save.")
		return false

	if FileAccess.file_exists(BACKUP_SAVE_PATH):
		DirAccess.remove_absolute(backup_absolute)
	return true


func load_game() -> Dictionary:
	var primary_data: Variant = _read_save_file(SAVE_PATH)
	if primary_data is Dictionary:
		return primary_data

	# A present but malformed primary file must not hide a valid backup.
	var backup_data: Variant = _read_save_file(BACKUP_SAVE_PATH)
	if not backup_data is Dictionary:
		return {}

	var save_absolute := ProjectSettings.globalize_path(SAVE_PATH)
	var backup_absolute := ProjectSettings.globalize_path(BACKUP_SAVE_PATH)
	if FileAccess.file_exists(SAVE_PATH):
		if DirAccess.remove_absolute(save_absolute) != OK:
			push_warning("Could not remove invalid primary save; using backup data in memory.")
			return backup_data
	if DirAccess.rename_absolute(backup_absolute, save_absolute) != OK:
		push_warning("Could not restore backup save file; using backup data in memory.")
	return backup_data


func _read_save_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Could not open save file for reading: %s" % path)
		return null

	var parser := JSON.new()
	var parse_result: Error = parser.parse(file.get_as_text())
	file.close()
	if parse_result != OK:
		push_warning("Save file contains invalid JSON: %s" % path)
		return null
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		push_warning("Save file root is not a Dictionary: %s" % path)
		return null
	return parsed


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(BACKUP_SAVE_PATH)


func delete_save() -> bool:
	for path in [SAVE_PATH, TEMP_SAVE_PATH, BACKUP_SAVE_PATH]:
		if FileAccess.file_exists(path):
			var absolute_path := ProjectSettings.globalize_path(path)
			if DirAccess.remove_absolute(absolute_path) != OK:
				push_error("Could not delete save-related file: %s" % path)
				return false
	return true
