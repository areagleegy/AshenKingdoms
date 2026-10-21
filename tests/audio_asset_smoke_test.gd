extends SceneTree

const SOUND_PATHS: PackedStringArray = [
	"res://assets/audio/sfx/ash_wind_loop.wav",
	"res://assets/audio/music/ashen_exploration_loop.wav",
	"res://assets/audio/sfx/ash_wraith_attack.wav",
	"res://assets/audio/sfx/ash_wraith_death.wav",
	"res://assets/audio/sfx/footstep_stone.wav",
	"res://assets/audio/sfx/player_hit.wav",
	"res://assets/audio/sfx/player_jump.wav",
	"res://assets/audio/sfx/potion_use.wav",
	"res://assets/audio/sfx/quest_accept.wav",
	"res://assets/audio/sfx/quest_complete.wav",
	"res://assets/audio/sfx/sword_hit.wav",
	"res://assets/audio/sfx/sword_swing.wav",
	"res://assets/audio/sfx/ui_back.wav",
	"res://assets/audio/sfx/ui_select.wav"
]
const REQUIRED_BUSES: PackedStringArray = ["Master", "Music", "SFX", "Ambience", "Voice"]

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var manager := root.get_node_or_null("AudioManager")
	_check(manager != null, "AudioManager autoload is present")
	for path in SOUND_PATHS:
		_check(ResourceLoader.exists(path), "audio path exists: %s" % path)
		var stream := load(path) as AudioStreamWAV
		_check(stream != null, "audio resource loads as WAV: %s" % path)
		if stream != null:
			_check(stream.get_length() > 0.05, "audio duration is non-zero: %s" % path)
			_check(stream.mix_rate == 22050, "audio sample rate is 22050 Hz: %s" % path)
			_check(stream.data.size() > 0, "audio PCM payload is not empty: %s" % path)
	for bus_name in REQUIRED_BUSES:
		_check(AudioServer.get_bus_index(bus_name) >= 0, "mixer bus exists: %s" % bus_name)

	if manager != null:
		_check(bool(manager.call("play_sfx", &"ui_select", -12.0)), "UI select can be resolved for playback")
		_check(bool(manager.call("play_loop", &"ash_wind_loop", -18.0)), "world ambience can be resolved for looping")
		_check(bool(manager.call("play_loop", &"ashen_exploration_loop", -23.0)), "exploration music resolves for looping")
		var loop_players: Dictionary = manager.get("_loop_players")
		if loop_players.has(&"ash_wind_loop"):
			_check((loop_players[&"ash_wind_loop"] as AudioStreamPlayer).bus == "Ambience", "wind is routed to Ambience bus")
		if loop_players.has(&"ashen_exploration_loop"):
			_check((loop_players[&"ashen_exploration_loop"] as AudioStreamPlayer).bus == "Music", "exploration music is routed to Music bus")

		manager.call("set_master_volume", 0.75)
		manager.call("set_music_volume", 0.65)
		manager.call("set_sfx_volume", 0.55)
		manager.call("set_ambience_volume", 0.45)
		manager.call("set_voice_volume", 0.35)
		_check(is_equal_approx(float(manager.get("master_volume_linear")), 0.75), "master volume is clamped and stored")
		_check(is_equal_approx(float(manager.get("music_volume_linear")), 0.65), "music volume is independently stored")
		_check(is_equal_approx(float(manager.get("sfx_volume_linear")), 0.55), "SFX volume is independently stored")
		_check(is_equal_approx(float(manager.get("ambience_volume_linear")), 0.45), "ambience volume is independently stored")
		_check(is_equal_approx(float(manager.get("voice_volume_linear")), 0.35), "voice volume is independently stored")
		_check(_bus_volume_matches("Master", 0.75), "master setting is applied to AudioServer")
		_check(_bus_volume_matches("Music", 0.65), "music setting is applied to AudioServer")
		_check(_bus_volume_matches("SFX", 0.55), "SFX setting is applied to AudioServer")
		_check(_bus_volume_matches("Ambience", 0.45), "ambience setting is applied to AudioServer")
		_check(_bus_volume_matches("Voice", 0.35), "voice setting is applied to AudioServer")

		manager.call("set_muted", true)
		_check(bool(manager.get("muted")), "master mute state is stored")
		var master_index := AudioServer.get_bus_index("Master")
		_check(master_index >= 0 and AudioServer.is_bus_mute(master_index), "master mute is applied to AudioServer")

		var bus_count_before := AudioServer.get_bus_count()
		var restarted_manager := Node.new()
		restarted_manager.name = "AudioManagerPersistenceTest"
		restarted_manager.set_script(load("res://scripts/audio/audio_manager.gd"))
		root.add_child(restarted_manager)
		_check(is_equal_approx(float(restarted_manager.get("master_volume_linear")), 0.75), "master volume is restored from user settings")
		_check(is_equal_approx(float(restarted_manager.get("music_volume_linear")), 0.65), "music volume is restored from user settings")
		_check(is_equal_approx(float(restarted_manager.get("sfx_volume_linear")), 0.55), "SFX volume is restored from user settings")
		_check(is_equal_approx(float(restarted_manager.get("ambience_volume_linear")), 0.45), "ambience volume is restored from user settings")
		_check(is_equal_approx(float(restarted_manager.get("voice_volume_linear")), 0.35), "voice volume is restored from user settings")
		_check(bool(restarted_manager.get("muted")), "mute state is restored from user settings")
		_check(AudioServer.get_bus_count() == bus_count_before, "recreating the manager does not duplicate mixer buses")
		restarted_manager.free()

		manager.call("set_muted", false)
		_check(not AudioServer.is_bus_mute(master_index), "master mute is removed from AudioServer")
		manager.call("set_master_volume", 1.0)
		manager.call("set_music_volume", 0.8)
		manager.call("set_sfx_volume", 1.0)
		manager.call("set_ambience_volume", 0.7)
		manager.call("set_voice_volume", 1.0)
		manager.call("stop_all")
	print("[audio-smoke] files: %d; failures: %d" % [SOUND_PATHS.size(), _failures])
	quit(1 if _failures > 0 else 0)


func _bus_volume_matches(bus_name: String, linear_value: float) -> bool:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return false
	var expected_db := linear_to_db(maxf(linear_value, 0.0001))
	return is_equal_approx(AudioServer.get_bus_volume_db(bus_index), expected_db)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
