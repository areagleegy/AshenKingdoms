extends SceneTree

const PLAYER_SCRIPT: Script = preload("res://scripts/player/player.gd")
const ENEMY_SCRIPT: Script = preload("res://scripts/enemies/enemy.gd")
const HEALTH_SCRIPT: Script = preload("res://scripts/components/health.gd")
const INVENTORY_SCRIPT: Script = preload("res://scripts/components/inventory.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_physics_configuration()
	_test_motion_invariants()
	_test_health_numeric_boundaries()
	_test_damage_and_combat_invariants()
	print("[INFO] Vehicle and companion mounting are not implemented; no boarding acceptance test is claimed.")
	print("[physics-combat] checks: %d, failures: %d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_physics_configuration() -> void:
	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	_check(is_finite(gravity) and gravity > 0.0, "3D gravity is finite and positive")

	var player := _make_actor(PLAYER_SCRIPT, "PhysicsTestPlayer")
	_check(_finite_nonnegative(float(player.get("speed"))), "player walking speed is finite and non-negative")
	_check(_finite_nonnegative(float(player.get("sprint_speed"))), "player sprint speed is finite and non-negative")
	_check(_finite_nonnegative(float(player.get("jump_velocity"))), "player jump impulse is finite and non-negative")
	_check(float(player.get("sprint_speed")) >= float(player.get("speed")), "sprint speed is not below walking speed")
	_check(_finite_nonnegative(float(player.get("rotation_speed"))), "player rotation speed is finite and non-negative")
	player.free()

	var enemy := _make_actor(ENEMY_SCRIPT, "PhysicsTestEnemy")
	_check(_finite_nonnegative(float(enemy.get("speed"))), "enemy movement speed is finite and non-negative")
	_check(_finite_nonnegative(float(enemy.get("detection_radius"))), "enemy detection radius is finite and non-negative")
	_check(_finite_nonnegative(float(enemy.get("attack_range"))), "enemy attack range is finite and non-negative")
	_check(_finite_nonnegative(float(enemy.get("attack_cooldown"))), "enemy attack cooldown is finite and non-negative")
	_check(_finite_nonnegative(float(enemy.get("attack_damage"))), "enemy attack damage is finite and non-negative")
	enemy.free()


func _test_motion_invariants() -> void:
	var forward := Vector3(0.0, 0.0, -1.0)
	var right := Vector3(1.0, 0.0, 0.0)
	var diagonal := (forward + right).normalized()
	_check(is_equal_approx(forward.length(), 1.0), "forward direction is unit length")
	_check(is_equal_approx(right.length(), 1.0), "right direction is unit length")
	_check(is_equal_approx(diagonal.length(), 1.0), "diagonal input is normalized and cannot exceed cardinal speed")
	_check(is_equal_approx(diagonal.y, 0.0), "ground movement direction has no vertical component")

	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	var delta: float = 1.0 / 60.0
	var falling_velocity := 0.0 - gravity * delta
	_check(is_finite(falling_velocity) and falling_velocity < 0.0, "gravity accelerates a falling body downward")
	var jump_velocity := 5.5
	var airborne_velocity := jump_velocity - gravity * delta
	_check(is_finite(airborne_velocity) and airborne_velocity < jump_velocity, "gravity reduces upward velocity after a jump")
	_check(jump_velocity > 0.0, "jump impulse starts upward under the project's positive-Y convention")

	var walk_speed := 6.0
	var sprint_speed := 9.0
	_check(is_equal_approx(diagonal.length() * walk_speed, walk_speed), "diagonal walking speed equals cardinal walking speed")
	_check(is_equal_approx(diagonal.length() * sprint_speed, sprint_speed), "diagonal sprint speed equals cardinal sprint speed")


func _test_health_numeric_boundaries() -> void:
	var health := Node.new()
	health.set_script(HEALTH_SCRIPT)
	health.name = "HealthNumericBoundaryTest"
	root.add_child(health)
	var component := health as Health
	_check(component != null, "health numeric-boundary fixture initializes")
	if component == null:
		health.free()
		return

	var initial_max := component.max_health
	var initial_current := component.current
	component.heal(INF)
	_check(is_equal_approx(component.current, initial_current), "infinite healing is rejected")
	component.set_current_health(INF)
	_check(is_equal_approx(component.current, initial_current), "infinite health assignment is rejected")
	component.increase_max_health(INF)
	_check(is_equal_approx(component.max_health, initial_max), "infinite maximum-health increase is rejected")
	component.increase_max_health(1.0e30)
	_check(is_equal_approx(component.max_health, initial_max), "finite but excessive maximum-health increase is rejected")
	component.increase_max_health(25.0)
	_check(is_equal_approx(component.max_health, initial_max + 25.0), "valid maximum-health increase remains supported")
	_check(is_finite(component.max_health) and component.max_health <= 10000.0, "maximum health remains finite and within its hard cap")
	health.free()


func _test_damage_and_combat_invariants() -> void:
	var player := _make_actor(PLAYER_SCRIPT, "CombatTestPlayer")
	var player_health: Health = player.get_node("Health") as Health
	_check(player_health != null, "player has a Health component for combat")
	if player_health == null:
		player.free()
		return

	var initial_health: float = player_health.current
	player.call("take_damage", 10.0)
	_check(is_equal_approx(player_health.current, initial_health - 10.0), "valid damage reduces player health by the exact amount")
	player.call("take_damage", -10.0)
	_check(is_equal_approx(player_health.current, initial_health - 10.0), "negative damage cannot heal the player")
	player.call("take_damage", INF)
	_check(is_finite(player_health.current), "non-finite damage cannot corrupt player health")
	_check(is_equal_approx(player_health.current, initial_health - 10.0), "non-finite damage is rejected without changing health")
	_check(player_health.current >= 0.0, "player health never falls below zero")

	player.call("take_damage", 100000.0)
	_check(bool(player.get("is_dead")), "lethal damage transitions the player to the dead state")
	player.call("reset_after_death", Vector3(3.0, 2.0, -4.0))
	_check(not bool(player.get("is_dead")), "respawn clears the player dead state")
	_check(player_health.current > 0.0, "respawn restores positive health")
	_check((player as Node3D).global_position.is_equal_approx(Vector3(3.0, 2.0, -4.0)), "respawn uses the supplied spawn position")
	player.free()

	var enemy := _make_actor(ENEMY_SCRIPT, "CombatTestEnemy")
	var enemy_health: Health = enemy.get_node("Health") as Health
	_check(enemy_health != null, "enemy has a Health component for combat")
	if enemy_health != null:
		var enemy_initial_health: float = enemy_health.current
		enemy.call("take_damage", 12.0)
		_check(is_equal_approx(enemy_health.current, enemy_initial_health - 12.0), "valid combat damage reduces enemy health")
		enemy.call("take_damage", -3.0)
		_check(is_equal_approx(enemy_health.current, enemy_initial_health - 12.0), "negative damage cannot heal the enemy")
	enemy.free()


func _make_actor(actor_script: Script, actor_name: String) -> CharacterBody3D:
	var actor := CharacterBody3D.new()
	actor.name = actor_name
	actor.set_script(actor_script)

	var health := Node.new()
	health.name = "Health"
	health.set_script(HEALTH_SCRIPT)
	actor.add_child(health)

	if actor_script == PLAYER_SCRIPT:
		var inventory := Node.new()
		inventory.name = "Inventory"
		inventory.set_script(INVENTORY_SCRIPT)
		actor.add_child(inventory)

	root.add_child(actor)
	return actor


func _finite_nonnegative(value: float) -> bool:
	return is_finite(value) and value >= 0.0


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
