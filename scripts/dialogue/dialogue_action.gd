class_name DialogueAction
extends Resource

@export_group("Conditions")
@export var required_flags: Array[StringName] = []
@export var forbidden_flags: Array[StringName] = []
@export var required_item_id: StringName = &""
@export_range(1, 999, 1) var required_item_count: int = 1
@export_range(1, 100, 1) var min_level: int = 1

@export_group("Effects")
@export var set_flags: Array[StringName] = []
@export_range(0, 1000000, 1) var give_xp: int = 0
@export var give_items: Array[ItemResource] = []
@export var start_quest_id: StringName = &""
