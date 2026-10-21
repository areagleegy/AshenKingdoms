extends CharacterBody3D

signal died(player: Node)

@export var speed: float = 6.0
@export var sprint_speed: float = 9.0
@export var jump_velocity: float = 5.5
@export var rotation_speed: float = 12.0
@export var attack_damage: float = 20.0
@export var attack_range: float = 2.6
@export var attack_cooldown: float = 0.55
@export var equipped_weapon_id: StringName = &"ash_dagger"
@export var equipped_armor_id: StringName = &""
@export var max_stamina: float = 100.0
@export var stamina_regen_per_second: float = 18.0
@export var stamina_regen_delay: float = 0.65

@onready var health: Health = $Health
@onready var inventory: Inventory = $Inventory

const ANIMATION_ALIASES: Dictionary = {
	"idle": ["idle", "stand", "breath"],
	"walk": ["walk", "walking"],
	"run": ["run", "running", "sprint"],
	"jump": ["jump", "leap"],
	"attack": ["attack", "slash", "swing", "strike"],
	"death": ["death", "die", "dead"]
}

var camera_pivot: Node3D
var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var _can_attack: bool = true
var is_dead: bool = false
var _animation_player: AnimationPlayer
var _resolved_animations: Dictionary = {}
var _is_attacking: bool = false
var current_stamina: float = 100.0
var _stamina_regen_wait: float = 0.0


func _ready() -> void:
	add_to_group("player")
	health.died.connect(_on_health_died)
	current_stamina = max_stamina
	_find_animation_player()
	_play_animation(&"idle")


func _physics_process(delta: float) -> void:
	if is_dead:
		velocity = Vector3.ZERO
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Vector3.ZERO
	if camera_pivot != null and is_instance_valid(camera_pivot):
		var forward := -camera_pivot.global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right := camera_pivot.global_transform.basis.x
		right.y = 0.0
		right = right.normalized()
		direction = (right * input_vector.x + forward * -input_vector.y).normalized()
	else:
		direction = Vector3(input_vector.x, 0.0, -input_vector.y).normalized()

	if _stamina_regen_wait > 0.0:
		_stamina_regen_wait = maxf(0.0, _stamina_regen_wait - delta)
	elif not _is_attacking:
		current_stamina = minf(max_stamina, current_stamina + stamina_regen_per_second * delta)

	var current_speed := sprint_speed if Input.is_action_pressed("sprint") else speed
	current_speed *= _get_equipment_movement_multiplier()
	velocity.x = direction.x * current_speed
	velocity.z = direction.z * current_speed

	if direction.length_squared() > 0.001:
		var target_y := atan2(-direction.x, -direction.z)
		rotation.y = lerp_angle(rotation.y, target_y, rotation_speed * delta)

	move_and_slide()

	if not _is_attacking:
		_update_animation(direction)

	if Input.is_action_just_pressed("attack") and _can_attack:
		_attack()


