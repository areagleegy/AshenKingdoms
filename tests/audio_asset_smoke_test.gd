extends SceneTree

const AUDIO_PATHS: Array[String] = [
	"res://assets/audio/sfx/ui_select.wav",
	"res://assets/audio/sfx/footstep_stone.wav",
	"res://assets/audio/sfx/sword_swing.wav",
	"res://assets/audio/sfx/sword_hit.wav",
	"res://assets/audio/sfx/ash_wraith_attack.wav",
	"res://assets/audio/sfx/potion_use.wav",
	"res://assets/audio/sfx/quest_complete.wav",
	"res://assets/audio/sfx/ash_wraith_death.wav",
	"res://assets/audio/sfx/player_hit.wav",
	"res://assets/audio/sfx/ash_wind_loop.wav",
]
const ICON_PATHS: Array[String] = [
	"res://assets/ui/icons/backpack.svg",
	"res://assets/ui/icons/pause.svg",
	"res://assets/ui/icons/sword.svg",
	"res://assets/ui/icons/jump.svg",
	"res://assets/ui/icons/sprint.svg",
	"res://assets/ui/icons/potion.svg",
	"res://assets/ui/icons/quest.svg",
]

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_audio_assets()
	_test_ui_assets()
	_test_manifest()
	_test_audio_feedback_script()
	print("[audio-assets] audio: %d, icons: %d, failures: %d" % [
		AUDIO_PATHS.size(), ICON_PATHS.size(), _failures
	])
	quit(1 if _failures > 0 else 0)


func _test_audio_assets() -> void:
	for path in AUDIO_PATHS:
		var stream := ResourceLoader.load(path) as AudioStreamWAV
		_check(stream != null, "WAV imports as AudioStreamWAV: %s" % path)
		if stream != null:
			_check(stream.get_length() > 0.0, "WAV duration is positive: %s" % path)
			_check(stream.mix_rate == 22050, "WAV sample rate is 22050 Hz: %s" % path)
			_check(not stream.stereo, "WAV is mono: %s" % path)


func _test_ui_assets() -> void:
	for path in ICON_PATHS:
		var texture := ResourceLoader.load(path) as Texture2D
		_check(texture != null, "SVG imports as Texture2D: %s" % path)


func _test_manifest() -> void:
	var manifest_text := FileAccess.get_file_as_string("res://assets/asset_manifest.json")
	var manifest: Variant = JSON.parse_string(manifest_text)
	_check(manifest is Dictionary, "asset manifest parses as JSON")
	if not manifest is Dictionary:
		return
	var records: Variant = manifest.get("assets", [])
	_check(records is Array, "asset manifest contains an assets array")
	if not records is Array:
		return
	var records_by_path: Dictionary = {}
	for record in records:
		if record is Dictionary:
			records_by_path[str(record.get("path", ""))] = record

	for path in AUDIO_PATHS + ICON_PATHS:
		var manifest_path := path.trim_prefix("res://")
		_check(records_by_path.has(manifest_path), "media file is registered: %s" % manifest_path)
		if records_by_path.has(manifest_path):
			var record: Dictionary = records_by_path[manifest_path]
			_check(not str(record.get("license", "")).strip_edges().is_empty(), "license recorded: %s" % manifest_path)
			_check(record.get("commercial_use", false) == true, "commercial permission recorded: %s" % manifest_path)
			_check(record.get("redistribution_allowed", false) == true, "redistribution recorded: %s" % manifest_path)


func _test_audio_feedback_script() -> void:
	var script := ResourceLoader.load("res://scripts/core/audio_feedback.gd") as Script
	_check(script != null and script.can_instantiate(), "AudioFeedback script loads and compiles")


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
