class_name Health
extends Node

signal health_changed(current: float, max_value: float)
signal died

@export_range(1.0, 10000.0, 1.0) var max_health: float = 100.0
var current: float = 100.0


func _ready() -> void:
	if not is_finite(max_health):
		max_health = 100.0
	else:
		max_health = clampf(max_health, 1.0, 10000.0)
	current = max_health
	health_changed.emit(current, max_health)


func take_damage(amount: float) -> void:
	if not is_finite(amount) or amount <= 0.0 or not is_finite(current) or current <= 0.0:
		return
	var was_alive := current > 0.0
	current = clampf(current - amount, 0.0, max_health)
	health_changed.emit(current, max_health)
	if was_alive and current <= 0.0:
		died.emit()


func heal(amount: float) -> void:
	if not is_finite(amount) or amount <= 0.0 or not is_finite(current) or current <= 0.0:
		return
	current = clampf(current + amount, 0.0, max_health)
	health_changed.emit(current, max_health)


func set_current_health(value: float) -> void:
	if not is_finite(value):
		return
	var was_alive := current > 0.0
	current = clampf(value, 0.0, max_health)
	health_changed.emit(current, max_health)
	if was_alive and current <= 0.0:
		died.emit()


func increase_max_health(amount: float, heal_by_amount: bool = true) -> void:
	if not is_finite(amount) or amount <= 0.0 or amount > 10000.0 - max_health:
		return
	max_health += amount
	if heal_by_amount:
		current = minf(current + amount, max_health)
	else:
		current = minf(current, max_health)
	health_changed.emit(current, max_health)


func is_dead() -> bool:
	return current <= 0.0
