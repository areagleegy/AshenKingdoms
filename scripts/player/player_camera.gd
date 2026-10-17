extends Node3D

@export_range(0.0005, 0.02, 0.0005) var mouse_sensitivity: float = 0.003
@export_range(0.001, 0.03, 0.001) var touch_sensitivity: float = 0.005
@export var min_pitch: float = -0.9
@export var max_pitch: float = 0.55

var _pitch: float = -0.18


func _ready() -> void:
	rotation.x = _pitch


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_apply_rotation(event.relative.x * mouse_sensitivity, event.relative.y * mouse_sensitivity)
	elif event is InputEventScreenDrag:
		_apply_rotation(event.relative.x * touch_sensitivity, event.relative.y * touch_sensitivity)


func _apply_rotation(dx: float, dy: float) -> void:
	rotate_y(-dx)
	_pitch = clampf(_pitch - dy, min_pitch, max_pitch)
	rotation.x = _pitch
