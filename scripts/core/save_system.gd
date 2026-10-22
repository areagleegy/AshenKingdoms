extends Node

## Save files are local user data, so keep the existing public API stable.
const SAVE_PATH: String = "user://savegame.json"
const BACKUP_PATH: String = "user://savegame.bak.json"
const TEMP_PATH: String = "user://savegame.tmp"
const BACKUP_TEMP_PATH: String = "user://savegame.bak.tmp"
const MAX_SAVE_SIZE: int = 1_048_576


func save_game(data: Dictionary) -> bool:
	var serialized := JSON.stringify(data, "\t")
	if serialized.is_empty() or serialized.to_utf8_buffer().size() > MAX_SAVE_SIZE:
		push_error("Save data is empty or exceeds the maximum allowed size.")
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
		push_error("Failed while writing temporary save file: %s" % error_string(write_error))
		return false

	# Preserve the last known save before replacing it. If promotion of the new
	# file fails, restore the previous file instead of leaving no primary save.
	var had_primary := FileAccess.file_exists(SAVE_PATH)
	if had_primary:
		var backup_error := DirAccess.copy_absolute(
			ProjectSettings.globalize_path(SAVE_PATH),
			ProjectSettings.globalize_path(BACKUP_PATH)
		)
		if backup_error != OK:
			_remove_if_exists(TEMP_PATH)
			push_error("Could not back up the previous save: %s" % error_string(backup_error))
			return false

	if had_primary:
		var move_old_error := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(SAVE_PATH),
			ProjectSettings.globalize_path(SAVE_PATH + ".old")
		)
		if move_old_error != OK:
			_remove_if_exists(TEMP_PATH)
			push_error("Could not stage the previous save: %s" % error_string(move_old_error))
			return false

	var promote_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(TEMP_PATH),
		ProjectSettings.globalize_path(SAVE_PATH)
	)
	if promote_error != OK:
		var staged_path := SAVE_PATH + ".old"
		if FileAccess.file_exists(staged_path):
			DirAccess.rename_absolute(
				ProjectSettings.globalize_path(staged_path),
				ProjectSettings.globalize_path(SAVE_PATH)
			)
		_remove_if_exists(TEMP_PATH)
		push_error("Could not activate the new save: %s" % error_string(promote_error))
		return false

	_remove_if_exists(SAVE_PATH + ".old")
	return true


func load_game() -> Dictionary:
	var primary := _read_dictionary(SAVE_PATH)
	if bool(primary.get("ok", false)):
		return primary.get("data", {}) as Dictionary

	var backup := _read_dictionary(BACKUP_PATH)
	if bool(backup.get("ok", false)):
		push_warning("Primary save is missing or invalid; recovered data from backup.")
		return backup.get("data", {}) as Dictionary

	if FileAccess.file_exists(SAVE_PATH):
		push_error("Save file is invalid and no usable backup was found.")
	return {}


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(BACKUP_PATH)


func delete_save() -> bool:
	var ok := true
	for path in [SAVE_PATH, BACKUP_PATH, TEMP_PATH, BACKUP_TEMP_PATH, SAVE_PATH + ".old"]:
		if not _remove_if_exists(path):
			ok = false
	return ok


func _read_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "missing"}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "open_failed"}

	if file.get_length() <= 0 or file.get_length() > MAX_SAVE_SIZE:
		file.close()
		return {"ok": false, "reason": "invalid_size"}

	var parser := JSON.new()
	var parse_result: Error = parser.parse(file.get_as_text())
	file.close()
	if parse_result != OK:
		return {"ok": false, "reason": "invalid_json"}

	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		return {"ok": false, "reason": "invalid_root"}

	return {"ok": true, "data": parsed}


func _remove_if_exists(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK
