extends CharacterBody3D

const INPUT_SEND_INTERVAL: float = 0.05
const INPUT_TIMEOUT_MSEC: int = 350

@export var move_speed: float = 5.0
@export var jump_velocity: float = 5.5
@export var rotation_speed: float = 10.0

@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/SpringArm3D/Camera3D
@onready var visual_mesh: MeshInstance3D = $VisualRoot/BodyMesh

var owner_peer_id: int = 1
var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var _requested_direction: Vector3 = Vector3.ZERO
var _jump_buffered: bool = false
var _last_jump_down: bool = false
var _last_input_msec: int = 0
var _input_send_accumulator: float = 0.0


func configure_owner(peer_id: int) -> void:
	owner_peer_id = maxi(1, peer_id)
	# The server remains authoritative for all replicated movement state.
	set_multiplayer_authority(1, true)
	position = _spawn_position(owner_peer_id)


func _ready() -> void:
	add_to_group("network_players")
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.from_hsv(fposmod(float(owner_peer_id) * 0.173, 1.0), 0.56, 0.88)
	material.roughness = 0.78
	visual_mesh.material_override = material

	var local_owner := _owns_local_input()
	camera.current = local_owner and DisplayServer.get_name() != "headless"
	camera_rig.set_process_unhandled_input(local_owner)
	if local_owner and not (OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		if owner_peer_id == 1:
			_set_requested_input(_read_world_direction(), Input.is_action_pressed("jump"))
		_server_step(delta)
		return

	if not _owns_local_input():
		return

	_input_send_accumulator += delta
	if _input_send_accumulator >= INPUT_SEND_INTERVAL:
		_input_send_accumulator = 0.0
		rpc_id(1, "_rpc_submit_input", _read_world_direction(), Input.is_action_pressed("jump"))


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_submit_input(direction: Vector3, jump_down: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != owner_peer_id or sender_id <= 1:
		return

	var safe_direction := Vector3(direction.x, 0.0, direction.z)
	if safe_direction.length_squared() > 1.0:
		safe_direction = safe_direction.normalized()
	_set_requested_input(safe_direction, jump_down)
	_last_input_msec = Time.get_ticks_msec()


func _set_requested_input(direction: Vector3, jump_down: bool) -> void:
	_requested_direction = Vector3(direction.x, 0.0, direction.z)
	if _requested_direction.length_squared() > 1.0:
		_requested_direction = _requested_direction.normalized()
	if jump_down and not _last_jump_down:
		_jump_buffered = true
	_last_jump_down = jump_down


func _server_step(delta: float) -> void:
	if owner_peer_id > 1 and Time.get_ticks_msec() - _last_input_msec > INPUT_TIMEOUT_MSEC:
		_requested_direction = Vector3.ZERO
		_jump_buffered = false

	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	if _jump_buffered and is_on_floor():
		velocity.y = jump_velocity
		_jump_buffered = false

	velocity.x = _requested_direction.x * move_speed
	velocity.z = _requested_direction.z * move_speed
	if _requested_direction.length_squared() > 0.001:
		var target_y := atan2(-_requested_direction.x, -_requested_direction.z)
		rotation.y = lerp_angle(rotation.y, target_y, rotation_speed * delta)

	move_and_slide()


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
		# The arena uses a left-side virtual pad; right-side drags look around.
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
