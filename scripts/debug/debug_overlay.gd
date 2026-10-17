extends CanvasLayer

@onready var label: Label = $Label

var _last_positions: Dictionary = {}
var _dialogue_start_positions: Dictionary = {}
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
	# Keep measuring even while the overlay is hidden, so toggling F1 cannot
	# pause or reset the diagnostic sampling.
	var lines: PackedStringArray = []
	lines.append("DEBUG OVERLAY (F1 show/hide)")
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
		var player_body := player as Node3D
		if player_body != null:
			lines.append("player_pos: %s" % _format_position(player_body.global_position))
	else:
		lines.append("player: missing")

	var enemies := get_tree().get_nodes_in_group("enemies")
	if dialogue_active and not _dialogue_was_active:
		# Capture the baseline on the first frame where the dialogue manager is
		# active. Compare HP to this value, not to a hard-coded 100 HP.
		_dialogue_start_hp = player_hp
		_dialogue_elapsed = 0.0
		_dialogue_start_positions.clear()
		for enemy_node in enemies:
			if enemy_node is Node3D and is_instance_valid(enemy_node):
				_dialogue_start_positions[enemy_node.get_instance_id()] = (enemy_node as Node3D).global_position

	if dialogue_active:
		_dialogue_elapsed += delta
		lines.append("dialogue_seconds: %.1f / 15.0" % _dialogue_elapsed)
		if _dialogue_start_hp >= 0.0 and player_hp >= 0.0:
			lines.append("player_hp_at_pause_start: %.1f" % _dialogue_start_hp)
			lines.append("player_hp_delta_during_dialogue: %+.1f" % (player_hp - _dialogue_start_hp))
	else:
		lines.append("dialogue_seconds: inactive")

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

		var dialogue_displacement := -1.0
		if dialogue_active and _dialogue_start_positions.has(instance_id):
			var starting_position: Vector3 = _dialogue_start_positions[instance_id]
			dialogue_displacement = position_now.distance_to(starting_position)

		var health := enemy.get_node_or_null("Health")
		var enemy_hp := float(health.get("current")) if health != null else -1.0
		var movement_text := "warming-up" if not has_previous else ("yes" if step_distance > 0.001 else "no")
		var displacement_text := "n/a" if dialogue_displacement < 0.0 else "%.4f m" % dialogue_displacement
		lines.append("e%d pos=%s hp=%.1f stored_vel=%s frame_delta=%.4f dialogue_delta=%s moving=%s" % [
			i,
			_format_position(position_now),
			enemy_hp,
			str(enemy.velocity.snapped(Vector3.ONE * 0.1)),
			step_distance,
			displacement_text,
			movement_text
		])

	for old_id in _last_positions.keys():
		if not active_ids.has(old_id):
			_last_positions.erase(old_id)
	for old_id in _dialogue_start_positions.keys():
		if not active_ids.has(old_id):
			_dialogue_start_positions.erase(old_id)

	_dialogue_was_active = dialogue_active
	if visible:
		label.text = "\n".join(lines)


func _format_position(position: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [position.x, position.y, position.z]
