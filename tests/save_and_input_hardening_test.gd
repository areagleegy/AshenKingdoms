extends SceneTree

const SaveSystemScript: Script = preload("res://scripts/core/save_system.gd")
const AVATAR_SCENE: PackedScene = preload("res://scenes/network/NetworkAvatar.tscn")
const TEST_SAVE: String = "user://hardening_test_save.json"

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_atomic_save()
	await _test_hostile_input()
	print("[hardening] failures: %d" % failures)
	quit(1 if failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		failures += 1
		push_error("[FAIL] %s" % label)


func _write_raw(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "test fixture can be opened: %s" % path)
		return
	file.store_string(text)
	file.close()


func _test_atomic_save() -> void:
	var save: Node = SaveSystemScript.new()
	save.set("save_path", TEST_SAVE)
	save.call("delete_save")
	_check(bool(save.call("save_game", {"level": 1})), "first save succeeds")
	_check(not FileAccess.file_exists(TEST_SAVE + ".tmp"), "temporary file is removed after saving")
	_check(not FileAccess.file_exists(TEST_SAVE + ".bak"), "first save does not create a backup")
	_check(bool(save.call("save_game", {"level": 2})), "second save succeeds")
	_check(FileAccess.file_exists(TEST_SAVE + ".bak"), "previous valid save is backed up")
	_check(int(save.call("load_game").get("level", 0)) == 2, "load returns newest save")
	_check(bool(save.call("save_game", {"level": 3})), "third save replaces an existing backup")
	_check(int(save.call("load_game").get("level", 0)) == 3, "load returns the third save")
	_check(int(save.call("load_game").get("level", 0)) == 3, "load returns newest save")
	_write_raw(TEST_SAVE, "{corrupt")
	_check(int(save.call("load_game").get("level", 0)) == 2, "corrupt primary falls back to most recent backup")
	_write_raw(TEST_SAVE, "{}")
	_check((save.call("load_game") as Dictionary).is_empty(), "valid empty primary does not load stale backup")
	_write_raw(TEST_SAVE, "{corrupt again")
	_write_raw(TEST_SAVE + ".tmp", "half-written garbage")
	_check(int(save.call("load_game").get("level", 0)) == 2, "stale temp file never affects recovery")
	_write_raw(TEST_SAVE + ".bak", "{also corrupt")
	_check((save.call("load_game") as Dictionary).is_empty(), "corrupt primary and backup returns empty dictionary")
	_check(bool(save.call("delete_save")), "delete_save reports successful cleanup")
	_check(not bool(save.call("has_save")), "delete_save removes primary and backup")
	_check(not FileAccess.file_exists(TEST_SAVE + ".tmp"), "delete_save removes temporary files")
	save.free()


func _test_hostile_input() -> void:
	var cases := [
		{"label": "NaN direction", "direction": Vector3(NAN, 0.0, NAN)},
		{"label": "Infinity direction", "direction": Vector3(INF, 0.0, 0.0)},
		{"label": "valid direction", "direction": Vector3(1.0, 0.0, 0.0)},
	]
	for item in cases:
		var avatar: CharacterBody3D = AVATAR_SCENE.instantiate()
		avatar.call("configure_owner", 2)
		root.add_child(avatar)
		await process_frame
		avatar.call("_set_requested_input", item.direction, false, false, false)
		for _i in range(3):
			avatar.set("_last_input_msec", Time.get_ticks_msec())
			avatar.call("_server_step", 0.016)
			await physics_frame
		_check(avatar.global_position.is_finite() and avatar.velocity.is_finite(), "%s keeps avatar physics finite" % item.label)
		var requested: Vector3 = avatar.get("_requested_direction")
		_check(requested.is_finite(), "%s is sanitized before physics" % item.label)
		avatar.queue_free()
		await process_frame
