extends SceneTree

const HEALTH_SCRIPT: Script = preload("res://scripts/components/health.gd")

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var health := Node.new()
	health.set_script(HEALTH_SCRIPT)
	health.set("max_health", 100.0)
	root.add_child(health)
	await process_frame

	_check(is_equal_approx(float(health.get("current")), 100.0), "health initializes to max")
	health.call("take_damage", NAN)
	_check(is_equal_approx(float(health.get("current")), 100.0), "NaN damage is ignored")
	health.call("take_damage", INF)
	_check(is_equal_approx(float(health.get("current")), 100.0), "infinite damage is ignored")
	health.call("heal", NAN)
	_check(is_equal_approx(float(health.get("current")), 100.0), "NaN healing is ignored")
	health.call("heal", INF)
	_check(is_equal_approx(float(health.get("current")), 100.0), "infinite healing is ignored")
	health.call("set_current_health", NAN)
	_check(
		is_equal_approx(float(health.get("current")), 100.0), "NaN health assignment is ignored"
	)
	health.call("set_current_health", INF)
	_check(
		is_equal_approx(float(health.get("current")), 100.0), "infinite health assignment is ignored"
	)
	health.call("increase_max_health", INF)
	_check(is_equal_approx(float(health.get("max_health")), 100.0), "infinite max-health increase is ignored")

	print("[health-numeric-safety] checks: %d, failures: %d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
