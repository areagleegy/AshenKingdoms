class_name InteractionDetector
extends Area3D

signal target_changed(npc: NPC)

var current_target: NPC
var _in_range: Array[NPC] = []
var _interact_button: Button


func _ready() -> void:
	monitoring = true
	collision_layer = 0
	collision_mask = 4
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)
	_build_touch_interact_button()

	var manager := get_node_or_null("/root/DialogueManager")
	if manager != null:
		manager.connect("dialogue_started", _on_dialogue_started)
		manager.connect("dialogue_ended", _on_dialogue_ended)


func _on_area_entered(area: Area3D) -> void:
	var npc := area.get_parent() as NPC
	if npc == null or _in_range.has(npc):
		return
	_in_range.append(npc)
	_update_target()


func _on_area_exited(area: Area3D) -> void:
	var npc := area.get_parent() as NPC
	if npc == null:
		return
	_in_range.erase(npc)
	_update_target()


func _physics_process(_delta: float) -> void:
	# Clean up freed NPCs and keep the nearest candidate as the player moves.
	var had_invalid := false
	for index in range(_in_range.size() - 1, -1, -1):
		if not is_instance_valid(_in_range[index]):
			_in_range.remove_at(index)
			had_invalid = true
	if had_invalid:
		_update_target()


func _update_target() -> void:
	var nearest: NPC
	var best_distance := INF
	for npc in _in_range:
		if not is_instance_valid(npc):
			continue
		var distance := global_position.distance_squared_to(npc.global_position)
		if distance < best_distance:
			best_distance = distance
			nearest = npc

	if nearest == current_target:
		_sync_target_ui()
		return

	if is_instance_valid(current_target):
		current_target.set_prompt_visible(false)
	current_target = nearest
	if is_instance_valid(current_target):
		current_target.set_prompt_visible(not _dialogue_active())
	target_changed.emit(current_target)
	_sync_target_ui()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or _is_echo(event):
		return
	if _dialogue_active() or not is_instance_valid(current_target):
		return
	current_target.interact()
	get_viewport().set_input_as_handled()


func interact() -> void:
	if _dialogue_active() or not is_instance_valid(current_target):
		return
	current_target.interact()


func _build_touch_interact_button() -> void:
	var layer := CanvasLayer.new()
	layer.name = "TouchInteractLayer"
	layer.layer = 20
	add_child(layer)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	_interact_button = Button.new()
	_interact_button.name = "InteractButton"
	_interact_button.text = "تحدّث"
	_interact_button.custom_minimum_size = Vector2(116.0, 54.0)
	_interact_button.anchor_left = 1.0
	_interact_button.anchor_right = 1.0
	_interact_button.anchor_top = 1.0
	_interact_button.anchor_bottom = 1.0
	_interact_button.offset_left = -140.0
	_interact_button.offset_right = -20.0
	_interact_button.offset_top = -245.0
	_interact_button.offset_bottom = -185.0
	_interact_button.focus_mode = Control.FOCUS_NONE
	_interact_button.visible = false
	_interact_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_interact_button.pressed.connect(interact)
	root.add_child(_interact_button)


func _sync_target_ui() -> void:
	if not is_instance_valid(_interact_button):
		return
	_interact_button.visible = is_instance_valid(current_target) and not _dialogue_active()


func _on_dialogue_started() -> void:
	if is_instance_valid(current_target):
		current_target.set_prompt_visible(false)
	_sync_target_ui()


func _on_dialogue_ended() -> void:
	if is_instance_valid(current_target):
		current_target.set_prompt_visible(true)
	_sync_target_ui()


func _dialogue_active() -> bool:
	var manager := get_node_or_null("/root/DialogueManager")
	return manager != null and bool(manager.call("is_active"))


func _is_echo(event: InputEvent) -> bool:
	if event is InputEventKey:
		return (event as InputEventKey).echo
	return false
