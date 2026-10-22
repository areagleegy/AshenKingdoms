extends Node

const SAVE_PATH: String = "user://savegame.json"
const TEMP_PATH: String = "user://savegame.json.tmp"
const BACKUP_PATH: String = "user://savegame.json.bak"
const MAX_SAVE_BYTES: int = 1024 * 1024


func save_game(data: Dictionary) -> bool:
	var serialized := JSON.stringify(data, "\t")
	if serialized.to_utf8_buffer().size() > MAX_SAVE_BYTES:
		push_error("Refusing to save data larger than the local save-size limit.")
		return false
	var validator := JSON.new()
	if validator.parse(serialized) != OK or not (validator.data is Dictionary):
		push_error("Refusing to write save data that does not round-trip as a JSON object.")
		return false

	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not open temporary save file for writing: %s" % FileAccess.get_open_error())
		return false

	file.store_string(serialized)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		_remove_file_if_exists(TEMP_PATH)
		push_error("Could not flush temporary save file: %s" % error_string(write_error))
		return false

	# Preserve the last known-good save before replacing it. A corrupt primary
	# must never overwrite a valid backup.
	var current := _read_dictionary_file(SAVE_PATH)
	if bool(current.get("valid", false)):
		var backup_error := DirAccess.copy_absolute(
			ProjectSettings.globalize_path(SAVE_PATH),
			ProjectSettings.globalize_path(BACKUP_PATH)
		)
		if backup_error != OK:
			_remove_file_if_exists(TEMP_PATH)
			push_error("Could not preserve the previous save: %s" % error_string(backup_error))
			return false

	var replace_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(TEMP_PATH),
		ProjectSettings.globalize_path(SAVE_PATH)
	)
	if replace_error != OK:
		_remove_file_if_exists(TEMP_PATH)
		push_error("Could not commit the new save file: %s" % error_string(replace_error))
		return false

	return true


func load_game() -> Dictionary:
	var primary := _read_dictionary_file(SAVE_PATH)
	if bool(primary.get("valid", false)):
		return primary.get("data", {})

	# A valid temp snapshot is the newest write that was flushed before a crash.
	# Prefer it over the older backup, but only after verifying the JSON object.
	var temporary := _read_dictionary_file(TEMP_PATH)
	if bool(temporary.get("valid", false)):
		push_warning("Primary save is missing or invalid; recovered the flushed temporary snapshot.")
		var temp_restore_error := DirAccess.copy_absolute(
			ProjectSettings.globalize_path(TEMP_PATH),
			ProjectSettings.globalize_path(SAVE_PATH)
		)
		if temp_restore_error == OK:
			_remove_file_if_exists(TEMP_PATH)
		else:
			push_warning("Recovered temporary save in memory, but could not restore the primary file: %s" % error_string(temp_restore_error))
		return temporary.get("data", {})

	var backup := _read_dictionary_file(BACKUP_PATH)
	if bool(backup.get("valid", false)):
		push_warning("Primary save is missing or invalid; recovered the last known-good backup.")
		var restore_error := DirAccess.copy_absolute(
			ProjectSettings.globalize_path(BACKUP_PATH),
			ProjectSettings.globalize_path(SAVE_PATH)
		)
		if restore_error != OK:
			push_warning("Recovered save in memory, but could not restore the primary file: %s" % error_string(restore_error))
		return backup.get("data", {})

	return {}


func has_save() -> bool:
	return (
		bool(_read_dictionary_file(SAVE_PATH).get("valid", false))
		or bool(_read_dictionary_file(TEMP_PATH).get("valid", false))
		or bool(_read_dictionary_file(BACKUP_PATH).get("valid", false))
	)


func delete_save() -> bool:
	var succeeded := true
	for path in [SAVE_PATH, TEMP_PATH, BACKUP_PATH]:
		if not FileAccess.file_exists(path):
			continue
		var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if remove_error != OK:
			push_error("Could not remove save-related file %s: %s" % [path, error_string(remove_error)])
			succeeded = false
	return succeeded


func _read_dictionary_file(path: String) -> Dictionary:
	var result: Dictionary = {"valid": false, "data": {}}
	if not FileAccess.file_exists(path):
		return result

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return result
	if file.get_length() <= 0 or file.get_length() > MAX_SAVE_BYTES:
		file.close()
		return result

	var parser := JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not (parser.data is Dictionary):
		return result

	result["valid"] = true
	result["data"] = parser.data
	return result


func _remove_file_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if remove_error != OK:
			push_warning("Could not remove temporary file %s: %s" % [path, error_string(remove_error)])
