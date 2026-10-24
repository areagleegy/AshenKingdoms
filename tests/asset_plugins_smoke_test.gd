extends SceneTree

const PLUGIN_CONFIG_PATHS: Array[String] = [
	"res://addons/ashen_asset_bridge/plugin.cfg",
	"res://addons/ashen_free_asset_pipeline/plugin.cfg",
]

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var project_config := ConfigFile.new()
	var project_error := project_config.load("res://project.godot")
	_check(project_error == OK, "project.godot loads as a configuration file")
	if project_error != OK:
		_finish()
		return

	var enabled_plugins: PackedStringArray = project_config.get_value(
		"editor_plugins", "enabled", PackedStringArray()
	)

	for config_path in PLUGIN_CONFIG_PATHS:
		_test_plugin_config(config_path, enabled_plugins)

	print("[asset-plugin-smoke] failures: %d" % _failures)
	_finish()


func _test_plugin_config(config_path: String, enabled_plugins: PackedStringArray) -> void:
	_check(FileAccess.file_exists(config_path), "plugin config exists: %s" % config_path)
	if not FileAccess.file_exists(config_path):
		return

	var plugin_config := ConfigFile.new()
	var config_error := plugin_config.load(config_path)
	_check(config_error == OK, "plugin config parses: %s" % config_path)
	if config_error != OK:
		return

	var plugin_name := str(plugin_config.get_value("plugin", "name", "")).strip_edges()
	var relative_script := str(plugin_config.get_value("plugin", "script", "")).strip_edges()
	_check(not plugin_name.is_empty(), "plugin has a non-empty name: %s" % config_path)
	_check(not relative_script.is_empty(), "plugin declares its editor script: %s" % config_path)
	_check(enabled_plugins.has(config_path), "plugin is enabled in project.godot: %s" % config_path)

	if relative_script.is_empty():
		return

	var script_path := relative_script
	if not script_path.begins_with("res://"):
		script_path = config_path.get_base_dir().path_join(relative_script)

	_check(FileAccess.file_exists(script_path), "plugin script exists: %s" % script_path)
	if not FileAccess.file_exists(script_path):
		return

	var plugin_script := ResourceLoader.load(script_path) as Script
	_check(plugin_script != null, "plugin script loads without a resource error: %s" % script_path)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)


func _finish() -> void:
	quit(1 if _failures > 0 else 0)
