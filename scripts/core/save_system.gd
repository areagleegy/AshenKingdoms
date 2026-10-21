extends Node

const SAVE_PATH: String = "user://savegame.json"
const TEMP_SAVE_PATH: String = "user://savegame.json.tmp"
const BACKUP_SAVE_PATH: String = "user://savegame.json.bak"


func save_game(data: Dictionary) -> bool:
	var save_absolute := ProjectSettings.globalize_path(SAVE_PATH)
	var temp_absolute := ProjectSettings.globalize_path(TEMP_SAVE_PATH)
	var backup_absolute := ProjectSettings.globalize_path(BACKUP_SAVE_PATH)

	# Recover the previous save if the app stopped during a replacement.
	if not FileAccess.file_exists(SAVE_PATH) and FileAccess.file_exists(BACKUP_SAVE_PATH):
		if DirAccess.rename_absolute(backup_absolute, save_absolute) != OK:
			push_error("Could not recover backup save file.")
			return false
	elif FileAccess.file_exists(SAVE_PATH) and FileAccess.file_exists(BACKUP_SAVE_PATH):
		DirAccess.remove_absolute(backup_absolute)

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
		push_warning("Save file contains invalid JSON; returning an empty save.")
		return {}
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		push_warning("Save file root is not a Dictionary; returning an empty save.")
		return {}
	return parsed


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func delete_save() -> bool:
	var save_absolute := ProjectSettings.globalize_path(SAVE_PATH)
	var temp_absolute := ProjectSettings.globalize_path(TEMP_SAVE_PATH)
	var backup_absolute := ProjectSettings.globalize_path(BACKUP_SAVE_PATH)
	for path in [SAVE_PATH, TEMP_SAVE_PATH, BACKUP_SAVE_PATH]:
		if FileAccess.file_exists(path):
			var absolute_path := ProjectSettings.globalize_path(path)
			if DirAccess.remove_absolute(absolute_path) != OK:
				push_error("Could not delete save-related file: %s" % path)
				return false
	return true
