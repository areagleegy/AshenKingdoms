extends CanvasLayer

@onready var label: Label = $Label

var _last_positions: Dictionary = {}
var _dialogue_was_active: bool = false
var _dialogue_start_hp: float = -1.0
var _dialogue_elapsed: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F1:
			visible = not visible
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return

	var lines: PackedStringArray = []
	lines.append("DEBUG OVERLAY (F1 hide)")
	lines.append("paused: %s" % str(get_tree().paused))

	var manager := get_node_or_null("/root/DialogueManager")
	var dialogue_active := manager != null and bool(manager.call("is_active"))
	lines.append("dialogue_active: %s" % str(dialogue_active))
	if manager != null:
		lines.append("flags: %s" % str(manager.get("flags")))

	var player := get_tree().get_first_node_in_group("player")
	var player_hp: float = -1.0
	if player != null:
		var health := player.get_node_or_null("Health")
		if health != null:
			player_hp = float(health.get("current"))
			lines.append("player_hp: %.1f" % player_hp)
		else:
			lines.append("player_hp: unavailable")
		lines.append("player_pos: %s" % str((player as Node3D).global_position.snapped(Vector3.ONE)))
	else:
		lines.append("player: missing")

	if dialogue_active:
		if not _dialogue_was_active:
			_dialogue_start_hp = player_hp
			_dialogue_elapsed = 0.0
		_dialogue_elapsed += delta
		lines.append("dialogue_seconds: %.1f / 15.0" % _dialogue_elapsed)
		if _dialogue_start_hp >= 0.0 and player_hp >= 0.0:
			lines.append("player_hp_delta_during_dialogue: %+.1f" % (player_hp - _dialogue_start_hp))
	else:
		_dialogue_elapsed = 0.0
		_dialogue_start_hp = player_hp
	_dialogue_was_active = dialogue_active

	# The enemy group is named "enemies" in enemy.gd. Report both the stored
	# CharacterBody velocity and actual position delta; velocity can retain its
	# last value while the scene tree is paused, so it alone does not prove motion.
	var enemies := get_tree().get_nodes_in_group("enemies")
	lines.append("enemies: %d" % enemies.size())
	var active_ids: Dictionary = {}
	for i in range(enemies.size()):
		var enemy := enemies[i] as CharacterBody3D
		if not is_instance_valid(enemy):
			continue
		var instance_id := enemy.get_instance_id()
		active_ids[instance_id] = true
		var position_now: Vector3 = enemy.global_position
		var step_distance := 0.0
		var has_previous := _last_positions.has(instance_id)
		if has_previous:
			step_distance = position_now.distance_to(_last_positions[instance_id])
		_last_positions[instance_id] = position_now
		var health := enemy.get_node_or_null("Health")
		var enemy_hp := float(health.get("current")) if health != null else -1.0
		var movement_text := "warming-up" if not has_previous else ("yes" if step_distance > 0.001 else "no")
		lines.append("e%d pos=%s hp=%.1f stored_vel=%s frame_delta=%.4f moving=%s" % [
			i,
			str(position_now.snapped(Vector3.ONE)),
			enemy_hp,
			str(enemy.velocity.snapped(Vector3.ONE * 0.1)),
			step_distance,
			movement_text
		])

	for old_id in _last_positions.keys():
		if not active_ids.has(old_id):
			_last_positions.erase(old_id)

	label.text = "\n".join(lines)