func take_damage(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	var final_damage := amount
	if not equipped_armor_id.is_empty():
		var catalog := get_node_or_null("/root/CombatCatalog")
		if catalog != null and catalog.has_method("calculate_damage_after_armor"):
			final_damage = float(catalog.call(
				"calculate_damage_after_armor", amount, String(equipped_armor_id)
			))
	health.take_damage(final_damage)


func reset_after_death(spawn_position: Vector3) -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	health.set_current_health(health.max_health)
	is_dead = false
	_is_attacking = false
	_can_attack = true
	_play_animation(&"idle")


func _attack() -> void:
	_can_attack = false
	_is_attacking = true
	_play_animation(&"attack")
	var weapon_profile := _get_equipped_weapon_profile()
	var stamina_cost := maxf(0.0, float(weapon_profile.get("stamina_cost", 0.0)))
	if current_stamina < stamina_cost:
		_can_attack = true
		_is_attacking = false
		return
	current_stamina = maxf(0.0, current_stamina - stamina_cost)
	_stamina_regen_wait = stamina_regen_delay
	var damage := float(weapon_profile.get("damage", attack_damage))
	var weapon_range := float(weapon_profile.get("range", attack_range))
	var windup := maxf(0.0, float(weapon_profile.get("windup_seconds", 0.0)))
	var active_time := maxf(0.0, float(weapon_profile.get("active_seconds", 0.0)))
	var recovery := maxf(0.0, float(weapon_profile.get("recovery_seconds", attack_cooldown)))
	if windup > 0.0:
		await get_tree().create_timer(windup).timeout
	if is_dead or not is_inside_tree():
		_is_attacking = false
		return
	var from := global_position + Vector3.UP * 0.65
	var to := from - global_transform.basis.z * weapon_range
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider: Object = hit.get("collider")
		if collider is Node and collider.has_method("take_damage"):
			collider.call("take_damage", damage)

	var remaining_time := active_time + recovery
	if remaining_time > 0.0:
		await get_tree().create_timer(remaining_time).timeout
	_can_attack = true
	_is_attacking = false


func equip_weapon(item_id: String) -> bool:
	var catalog := get_node_or_null("/root/CombatCatalog")
	if catalog == null or not catalog.has_method("get_weapon"):
		return false
	var profile: Dictionary = catalog.call("get_weapon", item_id)
	if profile.is_empty():
		return false
	equipped_weapon_id = StringName(item_id)
	return true


func equip_armor(item_id: String) -> bool:
	if item_id.is_empty():
		equipped_armor_id = &""
		return true
	var catalog := get_node_or_null("/root/CombatCatalog")
	if catalog == null or not catalog.has_method("get_armor"):
		return false
	var profile: Dictionary = catalog.call("get_armor", item_id)
	if profile.is_empty():
		return false
	equipped_armor_id = StringName(item_id)
	return true


func get_equipment_weight() -> float:
	var weapon_profile := _get_equipped_weapon_profile()
	var armor_profile := _get_equipped_armor_profile()
	return maxf(0.0, float(weapon_profile.get("weight", 0.0))) + maxf(0.0, float(armor_profile.get("weight", 0.0)))


func _get_equipped_armor_profile() -> Dictionary:
	var catalog := get_node_or_null("/root/CombatCatalog")
	if catalog == null or not catalog.has_method("get_armor"):
		return {}
	return catalog.call("get_armor", String(equipped_armor_id))


func _get_equipment_movement_multiplier() -> float:
	var multiplier := 1.0
	var armor_profile := _get_equipped_armor_profile()
	if not armor_profile.is_empty():
		multiplier *= clampf(float(armor_profile.get("movement_speed_multiplier", 1.0)), 0.5, 1.25)
	var catalog := get_node_or_null("/root/CombatCatalog")
	var max_carry := 30.0
	if catalog != null and catalog.has_method("get_max_carry_weight"):
		max_carry = maxf(1.0, float(catalog.call("get_max_carry_weight")))
	var load_ratio := get_equipment_weight() / max_carry
	if load_ratio > 1.0:
		multiplier *= 0.65
	elif load_ratio > 0.8:
		multiplier *= 0.82
	elif load_ratio > 0.5:
		multiplier *= 0.93
	return multiplier


func equip_weapon(item_id: String) -> bool:
	var catalog := get_node_or_null("/root/CombatCatalog")
	if catalog == null or not catalog.has_method("get_weapon"):
		return false
	var profile: Dictionary = catalog.call("get_weapon", item_id)
	if profile.is_empty():
		return false
	equipped_weapon_id = StringName(item_id)
	return true


func equip_armor(item_id: String) -> bool:
	if item_id.is_empty():
		equipped_armor_id = &""
		return true
	var catalog := get_node_or_null("/root/CombatCatalog")
	if catalog == null or not catalog.has_method("get_armor"):
		return false
	var profile: Dictionary = catalog.call("get_armor", item_id)
	if profile.is_empty():
		return false
	equipped_armor_id = StringName(item_id)
	return true


func get_equipment_weight() -> float:
	return maxf(0.0, float(_get_equipped_weapon_profile().get("weight", 0.0))) + maxf(0.0, float(_get_equipped_armor_profile().get("weight", 0.0)))


func _get_equipped_armor_profile() -> Dictionary:
	var catalog := get_node_or_null("/root/CombatCatalog")
	if catalog == null or not catalog.has_method("get_armor"):
		return {}
	return catalog.call("get_armor", String(equipped_armor_id))


func _get_equipment_movement_multiplier() -> float:
	var armor_profile := _get_equipped_armor_profile()
	var multiplier := clampf(float(armor_profile.get("movement_speed_multiplier", 1.0)), 0.5, 1.25)
	var catalog := get_node_or_null("/root/CombatCatalog")
	var max_carry := 30.0
	if catalog != null and catalog.has_method("get_max_carry_weight"):
		max_carry = maxf(1.0, float(catalog.call("get_max_carry_weight")))
	var load_ratio := get_equipment_weight() / max_carry
	if load_ratio > 1.0:
		multiplier *= 0.65
	elif load_ratio > 0.8:
		multiplier *= 0.82
	elif load_ratio > 0.5:
		multiplier *= 0.93
	return multiplier


func _get_equipped_weapon_profile() -> Dictionary:
	var catalog := get_node_or_null("/root/CombatCatalog")
	if catalog == null or not catalog.has_method("get_weapon"):
		return {}
	return catalog.call("get_weapon", String(equipped_weapon_id))


func _find_animation_player() -> void:
	var animation_nodes := find_children("*", "AnimationPlayer", true, false)
	if animation_nodes.is_empty():
		return
	_animation_player = animation_nodes[0] as AnimationPlayer
	if _animation_player == null:
		return

	for state in ANIMATION_ALIASES.keys():
		var clip_name := _find_animation_clip(String(state))
		if not clip_name.is_empty():
			_resolved_animations[String(state)] = clip_name


func _find_animation_clip(state: String) -> String:
	var aliases: Array = ANIMATION_ALIASES.get(state, [])
	var animation_names: PackedStringArray = _animation_player.get_animation_list()

	for alias_value in aliases:
		var alias_name := _normalise_animation_name(String(alias_value))
		for animation_name in animation_names:
			if _normalise_animation_name(animation_name) == alias_name:
				return animation_name

	for alias_value in aliases:
		var alias_name := _normalise_animation_name(String(alias_value))
		if alias_name.is_empty():
			continue
		for animation_name in animation_names:
			if _normalise_animation_name(animation_name).contains(alias_name):
				return animation_name

	return ""


func _normalise_animation_name(value: String) -> String:
	return value.to_lower().replace("_", "").replace("-", "").replace(" ", "").replace("|", "").replace(".", "")


func _play_animation(state: StringName) -> void:
	if _animation_player == null or not is_instance_valid(_animation_player):
		return
	var clip_name := String(_resolved_animations.get(String(state), ""))
	if clip_name.is_empty() or _animation_player.current_animation == clip_name:
		return
	_animation_player.play(clip_name)


func _update_animation(direction: Vector3) -> void:
	if not is_on_floor():
		_play_animation(&"jump")
	elif direction.length_squared() <= 0.001:
		_play_animation(&"idle")
	elif Input.is_action_pressed("sprint"):
		_play_animation(&"run")
	else:
		_play_animation(&"walk")


func _on_health_died() -> void:
	is_dead = true
	velocity = Vector3.ZERO
	_play_animation(&"death")
	died.emit(self)
