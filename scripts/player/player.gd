extends CharacterBody3D

signal died(player: Node)

@export var speed: float = 6.0
@export var sprint_speed: float = 9.0
@export var jump_velocity: float = 5.5
@export var rotation_speed: float = 12.0
@export var attack_damage: float = 20.0
@export var attack_range: float = 2.6
@export var attack_cooldown: float = 0.55

@onready var health: Health = $Health
@onready var inventory: Inventory = $Inventory

var camera_pivot: Node3D
var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var _can_attack: bool = true
var is_dead: bool = false


func _ready() -> void:
	add_to_group("player")
	health.died.connect(_on_health_died)


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


func _attack() -> void:
	_can_attack = false
	var from := global_position + Vector3.UP * 0.65
	var to := from - global_transform.basis.z * attack_range
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider: Object = hit.get("collider")
		if collider is Node and collider.has_method("take_damage"):
			collider.call("take_damage", attack_damage)

	await get_tree().create_timer(attack_cooldown).timeout
	_can_attack = true


func _on_health_died() -> void:
	is_dead = true
	velocity = Vector3.ZERO
	died.emit(self)
