extends Node

const SFX_STREAMS: Dictionary = {
	&"ui_select": preload("res://assets/audio/sfx/ui_select.wav"),
	&"footstep_stone": preload("res://assets/audio/sfx/footstep_stone.wav"),
	&"sword_swing": preload("res://assets/audio/sfx/sword_swing.wav"),
	&"sword_hit": preload("res://assets/audio/sfx/sword_hit.wav"),
	&"ash_wraith_attack": preload("res://assets/audio/sfx/ash_wraith_attack.wav"),
	&"potion_use": preload("res://assets/audio/sfx/potion_use.wav"),
	&"quest_complete": preload("res://assets/audio/sfx/quest_complete.wav"),
	&"ash_wraith_death": preload("res://assets/audio/sfx/ash_wraith_death.wav"),
	&"player_hit": preload("res://assets/audio/sfx/player_hit.wav"),
}
const AMBIENT_WIND: AudioStreamWAV = preload("res://assets/audio/sfx/ash_wind_loop.wav")
const PLAYER_POOL_SIZE: int = 8

var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _ambient_player: AudioStreamPlayer


func _ready() -> void:
	for index in range(PLAYER_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.name = "SFXPlayer_%02d" % index
		add_child(player)
		_players.append(player)

	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.name = "AshWindAmbience"
	var wind_stream := AMBIENT_WIND.duplicate() as AudioStreamWAV
	if wind_stream != null:
		wind_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wind_stream.loop_begin = 0
		wind_stream.loop_end = int(wind_stream.data.size() / 2)
		_ambient_player.stream = wind_stream
	_ambient_player.volume_db = -24.0
	add_child(_ambient_player)


func play_sfx(sound_id: StringName, volume_db: float = -6.0) -> void:
	var stream := SFX_STREAMS.get(sound_id) as AudioStream
	if stream == null or _players.is_empty():
		return

	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stop()
	player.stream = stream
	player.volume_db = volume_db
	player.play()


func start_ambience() -> void:
	if is_instance_valid(_ambient_player) and not _ambient_player.playing:
		_ambient_player.play()


func stop_ambience() -> void:
	if is_instance_valid(_ambient_player):
		_ambient_player.stop()
