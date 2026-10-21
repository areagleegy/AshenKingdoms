extends Node

const STREAM_PATHS: Dictionary = {
	&"ash_wind_loop": "res://assets/audio/sfx/ash_wind_loop.wav",
	&"ashen_exploration_loop": "res://assets/audio/music/ashen_exploration_loop.wav",
	&"ash_wraith_attack": "res://assets/audio/sfx/ash_wraith_attack.wav",
	&"ash_wraith_death": "res://assets/audio/sfx/ash_wraith_death.wav",
	&"footstep_stone": "res://assets/audio/sfx/footstep_stone.wav",
	&"player_hit": "res://assets/audio/sfx/player_hit.wav",
	&"player_jump": "res://assets/audio/sfx/player_jump.wav",
	&"potion_use": "res://assets/audio/sfx/potion_use.wav",
	&"quest_accept": "res://assets/audio/sfx/quest_accept.wav",
	&"quest_complete": "res://assets/audio/sfx/quest_complete.wav",
	&"sword_hit": "res://assets/audio/sfx/sword_hit.wav",
	&"sword_swing": "res://assets/audio/sfx/sword_swing.wav",
	&"ui_back": "res://assets/audio/sfx/ui_back.wav",
	&"ui_select": "res://assets/audio/sfx/ui_select.wav"
}
const LOOP_IDS: Array[StringName] = [&"ash_wind_loop", &"ashen_exploration_loop"]
const SFX_POOL_SIZE: int = 8
const SETTINGS_PATH: String = "user://audio_settings.cfg"
const BUS_MASTER: StringName = &"Master"
const BUS_MUSIC: StringName = &"Music"
const BUS_SFX: StringName = &"SFX"
const BUS_AMBIENCE: StringName = &"Ambience"
const BUS_VOICE: StringName = &"Voice"
const SETTINGS_SECTION: String = "audio"

var master_volume_linear: float = 1.0
var music_volume_linear: float = 0.8
var sfx_volume_linear: float = 1.0
var ambience_volume_linear: float = 0.7
var voice_volume_linear: float = 1.0
var muted: bool = false

var _stream_cache: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _loop_players: Dictionary = {}
var _next_player: int = 0


