extends SceneTree

var _failures: int = 0
var _script_paths: Array[String] = []
var _scene_paths: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_collect_project_resources("res://")
	_script_paths.sort()
	_scene_paths.sort()

	for script_path in _script_paths:
		var script_resource: Resource = ResourceLoader.load(script_path)
		_check(script_resource is Script, "GDScript resource loads: %s" % script_path)
		if script_resource is Script:
			var script := script_resource as Script
			_check(script.can_instantiate(), "GDScript compiles and can instantiate: %s" % script_path)

	for scene_path in _scene_paths:
		var scene_resource: Resource = ResourceLoader.load(scene_path)
		_check(scene_resource is PackedScene, "scene loads: %s" % scene_path)

	await _test_touch_controls()
	await _test_touch_controls_scene()

	print("[resource-smoke] scripts: %d, scenes: %d, failures: %d" % [
		_script_paths.size(), _scene_paths.size(), _failures
	])
	quit(1 if _failures > 0 else 0)


func _collect_project_resources(directory_path: String) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		_check(false, "directory opens: %s" % directory_path)
		return

	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry == "." or entry == ".." or entry.begins_with("."):
			entry = directory.get_next()
			continue

		var full_path := directory_path.path_join(entry)
		if directory.current_is_dir():
			_collect_project_resources(full_path)
		else:
			match entry.get_extension().to_lower():
				"gd":
					_script_paths.append(full_path)
				"tscn":
					_scene_paths.append(full_path)
		entry = directory.get_next()
	directory.list_dir_end()


func _test_touch_controls() -> void:
	var packed_scene: PackedScene = ResourceLoader.load("res://scenes/ui/VirtualJoystick.tscn") as PackedScene
	_check(packed_scene != null, "virtual joystick scene loads as a PackedScene")
	if packed_scene == null:
		return

	var instance := packed_scene.instantiate()
	_check(instance is Control, "virtual joystick scene instantiates as Control")
	if not is_instance_valid(instance):
		return

	var canvas := CanvasLayer.new()
	root.add_child(canvas)
	canvas.add_child(instance)
	await process_frame

	_check(instance.has_signal("direction_changed"), "virtual joystick publishes direction_changed")
	var control := instance as Control
	var local_center := control.size * 0.5
	var viewport_center: Vector2 = control.get_global_transform_with_canvas() * local_center
	var converted_center: Vector2 = control.make_canvas_position_local(viewport_center)
	_check(converted_center.is_equal_approx(local_center), "viewport touch coordinates convert to local coordinates")
	canvas.queue_free()


func _test_touch_controls_scene() -> void:
	const scene_path := "res://scenes/ui/TouchControls.tscn"
	const script_path := "res://scripts/ui/touch_controls.gd"
	var packed_scene := ResourceLoader.load(scene_path) as PackedScene
	_check(packed_scene != null, "touch controls scene loads")
	if packed_scene == null:
		return

	var instance := packed_scene.instantiate()
	_check(instance is CanvasLayer, "touch controls scene instantiates as CanvasLayer")
	root.add_child(instance)
	await process_frame

	for node_path in [
		"Controls",
		"Controls/MovePad",
		"Controls/Hint",
		"Controls/Jump",
		"Controls/Attack",
		"Controls/Interact",
		"Controls/Inventory",
	]:
		_check(instance.has_node(node_path), "touch controls node exists: %s" % node_path)

	var script_text := FileAccess.get_file_as_string(script_path)
	var node_path_regex := RegEx.new()
	var compile_result := node_path_regex.compile("\\$([A-Za-z0-9_./]+)")
	_check(compile_result == OK, "touch controls node-path checker compiles")
	if compile_result == OK:
		for match_result in node_path_regex.search_all(script_text):
			var node_path := match_result.get_string(1)
			_check(
				instance.has_node(node_path),
				"touch controls script path resolves in scene: %s" % node_path
			)

	instance.queue_free()
	await process_frame


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
