extends Node

## Local save storage with bounded reads, a validated temporary file, and backup recovery.
## The public save_game/load_game API stays compatible with existing gameplay callers.
const SAVE_PATH: String = "user://savegame.json"
const BACKUP_PATH: String = "user://savegame.bak.json"
const TEMP_PATH: String = "user://savegame.tmp"
const BACKUP_TEMP_PATH: String = "user://savegame.bak.tmp"
const STAGED_PATH: String = "user://savegame.json.old"
const MAX_SAVE_SIZE: int = 1_048_576


func save_game(data: Dictionary) -> bool:
	var serialized := JSON.stringify(data, "\t")
	if serialized.is_empty() or serialized.to_utf8_buffer().size() > MAX_SAVE_SIZE:
		push_error("Save data is empty or exceeds the maximum allowed size.")
		return false

	if not _remove_if_exists(TEMP_PATH):
		push_error("Could not clear the stale temporary save file.")
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

	var temp_check := _read_dictionary(TEMP_PATH)
	if not bool(temp_check.get("ok", false)) or temp_check.get("data", {}) != data:
		_remove_if_exists(TEMP_PATH)
		push_error("Temporary save failed JSON/dictionary verification.")
		return false

	# Rotate only a verified primary save into the backup. A corrupt primary
	# must never overwrite a previously valid backup with corrupt bytes.
	var had_primary := FileAccess.file_exists(SAVE_PATH)
	var primary_check := _read_dictionary(SAVE_PATH)
	if had_primary and bool(primary_check.get("ok", false)):
		if not _refresh_backup_from_primary(primary_check.get("data", {}) as Dictionary):
			_remove_if_exists(TEMP_PATH)
			return false

	# A staged file may be the only remaining copy after an interrupted save.
	# Discard it only when a verified primary and backup make it redundant.
	if FileAccess.file_exists(STAGED_PATH):
		var staged_check := _read_dictionary(STAGED_PATH)
		var backup_check := _read_dictionary(BACKUP_PATH)
		var primary_is_valid := bool(primary_check.get("ok", false))
		var backup_is_valid := bool(backup_check.get("ok", false))
		if primary_is_valid and backup_is_valid:
			if not _remove_if_exists(STAGED_PATH):
				_remove_if_exists(TEMP_PATH)
				push_error("Could not clear a redundant staged save.")
				return false
		elif bool(staged_check.get("ok", false)) and had_primary:
			_remove_if_exists(TEMP_PATH)
			push_error("A valid staged save needs recovery; refusing to overwrite it.")
			return false
		elif not bool(staged_check.get("ok", false)) and not _remove_if_exists(STAGED_PATH):
			_remove_if_exists(TEMP_PATH)
			push_error("Could not clear an invalid staged save.")
			return false

	if had_primary:
		var move_old_error := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(SAVE_PATH),
			ProjectSettings.globalize_path(STAGED_PATH)
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
		if had_primary and FileAccess.file_exists(STAGED_PATH):
			var restore_error := DirAccess.rename_absolute(
				ProjectSettings.globalize_path(STAGED_PATH),
				ProjectSettings.globalize_path(SAVE_PATH)
			)
			if restore_error != OK:
				push_error(
					"CRITICAL: save promotion failed (%s) and restoring the previous save failed (%s). "
					% [error_string(promote_error), error_string(restore_error)]
					+ "The staged save was left at: %s" % STAGED_PATH
				)
		_remove_if_exists(TEMP_PATH)
		push_error("Could not activate the new save: %s" % error_string(promote_error))
		return false

	# The new primary is now in place. Failure to remove the staged file is
	# non-fatal: load_game_result() can still inspect it on the next startup.
	if not _remove_if_exists(STAGED_PATH):
		push_warning("New save is active, but the prior staged file could not be removed.")
	return true


func load_game() -> Dictionary:
	# Compatibility wrapper: existing game systems continue to receive a Dictionary.
	var result := load_game_result()
	return result.get("data", {}) as Dictionary


