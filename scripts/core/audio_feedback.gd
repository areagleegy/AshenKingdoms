extends Node

const SFX_PATHS: Dictionary = {
	&"ui_select": "res://assets/audio/sfx/ui_select.wav",
	&"footstep_stone": "res://assets/audio/sfx/footstep_stone.wav",
	&"sword_swing": "res://assets/audio/sfx/sword_swing.wav",
	&"sword_hit": "res://assets/audio/sfx/sword_hit.wav",
	&"ash_wraith_attack": "res://assets/audio/sfx/ash_wraith_attack.wav",
	&"potion_use": "res://assets/audio/sfx/potion_use.wav",
	&"quest_complete": "res://assets/audio/sfx/quest_complete.wav",
	&"ash_wraith_death": "res://assets/audio/sfx/ash_wraith_death.wav",
	&"player_hit": "res://assets/audio/sfx/player_hit.wav",
}
const AMBIENT_WIND_PATH: String = "res://assets/audio/sfx/ash_wind_loop.wav"
const PLAYER_POOL_SIZE: int = 8

var _sfx_streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _ambient_player: AudioStreamPlayer


func _ready() -> void:
	_load_streams()
	for index in range(PLAYER_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.name = "SFXPlayer_%02d" % index
		add_child(player)
		_players.append(player)

	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.name = "AshWindAmbience"
	var wind_stream := ResourceLoader.load(AMBIENT_WIND_PATH) as AudioStreamWAV
	if wind_stream != null:
		var loop_stream := wind_stream.duplicate() as AudioStreamWAV
		if loop_stream != null:
			loop_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			loop_stream.loop_begin = 0
			loop_stream.loop_end = int(loop_stream.data.size() / 2)
			_ambient_player.stream = loop_stream
	else:
		push_warning("AudioFeedback: ambient WAV could not be loaded: %s" % AMBIENT_WIND_PATH)
	_ambient_player.volume_db = -24.0
	add_child(_ambient_player)


func _load_streams() -> void:
	_sfx_streams.clear()
	for sound_id in SFX_PATHS:
		var path := str(SFX_PATHS[sound_id])
		var stream := ResourceLoader.load(path) as AudioStreamWAV
		if stream == null:
			push_warning("AudioFeedback: SFX WAV could not be loaded: %s" % path)
			continue
		_sfx_streams[sound_id] = stream


func play_sfx(sound_id: StringName, volume_db: float = -6.0) -> void:
	var stream := _sfx_streams.get(sound_id) as AudioStream
	if stream == null or _players.is_empty():
		return

	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stop()
	player.stream = stream
	player.volume_db = volume_db
	player.play()


func start_ambience() -> void:
	if is_instance_valid(_ambient_player) and _ambient_player.stream != null and not _ambient_player.playing:
		_ambient_player.play()


func stop_ambience() -> void:
	if is_instance_valid(_ambient_player):
		_ambient_player.stop()


func get_loaded_sfx_count() -> int:
	return _sfx_streams.size()


func is_ambience_loaded() -> bool:
	return is_instance_valid(_ambient_player) and _ambient_player.stream != null
