extends CharacterBody3D

signal died(enemy: Node)

@export var enemy_id: StringName = &"ash_wraith"
@export var speed: float = 3.4
@export var detection_radius: float = 13.0
@export var attack_range: float = 1.7
@export var attack_damage: float = 10.0
@export var attack_cooldown: float = 1.25
@export var experience_reward: int = 35

@onready var health: Health = $Health

var player: Node3D
var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var _next_attack_msec: int = 0


func _ready() -> void:
	add_to_group("enemies")
	health.died.connect(_on_health_died)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	if not is_instance_valid(player):
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	var offset: Vector3 = player.global_position - global_position
	offset.y = 0.0
	var distance := offset.length()

	if distance <= attack_range:
		velocity.x = move_toward(velocity.x, 0.0, speed * 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, speed * 8.0 * delta)
		_try_attack()
	elif distance <= detection_radius:
		var direction := offset.normalized()
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		var target_y := atan2(-direction.x, -direction.z)
		rotation.y = lerp_angle(rotation.y, target_y, 8.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed * 4.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, speed * 4.0 * delta)

	move_and_slide()


func take_damage(amount: float) -> void:
	health.take_damage(amount)


func _try_attack() -> void:
	var now := Time.get_ticks_msec()
	if now < _next_attack_msec:
		return
	_next_attack_msec = now + int(attack_cooldown * 1000.0)
	if is_instance_valid(player) and player.has_method("take_damage"):
		_play_sfx(&"ash_wraith_attack", -13.0)
		player.call("take_damage", attack_damage)


func _on_health_died() -> void:
	_play_sfx(&"ash_wraith_death", -7.0)
	died.emit(self)
	queue_free()


func _play_sfx(sound_id: StringName, volume_db: float = -6.0) -> void:
	var audio_feedback := get_node_or_null("/root/AudioFeedback")
	if audio_feedback != null:
		audio_feedback.call("play_sfx", sound_id, volume_db)
