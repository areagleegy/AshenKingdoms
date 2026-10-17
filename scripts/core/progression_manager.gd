extends Node

signal experience_changed(experience: int, required: int, level: int)
signal level_up(new_level: int)

@export_range(1, 100, 1) var max_level: int = 50
var level: int = 1
var experience: int = 0


func xp_to_next_level() -> int:
	return 100 + ((level - 1) * 50)


func add_experience(amount: int) -> void:
	if amount <= 0 or level >= max_level:
		return
	experience += amount
	while level < max_level:
		var required := xp_to_next_level()
		if experience < required:
			break
		experience -= required
		level += 1
		level_up.emit(level)
	if level >= max_level:
		experience = mini(experience, xp_to_next_level())
	experience_changed.emit(experience, xp_to_next_level(), level)


func restore_state(saved_level: int, saved_experience: int) -> void:
	level = clampi(saved_level, 1, max_level)
	experience = clampi(saved_experience, 0, xp_to_next_level())
	experience_changed.emit(experience, xp_to_next_level(), level)
