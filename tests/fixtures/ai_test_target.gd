extends Node3D

var current_health: float = 100.0
var damage_received: float = 0.0
var is_dead: bool = false


func take_damage(amount: float) -> void:
	if amount <= 0.0 or is_dead:
		return
	damage_received += amount
	current_health = maxf(current_health - amount, 0.0)
	is_dead = current_health <= 0.0
