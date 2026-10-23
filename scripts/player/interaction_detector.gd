class_name InteractionDetector
extends Area3D

signal target_changed(target: Node3D)

var current_target: Node3D
var _in_range: Array[Node3D] = []
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
	var target := area.get_parent() as Node3D
	if target == null or not _is_interactable(target) or _in_range.has(target):
		return
	_in_range.append(target)
	_update_target()


func _on_area_exited(area: Area3D) -> void:
	var target := area.get_parent() as Node3D
	if target == null:
		return
	_in_range.erase(target)
	_update_target()


func _physics_process(_delta: float) -> void:
	var had_invalid := false
	for index in range(_in_range.size() - 1, -1, -1):
		if not is_instance_valid(_in_range[index]):
			_in_range.remove_at(index)
			had_invalid = true
	if had_invalid:
		_update_target()


func _update_target() -> void:
	var nearest: Node3D
	var best_distance := INF
	for target in _in_range:
		if not is_instance_valid(target) or not _is_interactable(target):
			continue
		var distance := global_position.distance_squared_to(target.global_position)
		if distance < best_distance:
			best_distance = distance
			nearest = target

	if nearest == current_target:
		_sync_target_ui()
		return

	_set_target_prompt(current_target, false)
	current_target = nearest
	_set_target_prompt(current_target, not _dialogue_active())
	target_changed.emit(current_target)
	_sync_target_ui()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or _is_echo(event):
		return
	if _dialogue_active() or not is_instance_valid(current_target):
		return
	current_target.call("interact")
	get_viewport().set_input_as_handled()


func interact() -> void:
	if _dialogue_active() or not is_instance_valid(current_target):
		return
	current_target.call("interact")


func _is_interactable(target: Node3D) -> bool:
	if not target.has_method("interact") or not target.has_method("set_prompt_visible"):
		return false
	return target.is_in_group("npc") or target.is_in_group("world_interactable")


func _set_target_prompt(target: Node3D, value: bool) -> void:
	if is_instance_valid(target) and target.has_method("set_prompt_visible"):
		target.call("set_prompt_visible", value)


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
	var has_target := is_instance_valid(current_target) and not _dialogue_active()
	_interact_button.visible = has_target
	if not has_target:
		return
	if current_target.has_method("get_interaction_button_text"):
		_interact_button.text = str(current_target.call("get_interaction_button_text"))
	else:
		_interact_button.text = "تحدّث"


func _on_dialogue_started() -> void:
	_set_target_prompt(current_target, false)
	_sync_target_ui()


func _on_dialogue_ended() -> void:
	_set_target_prompt(current_target, true)
	_sync_target_ui()


func _dialogue_active() -> bool:
	var manager := get_node_or_null("/root/DialogueManager")
	return manager != null and bool(manager.call("is_active"))


func _is_echo(event: InputEvent) -> bool:
	if event is InputEventKey:
		return (event as InputEventKey).echo
	return false
