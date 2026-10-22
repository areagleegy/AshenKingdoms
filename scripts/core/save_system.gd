extends Node

const SAVE_PATH: String = "user://savegame.json"


func save_game(data: Dictionary) -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		var open_error := FileAccess.get_open_error()
		_push_qa_event("save_write_failed", {"error_code": open_error})
		push_error("Could not open save file for writing: %s" % open_error)
		return false

	file.store_string(JSON.stringify(data, "\t"))
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		_push_qa_event("save_write_failed", {"error_code": write_error})
		push_error("Could not finish writing save file: %s" % error_string(write_error))
		return false

	_push_qa_event("save_written")
	return true


func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		_push_qa_event("save_missing")
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		var open_error := FileAccess.get_open_error()
		_push_qa_event("save_read_failed", {"error_code": open_error})
		push_error("Could not open save file for reading: %s" % open_error)
		return {}

	var parser := JSON.new()
	var parse_result: Error = parser.parse(file.get_as_text())
	file.close()
	if parse_result != OK:
		_push_qa_event("save_json_invalid", {"error_code": parse_result})
		return {}
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		_push_qa_event("save_root_not_dictionary", {"error_code": ERR_INVALID_DATA})
		return {}

	_push_qa_event("save_loaded")
	return parsed


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func delete_save() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return true
	var result := DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	_push_qa_event("save_deleted" if result == OK else "save_delete_failed", {"error_code": result})
	return result == OK


func _push_qa_event(event_name: String, details: Dictionary = {}) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var reporter := tree.root.get_node_or_null("QAReporter")
	if reporter != null and reporter.has_method("record_event"):
		reporter.call("record_event", event_name, details)
