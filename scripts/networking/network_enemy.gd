extends CharacterBody3D

signal died(enemy: Node, attacker_peer_id: int)

enum AIState {
	IDLE,
	PATROL,
	CHASE,
	ATTACK_WINDUP,
	ATTACK_COOLDOWN,
	RETURN_HOME,
	DEAD
}

const DETECTION_RADIUS: float = 15.0
const LEASH_RADIUS: float = 25.0
const ATTACK_RANGE: float = 2.1
const ATTACK_DAMAGE: float = 12.0
const ATTACK_WINDUP_SECONDS: float = 0.45
const ATTACK_COOLDOWN_SECONDS: float = 1.15
const PATROL_SPEED: float = 1.6
const CHASE_SPEED: float = 2.8
const RETURN_SPEED: float = 3.2

@export var max_health: float = 85.0

var enemy_slot: int = 1
var current_health: float = 85.0
var ai_state: int = AIState.IDLE
var is_dead: bool = false

var _home_position: Vector3 = Vector3.ZERO
var _state_elapsed: float = 0.0
var _attack_target_peer_id: int = 0
var _last_attacker_peer_id: int = 0
var _patrol_index: int = 0
var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var _death_emitted: bool = false

@onready var _body_mesh: MeshInstance3D = $BodyMesh


func configure_spawn(slot: int) -> void:
	enemy_slot = maxi(1, slot)
	set_multiplayer_authority(1, true)
	position = _spawn_position(enemy_slot)
	_home_position = position
	current_health = max_health


func _ready() -> void:
	add_to_group("network_enemies")
	_home_position = global_position
	current_health = clampf(current_health, 0.0, max_health)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.24, 0.30, 0.38, 1.0)
	material.roughness = 0.85
	_body_mesh.material_override = material
	if not multiplayer.is_server() or OS.get_environment("ASHEN_TEST_COMBAT") == "1":
		set_physics_process(false)


func _process(_delta: float) -> void:
	if not is_instance_valid(_body_mesh):
		return
	var material := _body_mesh.material_override as StandardMaterial3D
	if material == null:
		return
	if is_dead:
		material.albedo_color = Color(0.12, 0.12, 0.14, 1.0)
	else:
		var health_ratio := clampf(current_health / maxf(max_health, 1.0), 0.0, 1.0)
		material.albedo_color = Color(0.24 + 0.28 * (1.0 - health_ratio), 0.30 * health_ratio, 0.38 * health_ratio + 0.12, 1.0)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or is_dead:
		return

	_state_elapsed += delta
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	var target := _find_nearest_living_player()
	var distance_to_target := INF
	if is_instance_valid(target):
		distance_to_target = global_position.distance_to(target.global_position)

	if is_instance_valid(target) and distance_to_target <= DETECTION_RADIUS:
		if distance_to_target <= ATTACK_RANGE:
			_server_update_attack_state(target, delta)
		else:
			_attack_target_peer_id = int(target.get("owner_peer_id"))
			_set_state(AIState.CHASE)
			_move_toward_point(target.global_position, CHASE_SPEED, delta)
	else:
		if global_position.distance_to(_home_position) > LEASH_RADIUS:
			_set_state(AIState.RETURN_HOME)
			_move_toward_point(_home_position, RETURN_SPEED, delta)
		elif ai_state == AIState.CHASE or ai_state == AIState.ATTACK_WINDUP or ai_state == AIState.ATTACK_COOLDOWN:
			_set_state(AIState.RETURN_HOME)
			_move_toward_point(_home_position, RETURN_SPEED, delta)
		else:
			_server_patrol(delta)

	move_and_slide()


func apply_damage_from_server(amount: float, attacker_peer_id: int) -> void:
	if not multiplayer.is_server() or amount <= 0.0 or is_dead or current_health <= 0.0:
		return
	_qa_record_event("combat.network_enemy_damage_received", {"amount": amount})
	current_health = clampf(current_health - amount, 0.0, max_health)
	if OS.get_environment("ASHEN_TEST_COMBAT") == "1":
		print("[combat-server] enemy_health slot=%d health=%.2f" % [enemy_slot, current_health])
	_last_attacker_peer_id = attacker_peer_id
	if current_health <= 0.0:
		is_dead = true
		_set_state(AIState.DEAD)
		velocity = Vector3.ZERO
		_qa_record_event("combat.network_enemy_died")
		if not _death_emitted:
			_death_emitted = true
			died.emit(self, _last_attacker_peer_id)


