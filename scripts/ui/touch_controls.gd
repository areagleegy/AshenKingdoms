extends CanvasLayer

## Lightweight touch action bridge. All controls emit the same InputMap actions
## used by keyboard/mouse so gameplay logic remains platform-agnostic.

@onready var controls: Control = $Controls
@onready var move_pad: Control = $Controls/MovePad
@onready var status_label: Label = $Controls/Hint

var _move_touch := -1
var _look_touch := -1
var _move_origin := Vector2.ZERO
var _look_last := Vector2.ZERO
const MOVE_RADIUS := 54.0
const LOOK_SENSITIVITY := 0.008


func _ready() -> void:
	visible = OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")
	if not visible:
		return
	status_label.text = "الحركة يسار الشاشة • اسحب يمين الشاشة للكاميرا"
	for action in ["move_forward", "move_back", "move_left", "move_right", "jump", "attack", "interact", "inventory"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var split := get_viewport().get_visible_rect().size.x * 0.48
		if touch.pressed:
			if touch.position.x < split and _move_touch == -1:
				_move_touch = touch.index
				_move_origin = touch.position
				move_pad.position = _move_origin - move_pad.size * 0.5
				move_pad.visible = true
				_update_movement(touch.position)
			elif touch.position.x >= split and _look_touch == -1:
				_look_touch = touch.index
				_look_last = touch.position
		else:
			if touch.index == _move_touch:
				_move_touch = -1
				move_pad.visible = false
				_release_movement()
			if touch.index == _look_touch:
				_look_touch = -1
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _move_touch:
			_update_movement(drag.position)
		elif drag.index == _look_touch:
			var delta := drag.position - _look_last
			_look_last = drag.position
			var camera_pivot := get_tree().get_first_node_in_group("player_camera")
			if camera_pivot != null and camera_pivot.has_method("apply_look_delta"):
				camera_pivot.call("apply_look_delta", delta * LOOK_SENSITIVITY)


func _update_movement(position: Vector2) -> void:
	var delta := position - _move_origin
	if delta.length() > MOVE_RADIUS:
		delta = delta.normalized() * MOVE_RADIUS
	_set_action("move_left", delta.x < -MOVE_RADIUS * 0.22)
	_set_action("move_right", delta.x > MOVE_RADIUS * 0.22)
	_set_action("move_forward", delta.y < -MOVE_RADIUS * 0.22)
	_set_action("move_back", delta.y > MOVE_RADIUS * 0.22)


func _release_movement() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right"]:
		_set_action(action, false)


func _set_action(action: String, pressed: bool) -> void:
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _on_jump_pressed() -> void:
	Input.action_press("jump")


func _on_jump_released() -> void:
	Input.action_release("jump")


func _on_attack_pressed() -> void:
	Input.action_press("attack")


func _on_attack_released() -> void:
	Input.action_release("attack")


func _on_interact_pressed() -> void:
	Input.action_press("interact")
	get_viewport().set_input_as_handled()
	call_deferred("_release_one_frame_action", "interact")


func _on_inventory_pressed() -> void:
	Input.action_press("inventory")
	call_deferred("_release_one_frame_action", "inventory")


func _release_one_frame_action(action: String) -> void:
	await get_tree().process_frame
	Input.action_release(action)
