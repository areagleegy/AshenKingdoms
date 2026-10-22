extends Node

const SAVE_PATH: String = "user://savegame.json"

const LOAD_STATUS_NOT_FOUND: String = "not_found"
const LOAD_STATUS_OK: String = "ok"
const LOAD_STATUS_INVALID_JSON: String = "invalid_json"
const LOAD_STATUS_INVALID_SCHEMA: String = "invalid_schema"
const LOAD_STATUS_READ_ERROR: String = "read_error"
const LOAD_STATUS_INVALID_SIZE: String = "invalid_size"
const LOAD_STATUS_RECOVERED_BACKUP: String = "recovered_backup"

# Tests may override this path to avoid touching the player's real save.
var save_path: String = SAVE_PATH
var last_load_status: String = LOAD_STATUS_NOT_FOUND

# Explicit fault-injection seams used by automated tests only.
# write_hook_for_testing(file, serialized_text) must return whether writing succeeded.
# rename_hook_for_testing(absolute_from, absolute_to) must return an Error code.
var write_hook_for_testing: Callable = Callable()
var rename_hook_for_testing: Callable = Callable()


func save_game(data: Dictionary) -> bool:
	var serialized := JSON.stringify(data, "\t")
	if serialized.to_utf8_buffer().size() > MAX_SAVE_BYTES:
		push_error("Save data exceeds the maximum allowed size.")
		return false
	var serialized_parser := JSON.new()
	if serialized_parser.parse(serialized) != OK or not (serialized_parser.data is Dictionary):
		push_error("Refusing to save data that cannot be represented as a JSON object.")
		return false

	var temporary_path := save_path + ".tmp"
	_remove_file_if_exists(temporary_path)

	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not open temporary save file for writing: %s" % FileAccess.get_open_error())
		return false

	var write_ok := false
	if write_hook_for_testing.is_valid():
		write_ok = bool(write_hook_for_testing.call(file, serialized))
	else:
		write_ok = file.store_string(serialized)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()

	if not write_ok or write_error != OK:
		push_error("Writing the temporary save failed (store_string=%s, error=%s)." % [str(write_ok), error_string(write_error)])
		_remove_file_if_exists(temporary_path)
		return false

	if not bool(_read_save_file(temporary_path).get("ok", false)):
		push_error("Temporary save did not contain a valid JSON object.")
		_remove_file_if_exists(temporary_path)
		return false

	var current_state := _read_save_file(save_path)
	if FileAccess.file_exists(save_path):
		if bool(current_state.get("ok", false)):
			# Keep a verified copy of the previous valid save before replacing it.
			if not _stage_backup_from_current():
				push_error("Could not stage a verified backup; the existing save was left untouched.")
				_remove_file_if_exists(temporary_path)
				return false
		elif str(current_state.get("status", "")) not in [LOAD_STATUS_INVALID_JSON, LOAD_STATUS_INVALID_SCHEMA]:
			# A read/open error is not evidence that the primary save is corrupt.
			push_error("Could not verify the current save before replacement.")
			_remove_file_if_exists(temporary_path)
			return false

	# This replacement is not guaranteed to be atomic on every platform/filesystem.
	# The verified .bak file is the recovery mechanism, not an atomic-rename guarantee.
	var rename_error: Error = _rename_path(_absolute_path(temporary_path), _absolute_path(save_path))
	if rename_error != OK:
		push_error("Could not replace the save file: %s" % error_string(rename_error))
		_remove_file_if_exists(temporary_path)
		if not bool(current_state.get("ok", false)) and bool(_read_save_file(_backup_path()).get("ok", false)):
			_restore_backup_to_primary()
		return false

	var final_state := _read_save_file(save_path)
	if not bool(final_state.get("ok", false)):
		push_error("The final save failed verification; attempting backup recovery.")
		if not _restore_backup_to_primary():
			push_error("Backup recovery failed; the backup file was preserved for manual recovery.")
		return false

	last_load_status = LOAD_STATUS_OK
	return true


