extends Node

signal quest_updated(title: String, description: String, current: int, target: int)
signal quest_completed(title: String, reward_xp: int)

const QUEST_DEFINITIONS: Dictionary = {
	"ash_trail": {
		"title": "اقتفاء الرماد",
		"description": "اهزم ثلاثة من أشباح الرماد.",
		"target": 3,
		"reward_xp": 75
	}
}

var progression: Node
var quest_id: StringName = &""
var title: String = "لا توجد مهمة نشطة"
var description: String = "تحدث إلى الشيخ لقبول مهمة."
var target: int = 3
var progress: int = 0
var reward_xp: int = 75
var active: bool = false


func start_default_quest() -> bool:
	return start_quest(&"ash_trail")


func start_quest(requested_id: StringName) -> bool:
	var key := String(requested_id)
	if not QUEST_DEFINITIONS.has(key):
		push_warning("Unknown quest id: %s" % key)
		return false

	if quest_id == requested_id:
		if active:
			return true
		if progress >= target:
			return false

	var definition: Dictionary = QUEST_DEFINITIONS[key]
	quest_id = requested_id
	title = String(definition.get("title", "مهمة"))
	description = String(definition.get("description", ""))
	target = maxi(1, int(definition.get("target", 1)))
	reward_xp = maxi(0, int(definition.get("reward_xp", 0)))
	progress = 0
	active = true
	refresh_ui()
	return true


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
	if quest_id == &"":
		quest_updated.emit("لا توجد مهمة نشطة", "تحدث إلى الشيخ لقبول مهمة.", 0, target)
		return
	quest_updated.emit(title, description, progress, target)


func to_save_data() -> Dictionary:
	return {
		"id": String(quest_id),
		"title": title,
		"progress": progress,
		"active": active
	}


func load_state(data: Dictionary) -> void:
	if data.is_empty():
		quest_id = &""
		title = "لا توجد مهمة نشطة"
		description = "تحدث إلى الشيخ لقبول مهمة."
		progress = 0
		active = false
		refresh_ui()
		return

	var saved_id := StringName(str(data.get("id", "")))
	# Backward compatibility with save files created before quests had IDs.
	if saved_id == &"" and (bool(data.get("active", false)) or int(data.get("progress", 0)) > 0):
		saved_id = &"ash_trail"

	var key := String(saved_id)
	if saved_id == &"" or not QUEST_DEFINITIONS.has(key):
		quest_id = &""
		title = "لا توجد مهمة نشطة"
		description = "تحدث إلى الشيخ لقبول مهمة."
		progress = 0
		active = false
		refresh_ui()
		return

	var definition: Dictionary = QUEST_DEFINITIONS[key]
	quest_id = saved_id
	title = String(definition.get("title", data.get("title", "مهمة")))
	description = String(definition.get("description", ""))
	target = maxi(1, int(definition.get("target", 1)))
	reward_xp = maxi(0, int(definition.get("reward_xp", 0)))
	progress = clampi(int(data.get("progress", 0)), 0, target)
	active = bool(data.get("active", progress < target))
	if progress >= target:
		active = false
	refresh_ui()
