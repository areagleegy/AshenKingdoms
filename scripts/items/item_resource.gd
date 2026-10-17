class_name ItemResource
extends Resource

enum Type { CONSUMABLE, WEAPON, ARMOR, MATERIAL, QUEST }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

@export var id: StringName = &""
@export var display_name: String = "عنصر"
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var type: Type = Type.MATERIAL
@export var rarity: Rarity = Rarity.COMMON
@export_range(1, 999, 1) var max_stack: int = 99
@export_range(0, 999999, 1) var value: int = 0

@export_group("Combat")
@export var attack_bonus: float = 0.0
@export var defense_bonus: float = 0.0
@export var heal_amount: float = 0.0


func is_equippable() -> bool:
	return type == Type.WEAPON or type == Type.ARMOR


func is_consumable() -> bool:
	return type == Type.CONSUMABLE


func is_stackable() -> bool:
	return max_stack > 1
