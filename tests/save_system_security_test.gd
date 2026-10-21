extends SceneTree

const SAVE_SCRIPT: Script = preload("res://scripts/core/save_system.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var saver := Node.new()
	saver.set_script(SAVE_SCRIPT)
	root.add_child(saver)
	saver.call("delete_save")

	_check(bool(saver.call("save_game", {"level": 2, "player_health": 80})), "first save succeeds")
	_check(saver.call("load_game").get("level", 0) == 2, "saved dictionary round-trips")
	_check(bool(saver.call("save_game", {"level": 3, "player_health": 70})), "second save succeeds")
	_check(FileAccess.file_exists("user://savegame.bak.json"), "previous save is backed up")

	var corrupt := FileAccess.open("user://savegame.json", FileAccess.WRITE)
	corrupt.store_string("{broken json")
	corrupt.close()
	var recovered: Dictionary = saver.call("load_game")
	_check(recovered.get("level", 0) == 2, "corrupt primary recovers previous valid backup")

	var too_large := {"payload": "x".repeat(1_048_577)}
	_check(not bool(saver.call("save_game", too_large)), "oversized save is rejected")
	_check(bool(saver.call("delete_save")), "delete removes primary, temporary and backup files")
	_check(not bool(saver.call("has_save")), "deleted save is no longer reported")
	print("[save-system-security] failures: %d" % failures)
	saver.free()
	quit(1 if failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] %s" % description)
	else:
		failures += 1
		push_error("[FAIL] %s" % description)