func _ready() -> void:
	_ensure_audio_buses()
	_load_settings()
	for index in range(SFX_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.name = "SFXPlayer%d" % index
		player.bus = String(BUS_SFX)
		add_child(player)
		_players.append(player)


func _ensure_audio_buses() -> void:
	# Create only missing buses; repeated manager construction must not duplicate them.
	_ensure_audio_bus(BUS_MUSIC)
	_ensure_audio_bus(BUS_SFX)
	_ensure_audio_bus(BUS_AMBIENCE)
	_ensure_audio_bus(BUS_VOICE)
	for bus_name in [BUS_MUSIC, BUS_SFX, BUS_AMBIENCE, BUS_VOICE]:
		var bus_index := AudioServer.get_bus_index(String(bus_name))
		if bus_index >= 0:
			AudioServer.set_bus_send(bus_index, String(BUS_MASTER))


func _ensure_audio_bus(bus_name: StringName) -> void:
	if AudioServer.get_bus_index(String(bus_name)) >= 0:
		return
	var bus_index := AudioServer.get_bus_count()
	AudioServer.add_bus(bus_index)
	AudioServer.set_bus_name(bus_index, String(bus_name))


func play_sfx(sound_id: StringName, volume_db: float = 0.0) -> bool:
	if not STREAM_PATHS.has(sound_id) or LOOP_IDS.has(sound_id):
		return false
	var stream := _get_stream(sound_id)
	if stream == null or _players.is_empty():
		return false
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stop()
	player.stream = stream
	player.volume_db = clampf(volume_db, -30.0, 6.0)
	player.play()
	return true


func play_loop(sound_id: StringName, volume_db: float = -16.0) -> bool:
	if not LOOP_IDS.has(sound_id):
		return false
	var stream := _get_stream(sound_id)
	if stream == null:
		return false
	if not _loop_players.has(sound_id):
		var loop_player := AudioStreamPlayer.new()
		loop_player.name = "Loop_%s" % String(sound_id)
		loop_player.bus = String(BUS_MUSIC if sound_id == &"ashen_exploration_loop" else BUS_AMBIENCE)
		add_child(loop_player)
		_loop_players[sound_id] = loop_player
	var active_player := _loop_players[sound_id] as AudioStreamPlayer
	if stream is AudioStreamWAV:
		var loop_stream := (stream as AudioStreamWAV).duplicate() as AudioStreamWAV
		if loop_stream == null:
			return false
		loop_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		loop_stream.loop_begin = 0
		loop_stream.loop_end = int(loop_stream.data.size() / 2)
		active_player.stream = loop_stream
	else:
		active_player.stream = stream
	active_player.volume_db = clampf(volume_db, -30.0, 0.0)
	if not active_player.playing:
		active_player.play()
	return true


func set_master_volume(value: float) -> void:
	master_volume_linear = clampf(value, 0.0, 1.0)
	_apply_bus_settings()
	_save_settings()


func set_music_volume(value: float) -> void:
	music_volume_linear = clampf(value, 0.0, 1.0)
	_apply_bus_settings()
	_save_settings()


func set_sfx_volume(value: float) -> void:
	sfx_volume_linear = clampf(value, 0.0, 1.0)
	_apply_bus_settings()
	_save_settings()


func set_ambience_volume(value: float) -> void:
	ambience_volume_linear = clampf(value, 0.0, 1.0)
	_apply_bus_settings()
	_save_settings()


func set_voice_volume(value: float) -> void:
	voice_volume_linear = clampf(value, 0.0, 1.0)
	_apply_bus_settings()
	_save_settings()


func set_muted(value: bool) -> void:
	muted = value
	_apply_bus_settings()
	_save_settings()


func _load_settings() -> void:
	var config := ConfigFile.new()
	var result: Error = config.load(SETTINGS_PATH)
	if result == OK:
		master_volume_linear = _read_volume(config, "master_volume_linear", 1.0)
		music_volume_linear = _read_volume(config, "music_volume_linear", 0.8)
		sfx_volume_linear = _read_volume(config, "sfx_volume_linear", 1.0)
		ambience_volume_linear = _read_volume(config, "ambience_volume_linear", 0.7)
		voice_volume_linear = _read_volume(config, "voice_volume_linear", 1.0)
		muted = bool(config.get_value(SETTINGS_SECTION, "muted", false))
	elif result != ERR_FILE_NOT_FOUND:
		push_warning("Could not load audio settings: %s" % error_string(result))
	_apply_bus_settings()


func _read_volume(config: ConfigFile, key: String, fallback: float) -> float:
	return clampf(float(config.get_value(SETTINGS_SECTION, key, fallback)), 0.0, 1.0)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(SETTINGS_SECTION, "master_volume_linear", master_volume_linear)
	config.set_value(SETTINGS_SECTION, "music_volume_linear", music_volume_linear)
	config.set_value(SETTINGS_SECTION, "sfx_volume_linear", sfx_volume_linear)
	config.set_value(SETTINGS_SECTION, "ambience_volume_linear", ambience_volume_linear)
	config.set_value(SETTINGS_SECTION, "voice_volume_linear", voice_volume_linear)
	config.set_value(SETTINGS_SECTION, "muted", muted)
	var result: Error = config.save(SETTINGS_PATH)
	if result != OK:
		push_warning("Could not save audio settings: %s" % error_string(result))


func _apply_bus_settings() -> void:
	_ensure_audio_buses()
	_set_bus_volume(BUS_MASTER, master_volume_linear)
	_set_bus_volume(BUS_MUSIC, music_volume_linear)
	_set_bus_volume(BUS_SFX, sfx_volume_linear)
	_set_bus_volume(BUS_AMBIENCE, ambience_volume_linear)
	_set_bus_volume(BUS_VOICE, voice_volume_linear)
	var master_index := AudioServer.get_bus_index(String(BUS_MASTER))
	if master_index >= 0:
		AudioServer.set_bus_mute(master_index, muted)


func _set_bus_volume(bus_name: StringName, value: float) -> void:
	var bus_index := AudioServer.get_bus_index(String(bus_name))
	if bus_index < 0:
		return
	# Avoid -INF while retaining a predictable near-silent slider endpoint.
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(value, 0.0001)))


func stop_loop(sound_id: StringName) -> void:
	if not _loop_players.has(sound_id):
		return
	var active_player := _loop_players[sound_id] as AudioStreamPlayer
	if is_instance_valid(active_player):
		active_player.stop()


func stop_all() -> void:
	for player in _players:
		if is_instance_valid(player):
			player.stop()
	for value in _loop_players.values():
		var active_player := value as AudioStreamPlayer
		if is_instance_valid(active_player):
			active_player.stop()


func _get_stream(sound_id: StringName) -> AudioStream:
	if _stream_cache.has(sound_id):
		return _stream_cache[sound_id] as AudioStream
	var path := String(STREAM_PATHS.get(sound_id, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		push_warning("Audio asset is missing: %s" % path)
		return null
	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("Audio asset could not be loaded: %s" % path)
		return null
	_stream_cache[sound_id] = stream
	return stream
