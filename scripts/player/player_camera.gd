extends Node3D

@export_range(0.0005, 0.02, 0.0005) var mouse_sensitivity: float = 0.003
@export_range(0.001, 0.03, 0.001) var touch_sensitivity: float = 0.005
@export_range(0.5, 4.0, 0.1) var stick_look_speed: float = 2.2
@export var min_pitch: float = -0.9
@export var max_pitch: float = 0.55

var _pitch: float = -0.18


func _ready() -> void:
	add_to_group("player_camera")
	rotation.x = _pitch


func _process(delta: float) -> void:
	var look_input := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look_input.length_squared() > 0.0001:
		apply_look_delta(look_input * stick_look_speed * delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		apply_look_delta((event as InputEventMouseMotion).relative * mouse_sensitivity)
		return

	# Reserve the left side for touch movement controls; look only from the right.
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		var viewport_width := get_viewport().get_visible_rect().size.x
		if viewport_width > 0.0 and drag.position.x >= viewport_width * 0.42:
			apply_look_delta(drag.screen_relative * touch_sensitivity)
			get_viewport().set_input_as_handled()


func apply_look_delta(delta: Vector2) -> void:
	rotate_y(-delta.x)
	_pitch = clampf(_pitch - delta.y, min_pitch, max_pitch)
	rotation.x = _pitch