func load_game_result() -> Dictionary:
	## Detailed status API for menus, diagnostics, and future migrations.
	var primary := _read_dictionary(SAVE_PATH)
	if bool(primary.get("ok", false)):
		return {"status": "ok", "source": SAVE_PATH, "data": primary.get("data", {})}

	# An interrupted promotion can leave the last primary at STAGED_PATH.
	var staged := _read_dictionary(STAGED_PATH)
	if bool(staged.get("ok", false)):
		push_warning("Primary save is missing or invalid; recovered data from staged save.")
		return {
			"status": "recovered_from_staged_save",
			"source": STAGED_PATH,
			"primary_reason": primary.get("reason", "unknown"),
			"data": staged.get("data", {})
		}

	var backup := _read_dictionary(BACKUP_PATH)
	if bool(backup.get("ok", false)):
		push_warning("Primary save is missing or invalid; recovered data from backup.")
		return {
			"status": "recovered_from_backup",
			"source": BACKUP_PATH,
			"primary_reason": primary.get("reason", "unknown"),
			"data": backup.get("data", {})
		}

	var any_save_file := (
		FileAccess.file_exists(SAVE_PATH)
		or FileAccess.file_exists(STAGED_PATH)
		or FileAccess.file_exists(BACKUP_PATH)
	)
	if not any_save_file:
		return {"status": "not_found", "data": {}}

	# Return structured diagnostic state without logging an error as a side effect;
	# callers can decide how to surface corruption, and tests can assert statuses
	# without producing misleading CI error diagnostics.
	return {
		"status": "invalid",
		"data": {},
		"primary_reason": primary.get("reason", "unknown"),
		"staged_reason": staged.get("reason", "unknown"),
		"backup_reason": backup.get("reason", "unknown")
	}


func has_save() -> bool:
	return (
		FileAccess.file_exists(SAVE_PATH)
		or FileAccess.file_exists(BACKUP_PATH)
		or FileAccess.file_exists(STAGED_PATH)
	)


func delete_save() -> bool:
	var ok := true
	for path in [SAVE_PATH, BACKUP_PATH, TEMP_PATH, BACKUP_TEMP_PATH, STAGED_PATH]:
		if not _remove_if_exists(path):
			ok = false
	return ok


func _refresh_backup_from_primary(primary_data: Dictionary) -> bool:
	if not _remove_if_exists(BACKUP_TEMP_PATH):
		push_error("Could not clear the temporary backup file.")
		return false

	var copy_error := DirAccess.copy_absolute(
		ProjectSettings.globalize_path(SAVE_PATH),
		ProjectSettings.globalize_path(BACKUP_TEMP_PATH)
	)
	if copy_error != OK:
		push_error("Could not create the temporary backup: %s" % error_string(copy_error))
		return false

	var temporary_backup := _read_dictionary(BACKUP_TEMP_PATH)
	if (
		not bool(temporary_backup.get("ok", false))
		or temporary_backup.get("data", {}) != primary_data
	):
		_remove_if_exists(BACKUP_TEMP_PATH)
		push_error("Temporary backup failed content verification.")
		return false

	# The primary remains untouched while the backup destination is copied.
	# This is crash-resilient fallback logic, not a cross-platform atomic
	# transaction or a guarantee that the storage device has persisted bytes.
	copy_error = DirAccess.copy_absolute(
		ProjectSettings.globalize_path(BACKUP_TEMP_PATH),
		ProjectSettings.globalize_path(BACKUP_PATH)
	)
	if copy_error != OK:
		_remove_if_exists(BACKUP_TEMP_PATH)
		push_error("Could not update the backup save: %s" % error_string(copy_error))
		return false

	var backup_check := _read_dictionary(BACKUP_PATH)
	if (
		not bool(backup_check.get("ok", false))
		or backup_check.get("data", {}) != primary_data
	):
		_remove_if_exists(BACKUP_TEMP_PATH)
		push_error("Updated backup failed content verification; primary save was not changed.")
		return false

	if not _remove_if_exists(BACKUP_TEMP_PATH):
		push_warning("Verified backup is active, but its temporary file could not be removed.")
	return true


func _read_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "missing"}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "open_failed"}

	var file_size := file.get_length()
	if file_size <= 0 or file_size > MAX_SAVE_SIZE:
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