func _server_update_attack_state(target: Node3D, delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, CHASE_SPEED * 8.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, CHASE_SPEED * 8.0 * delta)
	var target_id := int(target.get("owner_peer_id"))

	if ai_state != AIState.ATTACK_WINDUP and ai_state != AIState.ATTACK_COOLDOWN:
		_attack_target_peer_id = target_id
		_set_state(AIState.ATTACK_WINDUP)
		return

	if _attack_target_peer_id != target_id and ai_state == AIState.ATTACK_WINDUP:
		_attack_target_peer_id = target_id
		_set_state(AIState.ATTACK_WINDUP)
		return

	if ai_state == AIState.ATTACK_WINDUP and _state_elapsed >= ATTACK_WINDUP_SECONDS:
		var fresh_target := _find_player_by_id(_attack_target_peer_id)
		if is_instance_valid(fresh_target) and global_position.distance_to(fresh_target.global_position) <= ATTACK_RANGE + 0.25:
			_qa_record_event("combat.network_enemy_attack", {"damage": ATTACK_DAMAGE})
			fresh_target.call("apply_damage_from_server", ATTACK_DAMAGE, 0)
		_set_state(AIState.ATTACK_COOLDOWN)
	elif ai_state == AIState.ATTACK_COOLDOWN and _state_elapsed >= ATTACK_COOLDOWN_SECONDS:
		_set_state(AIState.CHASE)


func _server_patrol(delta: float) -> void:
	if global_position.distance_to(_home_position) > 1.0:
		_set_state(AIState.RETURN_HOME)
		_move_toward_point(_home_position, RETURN_SPEED, delta)
		return

	if ai_state == AIState.RETURN_HOME:
		_set_state(AIState.IDLE)
		return

	if ai_state == AIState.IDLE:
		velocity.x = move_toward(velocity.x, 0.0, PATROL_SPEED * 5.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, PATROL_SPEED * 5.0 * delta)
		if _state_elapsed >= 1.0:
			_patrol_index = (_patrol_index + 1) % 4
			_set_state(AIState.PATROL)
		return

	var patrol_target := _home_position + _patrol_offset(_patrol_index)
	if global_position.distance_to(patrol_target) <= 0.8:
		_set_state(AIState.IDLE)
		return
	_move_toward_point(patrol_target, PATROL_SPEED, delta)


func _move_toward_point(target_position: Vector3, speed: float, delta: float) -> void:
	var offset := target_position - global_position
	offset.y = 0.0
	if offset.length_squared() <= 0.01:
		velocity.x = move_toward(velocity.x, 0.0, speed * 5.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, speed * 5.0 * delta)
		return
	var direction := offset.normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), 8.0 * delta)


func _find_nearest_living_player() -> Node3D:
	var nearest: Node3D
	var best_distance := DETECTION_RADIUS
	for node in get_tree().get_nodes_in_group("network_players"):
		if not is_instance_valid(node) or bool(node.get("is_dead")):
			continue
		if float(node.get("current_health")) <= 0.0:
			continue
		var distance := global_position.distance_to(node.global_position)
		if distance < best_distance:
			best_distance = distance
			nearest = node as Node3D
	return nearest


func _find_player_by_id(peer_id: int) -> Node3D:
	for node in get_tree().get_nodes_in_group("network_players"):
		if is_instance_valid(node) and int(node.get("owner_peer_id")) == peer_id:
			if not bool(node.get("is_dead")) and float(node.get("current_health")) > 0.0:
				return node as Node3D
	return null


func _set_state(next_state: int) -> void:
	if ai_state == next_state:
		return
	var previous_state := ai_state
	ai_state = next_state
	_qa_record_event("combat.network_enemy_state_changed", {"previous_state": previous_state, "next_state": next_state})
	_state_elapsed = 0.0


func _patrol_offset(index: int) -> Vector3:
	var offsets: Array[Vector3] = [
		Vector3(3.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 3.0),
		Vector3(-3.0, 0.0, 0.0),
		Vector3(0.0, 0.0, -3.0)
	]
	return offsets[index % offsets.size()]


func _spawn_position(slot: int) -> Vector3:
	var spawn_points: Array[Vector3] = [
		Vector3(0.0, 0.92, -7.0),
		Vector3(6.0, 0.92, -7.0),
		Vector3(-6.0, 0.92, -7.0),
		Vector3(8.0, 0.92, 2.0),
		Vector3(-8.0, 0.92, 2.0),
		Vector3(0.0, 0.92, -12.0)
	]
	return spawn_points[(slot - 1) % spawn_points.size()]


# QA hooks are inert in regular builds and record state numbers, never chat text.
func _qa_record_event(event_name: String, details: Dictionary = {}) -> void:
	if not OS.has_feature("qa_tools"):
		return
	var reporter := get_node_or_null("/root/QAReporter")
	if reporter != null:
		reporter.call("record_event", event_name, details)
