extends Node

signal quest_updated(title: String, description: String, current: int, target: int)
signal quest_completed(title: String, reward_xp: int)

const DEFAULT_QUEST_TITLE: String = "اقتفاء الرماد"
const DEFAULT_QUEST_DESCRIPTION: String = "اهزم ثلاثة من أشباح الرماد."
const DEFAULT_TARGET: int = 3
const DEFAULT_REWARD_XP: int = 75

var progression: Node
var title: String = DEFAULT_QUEST_TITLE
var description: String = DEFAULT_QUEST_DESCRIPTION
var target: int = DEFAULT_TARGET
var progress: int = 0
var reward_xp: int = DEFAULT_REWARD_XP
var active: bool = true


func start_default_quest() -> void:
	title = DEFAULT_QUEST_TITLE
	description = DEFAULT_QUEST_DESCRIPTION
	target = DEFAULT_TARGET
	reward_xp = DEFAULT_REWARD_XP
	progress = 0
	active = true
	refresh_ui()


func on_enemy_defeated(enemy_id: StringName) -> void:
	if not active or enemy_id != &"ash_wraith":
		return
	progress = mini(progress + 1, target)
	if progress >= target:
		active = false
		if is_instance_valid(progression):
			progression.call("add_experience", reward_xp)
		quest_completed.emit(title, reward_xp)
	refresh_ui()


func refresh_ui() -> void:
	quest_updated.emit(title, description, progress, target)


func to_save_data() -> Dictionary:
	return {"title": title, "progress": progress, "active": active}


func load_state(data: Dictionary) -> void:
	if data.is_empty():
		refresh_ui()
		return
	title = String(data.get("title", DEFAULT_QUEST_TITLE))
	progress = clampi(int(data.get("progress", 0)), 0, target)
	active = bool(data.get("active", progress < target))
	if progress >= target:
		active = false
	refresh_ui()
