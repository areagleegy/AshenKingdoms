extends SceneTree

const ProgressionRules: Script = preload("res://scripts/domain/progression_rules.gd")

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(ProgressionRules.required_xp_for_level(1) == 100, "level 1 requires 100 XP")
	_check(ProgressionRules.required_xp_for_level(2) == 150, "level 2 requires 150 XP")
	_check(ProgressionRules.required_xp_for_level(3) == 200, "level 3 requires 200 XP")
	_check(ProgressionRules.required_xp_for_level(50) == 2550, "level 50 follows the existing progression curve")
	_check(
		ProgressionRules.required_xp_for_level(4) - ProgressionRules.required_xp_for_level(3) == 50,
		"the XP threshold increases by 50 for each level"
	)

	# Full curve: every level 1..50 must satisfy the linear step.
	var expected: int = 100
	var curve_ok: bool = true
	for lvl in range(1, 51):
		var actual: int = ProgressionRules.required_xp_for_level(lvl)
		if actual != expected:
			curve_ok = false
			push_error("[FAIL] curve mismatch at level %d: expected %d, got %d" % [
				lvl, expected, actual
			])
			break
		expected += 50
	_check(curve_ok, "required_xp_for_level follows the linear curve for levels 1..50")

	print("[domain-progression] checks: %d, failures: %d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