func load_game() -> Dictionary:
	var primary := _read_save_file(save_path)
	if bool(primary.get("ok", false)):
		last_load_status = LOAD_STATUS_OK
		var primary_data: Variant = primary.get("data", {})
		return primary_data if primary_data is Dictionary else {}

	var backup := _read_save_file(_backup_path())
	if bool(backup.get("ok", false)):
		last_load_status = LOAD_STATUS_RECOVERED_BACKUP
		if not _restore_backup_to_primary():
			push_warning("Loaded the valid backup, but could not restore the primary save file.")
		var backup_data: Variant = backup.get("data", {})
		return backup_data if backup_data is Dictionary else {}

	if str(primary.get("status", "")) == LOAD_STATUS_NOT_FOUND:
		last_load_status = str(backup.get("status", LOAD_STATUS_NOT_FOUND))
	else:
		last_load_status = str(primary.get("status", LOAD_STATUS_READ_ERROR))
	return {}


func has_save() -> bool:
	return bool(_read_save_file(save_path).get("ok", false)) or bool(_read_save_file(_backup_path()).get("ok", false))


func delete_save() -> bool:
	var paths: Array[String] = [
		save_path,
		save_path + ".tmp",
		_backup_path(),
		_backup_temporary_path(),
		_restore_temporary_path()
	]
	var success := true
	for path in paths:
		if not _remove_file_if_exists(path):
			success = false
	last_load_status = LOAD_STATUS_NOT_FOUND
	return success


func _read_save_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "status": LOAD_STATUS_NOT_FOUND, "data": {}}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "status": LOAD_STATUS_READ_ERROR, "data": {}}
	if file.get_length() <= 0 or file.get_length() > MAX_SAVE_BYTES:
		file.close()
		return {"ok": false, "status": LOAD_STATUS_INVALID_SIZE, "data": {}}

	var text := file.get_as_text()
	file.close()

	var parser := JSON.new()
	var parse_result: Error = parser.parse(text)
	if parse_result != OK:
		return {"ok": false, "status": LOAD_STATUS_INVALID_JSON, "data": {}}

	var parsed: Variant = parser.data
	if not (parsed is Dictionary):
		return {"ok": false, "status": LOAD_STATUS_INVALID_SCHEMA, "data": {}}
	return {"ok": true, "status": LOAD_STATUS_OK, "data": parsed}


func _stage_backup_from_current() -> bool:
	if not bool(_read_save_file(save_path).get("ok", false)):
		return false

	var backup_temporary := _backup_temporary_path()
	_remove_file_if_exists(backup_temporary)
	var copy_error: Error = DirAccess.copy_absolute(_absolute_path(save_path), _absolute_path(backup_temporary))
	if copy_error != OK:
		_remove_file_if_exists(backup_temporary)
		return false
	if not bool(_read_save_file(backup_temporary).get("ok", false)):
		_remove_file_if_exists(backup_temporary)
		return false

	var rename_error: Error = _rename_path(_absolute_path(backup_temporary), _absolute_path(_backup_path()))
	if rename_error != OK:
		_remove_file_if_exists(backup_temporary)
		return false
	return bool(_read_save_file(_backup_path()).get("ok", false))


func _restore_backup_to_primary() -> bool:
	if not bool(_read_save_file(_backup_path()).get("ok", false)):
		return false

	var restore_temporary := _restore_temporary_path()
	_remove_file_if_exists(restore_temporary)
	var copy_error: Error = DirAccess.copy_absolute(_absolute_path(_backup_path()), _absolute_path(restore_temporary))
	if copy_error != OK:
		_remove_file_if_exists(restore_temporary)
		return false
	if not bool(_read_save_file(restore_temporary).get("ok", false)):
		_remove_file_if_exists(restore_temporary)
		return false

	var rename_error: Error = _rename_path(_absolute_path(restore_temporary), _absolute_path(save_path))
	if rename_error != OK:
		_remove_file_if_exists(restore_temporary)
		return false
	return bool(_read_save_file(save_path).get("ok", false))


func _rename_path(from_path: String, to_path: String) -> Error:
	if rename_hook_for_testing.is_valid():
		return int(rename_hook_for_testing.call(from_path, to_path))
	return DirAccess.rename_absolute(from_path, to_path)


func _remove_file_if_exists(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(_absolute_path(path)) == OK


func _absolute_path(path: String) -> String:
	return ProjectSettings.globalize_path(path)


func _backup_path() -> String:
	return save_path + ".bak"


func _backup_temporary_path() -> String:
	return save_path + ".bak.tmp"


func _restore_temporary_path() -> String:
	return save_path + ".restore.tmp"
