extends SceneTree

const SAVE_SCRIPT: Script = preload("res://scripts/core/save_system.gd")
const SAVE_FILES: Array[String] = [
	"user://savegame.json",
	"user://savegame.tmp",
	"user://savegame.bak.json",
]

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Do not mutate any save file unless every existing file was snapshotted.
	var snapshots: Dictionary = {}
	for path in SAVE_FILES:
		snapshots[path] = _snapshot_file(path)
	for path in SAVE_FILES:
		if not bool(snapshots[path].get("ok", false)):
			_check(false, "test aborts safely because snapshot failed: %s" % path)
			quit(1)
			return

	var saver := Node.new()
	saver.set_script(SAVE_SCRIPT)
	root.add_child(saver)

	_check(bool(saver.call("delete_save")), "test starts with an isolated save state")
	_check(bool(saver.call("save_game", {"level": 2, "player_health": 80})), "first save succeeds")
	_check(saver.call("load_game").get("level", 0) == 2, "saved dictionary round-trips")
	_check(bool(saver.call("save_game", {"level": 3, "player_health": 70})), "second save succeeds")
	_check(FileAccess.file_exists("user://savegame.bak.json"), "previous save is backed up")

	var corrupt := FileAccess.open("user://savegame.json", FileAccess.WRITE)
	if corrupt == null:
		_check(false, "primary save can be opened to simulate corruption")
	else:
		corrupt.store_string("{broken json")
		corrupt.flush()
		var write_error: Error = corrupt.get_error()
		corrupt.close()
		_check(write_error == OK, "corrupt fixture is written")
		if write_error == OK:
			var recovered: Dictionary = saver.call("load_game")
			_check(recovered.get("level", 0) == 2, "corrupt primary recovers previous valid backup")

	var too_large := {"payload": "x".repeat(1_048_577)}
	_check(not bool(saver.call("save_game", too_large)), "oversized save is rejected")
	_check(bool(saver.call("delete_save")), "delete removes primary, temporary and backup files")
	_check(not bool(saver.call("has_save")), "deleted save is no longer reported")

	# Restore originals even when an assertion above failed.
	for path in SAVE_FILES:
		_restore_file(path, snapshots[path])
	saver.free()

	print("[save-system-security] failures: %d" % failures)
	quit(1 if failures > 0 else 0)


func _snapshot_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": true, "exists": false, "content": ""}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not snapshot existing test file: %s" % path)
		return {"ok": false, "exists": true, "content": ""}
	var content := file.get_as_text()
	var read_error: Error = file.get_error()
	file.close()
	if read_error != OK:
		push_error("Could not fully read existing test file: %s" % path)
		return {"ok": false, "exists": true, "content": ""}
	return {"ok": true, "exists": true, "content": content}


func _restore_file(path: String, snapshot: Dictionary) -> void:
	if not bool(snapshot.get("exists", false)):
		if FileAccess.file_exists(path):
			var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			_check(remove_error == OK, "temporary test file is removed: %s" % path)
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "original file can be restored: %s" % path)
		return
	file.store_string(str(snapshot.get("content", "")))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	_check(write_error == OK, "original file is restored: %s" % path)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] %s" % description)
	else:
		failures += 1
		push_error("[FAIL] %s" % description)
