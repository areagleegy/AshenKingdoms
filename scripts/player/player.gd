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


func _ready() -> void:
	add_to_group("player")
	health.died.connect(_on_health_died)
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

	var current_speed := sprint_speed if Input.is_action_pressed("sprint") else speed
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
	if not is_dead:
		health.take_damage(amount)


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
