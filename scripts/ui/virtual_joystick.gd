extends Control

signal direction_changed(direction: Vector2)

@export_range(0.05, 0.5, 0.01) var deadzone: float = 0.16
@export_range(0.2, 0.48, 0.01) var radius_ratio: float = 0.36

var _active_touch_index: int = -1
var _direction: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var local_position := to_local(touch.position)
		if touch.pressed and _active_touch_index == -1 and Rect2(Vector2.ZERO, size).has_point(local_position):
			_active_touch_index = touch.index
			_update_from_screen_position(touch.position)
			accept_event()
		elif not touch.pressed and touch.index == _active_touch_index:
			_active_touch_index = -1
			_set_direction(Vector2.ZERO)
			accept_event()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _active_touch_index:
			_update_from_screen_position(drag.position)
			accept_event()


func _update_from_screen_position(screen_position: Vector2) -> void:
	var center := size * 0.5
	var radius := maxf(minf(size.x, size.y) * radius_ratio, 1.0)
	var raw_direction := (to_local(screen_position) - center) / radius
	if raw_direction.length_squared() > 1.0:
		raw_direction = raw_direction.normalized()
	if raw_direction.length() < deadzone:
		raw_direction = Vector2.ZERO
	_set_direction(raw_direction)


func _set_direction(next_direction: Vector2) -> void:
	if _direction.is_equal_approx(next_direction):
		return
	_direction = next_direction
	direction_changed.emit(_direction)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := maxf(minf(size.x, size.y) * radius_ratio, 1.0)
	draw_circle(center, radius, Color(0.03, 0.04, 0.06, 0.48))
	draw_arc(center, radius, 0.0, TAU, 48, Color(0.8, 0.78, 0.7, 0.68), 3.0, true)
	draw_circle(center + _direction * radius, radius * 0.34, Color(0.72, 0.61, 0.43, 0.84))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _exit_tree() -> void:
	if not _direction.is_zero_approx():
		direction_changed.emit(Vector2.ZERO)
