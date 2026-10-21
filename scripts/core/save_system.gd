extends Node

const SAVE_PATH: String = "user://savegame.json"
const TEMP_SAVE_PATH: String = "user://savegame.json.tmp"
const BACKUP_SAVE_PATH: String = "user://savegame.json.bak"
const SAVE_VERSION: int = 2
const MAX_SAVE_BYTES: int = 1_048_576

const REQUIRED_KEYS: Array[String] = [
	"version",
	"player_position",
	"player_health",
	"level",
	"experience",
	"inventory",
	"quest",
	"dialogue",
]

var _unsupported_future_save: bool = false


func save_game(data: Dictionary) -> bool:
	# Work on a copy so validation/versioning does not mutate caller-owned state.
	var candidate: Dictionary = data.duplicate(true)
	candidate["version"] = SAVE_VERSION
	if not _validate_payload(candidate):
		push_error("SaveSystem: refusing to write an invalid save payload.")
		return false

	var payload := JSON.stringify(candidate, "\t")
	if payload.to_utf8_buffer().size() > MAX_SAVE_BYTES:
		push_error("SaveSystem: save payload exceeds the 1 MiB limit.")
		return false

	var temporary_file := FileAccess.open(TEMP_SAVE_PATH, FileAccess.WRITE)
	if temporary_file == null:
		push_error("SaveSystem: could not open temporary save file: %s" % error_string(FileAccess.get_open_error()))
		return false

	temporary_file.store_string(payload)
	temporary_file.flush()
	var write_error: Error = temporary_file.get_error()
	temporary_file.close()
	if write_error != OK:
		push_error("SaveSystem: failed writing temporary save: %s" % error_string(write_error))
		_remove_if_exists(TEMP_SAVE_PATH)
		return false

	var save_absolute := ProjectSettings.globalize_path(SAVE_PATH)
	var temp_absolute := ProjectSettings.globalize_path(TEMP_SAVE_PATH)
	var backup_absolute := ProjectSettings.globalize_path(BACKUP_SAVE_PATH)
	var had_previous_save := FileAccess.file_exists(SAVE_PATH)

	# Preserve the current save as the recovery copy until the replacement is installed.
	if FileAccess.file_exists(BACKUP_SAVE_PATH) and not _remove_if_exists(BACKUP_SAVE_PATH):
		push_error("SaveSystem: could not clear stale backup before replacement.")
		_remove_if_exists(TEMP_SAVE_PATH)
		return false

	if had_previous_save:
		var backup_error: Error = DirAccess.rename_absolute(save_absolute, backup_absolute)
		if backup_error != OK:
			push_error("SaveSystem: could not preserve previous save: %s" % error_string(backup_error))
			_remove_if_exists(TEMP_SAVE_PATH)
			return false

	var replace_error: Error = DirAccess.rename_absolute(temp_absolute, save_absolute)
	if replace_error != OK:
		push_error("SaveSystem: could not install new save: %s" % error_string(replace_error))
		if had_previous_save:
			var rollback_error: Error = DirAccess.rename_absolute(backup_absolute, save_absolute)
			if rollback_error != OK:
				push_error("SaveSystem: CRITICAL: save rollback failed: %s" % error_string(rollback_error))
		_remove_if_exists(TEMP_SAVE_PATH)
		return false

	# Keep the previous save as a recovery copy. The next successful save rotates it.
	return true


func load_game() -> Dictionary:
	_unsupported_future_save = false
	if not FileAccess.file_exists(SAVE_PATH):
		if FileAccess.file_exists(BACKUP_SAVE_PATH):
			push_warning("SaveSystem: primary save is missing; trying recovery backup.")
			return _load_from_path(BACKUP_SAVE_PATH)
		return {}

	var data := _load_from_path(SAVE_PATH)
	if not data.is_empty():
		return data

	# Do not silently roll back a save created by a newer game version.
	if _unsupported_future_save:
		return {}

	if FileAccess.file_exists(BACKUP_SAVE_PATH):
		push_warning("SaveSystem: primary save is invalid; trying recovery backup.")
		return _load_from_path(BACKUP_SAVE_PATH)
	return {}


func _load_from_path(path: String) -> Dictionary:
	_unsupported_future_save = false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("SaveSystem: could not open %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return {}

	if file.get_length() > MAX_SAVE_BYTES:
		file.close()
		push_warning("SaveSystem: refusing oversized save file: %s" % path)
		return {}

	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		push_warning("SaveSystem: invalid JSON in %s at line %d." % [path, parser.get_error_line()])
		return {}

	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		push_warning("SaveSystem: save root must be a JSON object: %s" % path)
		return {}

	var data: Dictionary = parsed
	var version_value: Variant = data.get("version", 1)
	if not _is_number(version_value) or int(version_value) < 1:
		push_warning("SaveSystem: missing or invalid save version in %s." % path)
		return {}
	if int(version_value) > SAVE_VERSION:
		_unsupported_future_save = true
		push_warning("SaveSystem: save version %d is newer than supported version %d." % [int(version_value), SAVE_VERSION])
		return {}

	data = _migrate_payload(data)
	if not _validate_payload(data):
		push_warning("SaveSystem: save schema validation failed for %s." % path)
		return {}
	return data


func _validate_payload(data: Dictionary) -> bool:
	for key in REQUIRED_KEYS:
		if not data.has(key):
			return false

	if not _is_number(data["version"]) or int(data["version"]) != SAVE_VERSION:
		return false
	if not data["player_position"] is Dictionary:
		return false
	var position_data: Dictionary = data["player_position"]
	for axis in ["x", "y", "z"]:
		if not position_data.has(axis) or not _is_number(position_data[axis]):
			return false
		if not is_finite(float(position_data[axis])) or absf(float(position_data[axis])) > 1_000_000.0:
			return false

	if not _is_number(data["player_health"]):
		return false
	var health := float(data["player_health"])
	if not is_finite(health) or health < 0.0 or health > 9999.0:
		return false

	if typeof(data["level"]) != TYPE_INT or int(data["level"]) < 1 or int(data["level"]) > 10000:
		return false
	if not _is_number(data["experience"]) or not is_finite(float(data["experience"])) or float(data["experience"]) < 0.0:
		return false
	if not data["inventory"] is Array:
		return false
	if not data["quest"] is Dictionary or not data["dialogue"] is Dictionary:
		return false
	return true


func _migrate_payload(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 1))
	# Version 1 already used the current gameplay field names. Version 2 makes
	# the schema version explicit while preserving quest/dialogue save contents.
	if version < 2:
		data["version"] = 2
		push_warning("SaveSystem: migrated save data from version %d to %d." % [version, SAVE_VERSION])
	return data


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func delete_save() -> bool:
	for path in [SAVE_PATH, TEMP_SAVE_PATH, BACKUP_SAVE_PATH]:
		if not _remove_if_exists(path):
			return false
	return true


func _remove_if_exists(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK
