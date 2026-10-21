extends Node

const SAVE_PATH: String = "user://savegame.json"
const TEMP_SUFFIX: String = ".tmp"
const BACKUP_SUFFIX: String = ".bak"
const BACKUP_TEMP_SUFFIX: String = ".bak.tmp"

## Overridable so tests never touch the player's real save.
var save_path: String = SAVE_PATH


func save_game(data: Dictionary) -> bool:
	var json := JSON.stringify(data, "\t")
	var temp_path := save_path + TEMP_SUFFIX
	var temp_file := FileAccess.open(temp_path, FileAccess.WRITE)
	if temp_file == null:
		push_error("Could not open temporary save file: %s" % error_string(FileAccess.get_open_error()))
		return false
	temp_file.store_string(json)
	temp_file.flush()
	temp_file.close()
	if not FileAccess.file_exists(temp_path) or FileAccess.get_file_as_string(temp_path) != json or not _is_valid_dictionary_file(temp_path):
		push_error("Temporary save file failed verification; existing save kept.")
		_remove_if_exists(temp_path)
		return false

	if FileAccess.file_exists(save_path) and _is_valid_dictionary_file(save_path):
		var old_data := FileAccess.get_file_as_string(save_path)
		var backup_temp := save_path + BACKUP_TEMP_SUFFIX
		_remove_if_exists(backup_temp)
		var copy_error := DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(backup_temp))
		if copy_error != OK or not FileAccess.file_exists(backup_temp) or FileAccess.get_file_as_string(backup_temp) != old_data or not _is_valid_dictionary_file(backup_temp):
			push_error("Could not verify backup copy; existing save kept.")
			_remove_if_exists(backup_temp)
			_remove_if_exists(temp_path)
			return false
		var backup_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(backup_temp), ProjectSettings.globalize_path(save_path + BACKUP_SUFFIX))
		if backup_error != OK:
			push_error("Could not move verified backup into place: %s" % error_string(backup_error))
			_remove_if_exists(backup_temp)
			_remove_if_exists(temp_path)
			return false

	# Replace directly; never delete the primary before the verified temp is ready.
	var rename_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(save_path))
	if rename_error != OK:
		push_error("Could not move the new save into place: %s" % error_string(rename_error))
		_remove_if_exists(temp_path)
		return false
	return true


func load_game() -> Dictionary:
	if _is_valid_dictionary_file(save_path):
		return _read_dictionary(save_path)
	if _is_valid_dictionary_file(save_path + BACKUP_SUFFIX):
		return _read_dictionary(save_path + BACKUP_SUFFIX)
	return {}


func has_save() -> bool:
	return FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path + BACKUP_SUFFIX)


func delete_save() -> bool:
	var ok := true
	for path in [save_path, save_path + BACKUP_SUFFIX, save_path + TEMP_SUFFIX, save_path + BACKUP_TEMP_SUFFIX]:
		if not _remove_if_exists(path):
			ok = false
	return ok


func _is_valid_dictionary_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parser := JSON.new()
	var parse_result := parser.parse(file.get_as_text())
	file.close()
	return parse_result == OK and parser.data is Dictionary


func _read_dictionary(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser := JSON.new()
	var parse_result := parser.parse(file.get_as_text())
	file.close()
	if parse_result != OK or not parser.data is Dictionary:
		return {}
	return parser.data


func _remove_if_exists(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK
