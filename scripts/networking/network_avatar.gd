extends CharacterBody3D

const INPUT_SEND_INTERVAL: float = 0.05
const INPUT_MIN_INTERVAL_MSEC: int = 10
const INPUT_TIMEOUT_MSEC: int = 350
const MAX_LEVEL: int = 50
const QUEST_TARGET: int = 3
const QUEST_REWARD_XP: int = 75

@export var move_speed: float = 5.0
@export var sprint_speed: float = 7.5
@export var jump_velocity: float = 5.5
@export var rotation_speed: float = 10.0
@export var attack_damage: float = 20.0
@export var attack_range: float = 2.7
@export var attack_cooldown: float = 0.65
@export var max_health: float = 100.0

@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/SpringArm3D/Camera3D
@onready var visual_mesh: MeshInstance3D = $VisualRoot/BodyMesh

var owner_peer_id: int = 1
var current_health: float = 100.0
var level: int = 1
var experience: int = 0
var quest_progress: int = 0
var quest_completed: bool = false
var is_dead: bool = false

var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var _requested_direction: Vector3 = Vector3.ZERO
var _sprint_requested: bool = false
var _jump_buffered: bool = false
var _attack_requested: bool = false
var _last_jump_down: bool = false
var _last_attack_down: bool = false
var _last_input_msec: int = 0
var _last_input_attempt_msec: int = -1
var _next_attack_msec: int = 0
var _death_generation: int = 0
var _input_send_accumulator: float = 0.0
var _base_color: Color = Color.WHITE


func configure_owner(peer_id: int) -> void:
	owner_peer_id = maxi(1, peer_id)
	set_multiplayer_authority(1, true)
	position = _spawn_position(owner_peer_id)
	current_health = max_health


