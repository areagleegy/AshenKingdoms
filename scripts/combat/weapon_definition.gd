class_name WeaponDefinition
extends Resource
## Data-only weapon configuration. Runtime combat integration is a separate step.

@export var weapon_id: StringName = &""
@export var category: StringName = &"light"
@export_range(0.0, 1000.0, 0.1) var damage: float = 0.0
@export_range(0.0, 1000.0, 0.1) var range_m: float = 0.0
@export_range(0.0, 60.0, 0.01) var windup_seconds: float = 0.0
@export_range(0.0, 10.0, 0.01) var active_seconds: float = 0.0
@export_range(0.0, 60.0, 0.01) var recovery_seconds: float = 0.0
@export_range(0.0, 1000.0, 0.1) var stamina_cost: float = 0.0
@export_range(0.0, 1000.0, 0.1) var poise_damage: float = 0.0
@export_range(0.0, 1000.0, 0.1) var weight: float = 0.0
@export_range(0, 999, 1) var ammo_capacity: int = 0
@export_range(0, 99, 1) var charges: int = 0
@export_range(0.0, 3600.0, 0.1) var cooldown_seconds: float = 0.0
@export_range(0.0, 60.0, 0.1) var charge_seconds: float = 0.0
@export var interruptible: bool = true
@export_range(0.0, 10000.0, 1.0) var durability_max: float = 100.0


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(weapon_id).strip_edges().is_empty():
		errors.append("weapon_id must not be empty")
	if not [&"light", &"medium", &"heavy", &"ranged", &"charged", &"limited"].has(category):
		errors.append("category is not supported")
	if not _is_finite_non_negative(damage):
		errors.append("damage must be finite and non-negative")
	if not _is_finite_non_negative(range_m):
		errors.append("range_m must be finite and non-negative")
	if not _is_finite_non_negative(windup_seconds):
		errors.append("windup_seconds must be finite and non-negative")
	if not _is_finite_non_negative(active_seconds):
		errors.append("active_seconds must be finite and non-negative")
	if not _is_finite_non_negative(recovery_seconds):
		errors.append("recovery_seconds must be finite and non-negative")
	if not _is_finite_non_negative(stamina_cost):
		errors.append("stamina_cost must be finite and non-negative")
	if not _is_finite_non_negative(poise_damage):
		errors.append("poise_damage must be finite and non-negative")
	if not _is_finite_non_negative(weight):
		errors.append("weight must be finite and non-negative")
	if not _is_finite_non_negative(cooldown_seconds):
		errors.append("cooldown_seconds must be finite and non-negative")
	if not _is_finite_non_negative(charge_seconds):
		errors.append("charge_seconds must be finite and non-negative")
	if ammo_capacity < 0 or charges < 0:
		errors.append("ammo_capacity and charges must be non-negative")
	if not _is_finite_non_negative(durability_max):
		errors.append("durability_max must be finite and non-negative")
	if category == &"charged" and charge_seconds <= 0.0:
		errors.append("charged weapons require charge_seconds greater than zero")
	if category == &"limited" and ammo_capacity <= 0 and charges <= 0:
		errors.append("limited weapons require ammo or charges")
	return errors


func is_valid_definition() -> bool:
	return validation_errors().is_empty()


func _is_finite_non_negative(value: float) -> bool:
	return is_finite(value) and value >= 0.0
