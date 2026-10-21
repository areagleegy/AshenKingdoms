extends CharacterBody3D

signal died(player: Node)

const WeaponDefinitionScript: Script = preload("res://scripts/combat/weapon_definition.gd")
const CombatRuntimeScript: Script = preload("res://scripts/combat/combat_runtime.gd")

@export var speed: float = 6.0
@export var sprint_speed: float = 9.0
@export var jump_velocity: float = 5.5
@export var rotation_speed: float = 12.0
@export var attack_damage: float = 20.0
@export var attack_range: float = 2.6
@export var attack_cooldown: float = 0.55
@export var stamina_max: float = 100.0
@export var stamina_regen_per_second: float = 18.0

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
var _combat_runtime: Node
var _combat_weapon: Resource
var is_dead: bool = false
var _animation_player: AnimationPlayer
var _resolved_animations: Dictionary = {}
var _is_attacking: bool = false


func _ready() -> void:
	add_to_group("player")
	health.died.connect(_on_health_died)
	_setup_combat_runtime()
	_find_animation_player()
	_play_animation(&"idle")


func _physics_process(delta: float) -> void:
	if is_dead:
		velocity = Vector3.ZERO
		return

	if _combat_runtime != null and is_instance_valid(_combat_runtime):
		_combat_runtime.call("advance", delta)
		var phase := StringName(_combat_runtime.get("phase"))
		if phase != &"windup" and phase != &"active":
			_combat_runtime.call("restore_stamina", maxf(0.0, stamina_regen_per_second) * delta)

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

	if Input.is_action_just_pressed("attack") and _combat_runtime != null:
		if bool(_combat_runtime.call("can_start_attack")):
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
	if _combat_runtime != null and _combat_weapon != null:
		_combat_runtime.call("configure", _combat_weapon, maxf(0.0, stamina_max))
	_play_animation(&"idle")


func _setup_combat_runtime() -> void:
	_combat_weapon = WeaponDefinitionScript.new()
	_combat_weapon.set("weapon_id", &"player_default_blade")
	_combat_weapon.set("category", &"light")
	_combat_weapon.set("damage", maxf(0.0, attack_damage))
	_combat_weapon.set("range_m", maxf(0.1, attack_range))
	_combat_weapon.set("windup_seconds", 0.12)
	_combat_weapon.set("active_seconds", 0.1)
	_combat_weapon.set("recovery_seconds", 0.15)
	_combat_weapon.set("cooldown_seconds", maxf(0.0, attack_cooldown - 0.37))
	_combat_weapon.set("stamina_cost", 12.0)

	_combat_runtime = CombatRuntimeScript.new()
	_combat_runtime.name = "CombatRuntime"
	add_child(_combat_runtime)
	_combat_runtime.connect("hit_window_opened", Callable(self, "_on_combat_hit_window_opened"))
	_combat_runtime.connect("attack_finished", Callable(self, "_on_combat_attack_finished"))
	_combat_runtime.call("configure", _combat_weapon, maxf(0.0, stamina_max))


func _attack() -> void:
	if _combat_runtime == null or not bool(_combat_runtime.call("start_attack")):
		return
	_is_attacking = true
	_play_animation(&"attack")


func _on_combat_hit_window_opened(_weapon_id: StringName) -> void:
	if is_dead or not is_inside_tree():
		return
	var from := global_position + Vector3.UP * 0.65
	var to := from - global_transform.basis.z * maxf(0.1, attack_range)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider")
	if collider is Node and collider.has_method("take_damage"):
		collider.call("take_damage", maxf(0.0, attack_damage))


func _on_combat_attack_finished(_weapon_id: StringName) -> void:
	_is_attacking = false


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