func _ready() -> void:
	add_to_group("network_players")
	var material := StandardMaterial3D.new()
	_base_color = Color.from_hsv(fposmod(float(owner_peer_id) * 0.173, 1.0), 0.56, 0.88)
	material.albedo_color = _base_color
	material.roughness = 0.78
	visual_mesh.material_override = material

	var local_owner := _owns_local_input()
	camera.current = local_owner and DisplayServer.get_name() != "headless"
	set_process_unhandled_input(local_owner)
	if local_owner and not (OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	var material := visual_mesh.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = Color(0.14, 0.12, 0.16, 1.0) if is_dead else _base_color


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		if owner_peer_id == 1 and not is_dead:
			_set_requested_input(
				_read_world_direction(),
				Input.is_action_pressed("jump"),
				Input.is_action_pressed("sprint"),
				Input.is_action_pressed("attack")
			)
		_server_step(delta)
		return

	if not _owns_local_input() or is_dead:
		return

	_input_send_accumulator += delta
	if _input_send_accumulator >= INPUT_SEND_INTERVAL:
		_input_send_accumulator = 0.0
		rpc_id(
			1,
			"_rpc_submit_input",
			_read_world_direction(),
			Input.is_action_pressed("jump"),
			Input.is_action_pressed("sprint"),
			Input.is_action_pressed("attack")
		)


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_submit_input(direction: Vector3, jump_down: bool, sprint_down: bool, attack_down: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != owner_peer_id or sender_id <= 1 or is_dead:
		return
	var now_msec := Time.get_ticks_msec()
	if not _try_validate_input_attempt(direction, now_msec):
		return

	var safe_direction := Vector3(direction.x, 0.0, direction.z)
	if safe_direction.length_squared() > 1.0:
		safe_direction = safe_direction.normalized()
	_set_requested_input(safe_direction, jump_down, sprint_down, attack_down)
	_last_input_msec = now_msec


func _try_validate_input_attempt(direction: Vector3, now_msec: int) -> bool:
	if not _try_mark_input_attempt(now_msec):
		return false
	return _is_valid_network_direction(direction)


func _try_mark_input_attempt(now_msec: int) -> bool:
	if _last_input_attempt_msec >= 0 and now_msec - _last_input_attempt_msec < INPUT_MIN_INTERVAL_MSEC:
		return false
	_last_input_attempt_msec = now_msec
	return true


func _is_valid_network_direction(direction: Vector3) -> bool:
	# Clients should send finite, horizontal, normalized-or-near-normalized intent only.
	return (
		direction.is_finite()
		and absf(direction.y) <= 0.001
		and direction.length_squared() <= 1.05
	)


func _set_requested_input(direction: Vector3, jump_down: bool, sprint_down: bool, attack_down: bool) -> void:
	_requested_direction = Vector3(direction.x, 0.0, direction.z)
	if _requested_direction.length_squared() > 1.0:
		_requested_direction = _requested_direction.normalized()
	_sprint_requested = sprint_down
	if jump_down and not _last_jump_down:
		_jump_buffered = true
	if attack_down and not _last_attack_down:
		_attack_requested = true
	_last_jump_down = jump_down
	_last_attack_down = attack_down


func _server_step(delta: float) -> void:
	if is_dead or current_health <= 0.0:
		velocity = Vector3.ZERO
		return

	if owner_peer_id > 1 and Time.get_ticks_msec() - _last_input_msec > INPUT_TIMEOUT_MSEC:
		_requested_direction = Vector3.ZERO
		_sprint_requested = false
		_jump_buffered = false
		_attack_requested = false

	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	if _jump_buffered and is_on_floor():
		velocity.y = jump_velocity
		_jump_buffered = false

	var current_speed := sprint_speed if _sprint_requested else move_speed
	velocity.x = _requested_direction.x * current_speed
	velocity.z = _requested_direction.z * current_speed
	if _requested_direction.length_squared() > 0.001:
		var target_y := atan2(-_requested_direction.x, -_requested_direction.z)
		rotation.y = lerp_angle(rotation.y, target_y, rotation_speed * delta)

	move_and_slide()

	if _attack_requested:
		_attack_requested = false
		_server_try_attack()


func _server_try_attack() -> void:
	if not multiplayer.is_server() or is_dead or current_health <= 0.0:
		return
	var now := Time.get_ticks_msec()
	if now < _next_attack_msec:
		return
	_next_attack_msec = now + int(attack_cooldown * 1000.0)

	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var closest_enemy: Node3D
	var closest_distance := attack_range
	for candidate in get_tree().get_nodes_in_group("network_enemies"):
		if not is_instance_valid(candidate) or not candidate.has_method("apply_damage_from_server"):
			continue
		if bool(candidate.get("is_dead")):
			continue
		var offset: Vector3 = candidate.global_position - global_position
		offset.y = 0.0
		var distance: float = offset.length()
		if distance > closest_distance or distance <= 0.001:
			continue
		if forward.dot(offset.normalized()) < 0.1:
			continue
		closest_enemy = candidate as Node3D
		closest_distance = distance

	if is_instance_valid(closest_enemy):
		closest_enemy.call("apply_damage_from_server", attack_damage, owner_peer_id)


func apply_damage_from_server(amount: float, attacker_peer_id: int = 0) -> void:
	if not multiplayer.is_server() or not is_finite(amount) or amount <= 0.0 or is_dead or current_health <= 0.0:
		return
	current_health = clampf(current_health - amount, 0.0, max_health)
	if current_health <= 0.0:
		_server_begin_respawn()


func _server_begin_respawn() -> void:
	is_dead = true
	velocity = Vector3.ZERO
	_requested_direction = Vector3.ZERO
	_jump_buffered = false
	_attack_requested = false
	_death_generation += 1
	var timer := get_tree().create_timer(2.0)
	timer.timeout.connect(_server_respawn.bind(_death_generation))


func _server_respawn(generation: int) -> void:
	if not multiplayer.is_server() or not is_inside_tree() or generation != _death_generation:
		return
	global_position = _spawn_position(owner_peer_id)
	velocity = Vector3.ZERO
	current_health = max_health
	is_dead = false
	_last_jump_down = false
	_last_attack_down = false
	_last_input_msec = Time.get_ticks_msec()


func register_enemy_defeat() -> void:
	if not multiplayer.is_server():
		return
	server_grant_experience(35)
	if quest_completed:
		return
	quest_progress = mini(quest_progress + 1, QUEST_TARGET)
	if quest_progress >= QUEST_TARGET:
		quest_completed = true
		server_grant_experience(QUEST_REWARD_XP)


func server_grant_experience(amount: int) -> void:
	if not multiplayer.is_server() or amount <= 0 or level >= MAX_LEVEL:
		return
	experience += amount
	while level < MAX_LEVEL:
		var required := 100 + ((level - 1) * 50)
		if experience < required:
			break
		experience -= required
		level += 1
		max_health += 10.0
		current_health = minf(current_health + 10.0, max_health)
	if level >= MAX_LEVEL:
		experience = 0


func _read_world_direction() -> Vector3:
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input_vector.length_squared() <= 0.001:
		return Vector3.ZERO

	var forward := -camera_rig.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := camera_rig.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var direction := right * input_vector.x + forward * -input_vector.y
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	return direction


func _unhandled_input(event: InputEvent) -> void:
	if not _owns_local_input():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_apply_camera_rotation((event as InputEventMouseMotion).relative.x * 0.003, (event as InputEventMouseMotion).relative.y * 0.003)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.position.x >= get_viewport().get_visible_rect().size.x * 0.42:
			_apply_camera_rotation(drag.relative.x * 0.005, drag.relative.y * 0.005)


func _apply_camera_rotation(dx: float, dy: float) -> void:
	camera_rig.rotate_y(-dx)
	var pitch := clampf(camera_rig.rotation.x - dy, -0.85, 0.48)
	camera_rig.rotation.x = pitch


func _owns_local_input() -> bool:
	return owner_peer_id == multiplayer.get_unique_id()


func _spawn_position(peer_id: int) -> Vector3:
	var spawn_points: Array[Vector3] = [
		Vector3(0.0, 0.92, 0.0),
		Vector3(3.0, 0.92, 0.0),
		Vector3(-3.0, 0.92, 0.0),
		Vector3(0.0, 0.92, 3.0),
		Vector3(0.0, 0.92, -3.0),
		Vector3(4.0, 0.92, 3.0),
		Vector3(-4.0, 0.92, -3.0),
		Vector3(4.0, 0.92, -3.0)
	]
	return spawn_points[(peer_id - 1) % spawn_points.size()]
