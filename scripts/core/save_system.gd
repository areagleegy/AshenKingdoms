extends Node
## Defensive local save storage for Android. Public methods remain backward-compatible.

const SAVE_PATH: String = "user://savegame.json"
const TEMP_PATH: String = "user://savegame.tmp"
const BACKUP_PATH: String = "user://savegame.bak.json"
const MAX_SAVE_BYTES: int = 1_048_576


func save_game(data: Dictionary) -> bool:
	var serialized := JSON.stringify(data, "\t")
	if serialized.to_utf8_buffer().size() > MAX_SAVE_BYTES:
		push_error("Save rejected: serialized data exceeds the maximum size.")
		return false

	var temp_file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if temp_file == null:
		push_error("Could not open temporary save file: %s" % error_string(FileAccess.get_open_error()))
		return false
	temp_file.store_string(serialized)
	temp_file.flush()
	var write_error: Error = temp_file.get_error()
	temp_file.close()
	if write_error != OK:
		_remove_if_exists(TEMP_PATH)
		push_error("Could not write temporary save file: %s" % error_string(write_error))
		return false

	var save_absolute := ProjectSettings.globalize_path(SAVE_PATH)
	var temp_absolute := ProjectSettings.globalize_path(TEMP_PATH)
	var backup_absolute := ProjectSettings.globalize_path(BACKUP_PATH)
	var had_previous_save := FileAccess.file_exists(SAVE_PATH)

	if had_previous_save:
		_remove_if_exists(BACKUP_PATH)
		var backup_error: Error = DirAccess.rename_absolute(save_absolute, backup_absolute)
		if backup_error != OK:
			_remove_if_exists(TEMP_PATH)
			push_error("Could not rotate current save to backup: %s" % error_string(backup_error))
			return false

	var promote_error: Error = DirAccess.rename_absolute(temp_absolute, save_absolute)
	if promote_error != OK:
		if had_previous_save and FileAccess.file_exists(BACKUP_PATH):
			DirAccess.rename_absolute(backup_absolute, save_absolute)
		_remove_if_exists(TEMP_PATH)
		push_error("Could not promote temporary save: %s" % error_string(promote_error))
		return false
	return true


func load_game() -> Dictionary:
	var primary := _read_save(SAVE_PATH)
	if bool(primary.get("valid", false)):
		return primary.get("data", {}) as Dictionary

	var backup := _read_save(BACKUP_PATH)
	if bool(backup.get("valid", false)):
		var backup_data: Dictionary = backup.get("data", {})
		if _restore_backup():
			push_warning("Primary save was invalid; recovered backup save.")
		else:
			push_warning("Loaded backup save, but could not restore the primary file.")
		return backup_data

	if bool(primary.get("exists", false)) or bool(backup.get("exists", false)):
		push_warning("Save data is invalid or unreadable; returning an empty save.")
	return {}


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(BACKUP_PATH)


func delete_save() -> bool:
	var ok := true
	for path in [SAVE_PATH, TEMP_PATH, BACKUP_PATH]:
		if not _remove_if_exists(path):
			ok = false
	return ok


func _read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"exists": false, "valid": false, "data": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"exists": true, "valid": false, "data": {}}
	if file.get_length() <= 0 or file.get_length() > MAX_SAVE_BYTES:
		file.close()
		return {"exists": true, "valid": false, "data": {}}
	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return {"exists": true, "valid": false, "data": {}}
	return {"exists": true, "valid": true, "data": parser.data}


func _restore_backup() -> bool:
	var save_absolute := ProjectSettings.globalize_path(SAVE_PATH)
	var backup_absolute := ProjectSettings.globalize_path(BACKUP_PATH)
	_remove_if_exists(SAVE_PATH)
	return DirAccess.copy_absolute(backup_absolute, save_absolute) == OK


func _remove_if_exists(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK
