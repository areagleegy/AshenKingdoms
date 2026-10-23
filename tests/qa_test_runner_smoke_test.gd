extends SceneTree

const RunnerScript: Script = preload("res://scripts/qa/qa_test_runner.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not RunnerScript.can_instantiate():
		push_error("QA test runner script failed to compile.")
		quit(1)
		return

	var runner := RunnerScript.new() as Node
	root.add_child(runner)
	var summary: Dictionary = runner.call("run_smoke_tests", true)
	var results: Array = summary.get("results", [])
	_check(bool(summary.get("enabled", false)), "test-mode invocation runs without the qa_tools export feature")
	_check(int(summary.get("failed", -1)) == 0, "all automated QA behavioral checks pass")
	_check(int(summary.get("skipped", 0)) >= 8, "manual real-device acceptance gates remain explicitly skipped")
	_check(_has_result(results, "combat_health_lifecycle", "pass"), "health damage/heal/death scenario is included")
	_check(_has_result(results, "dialogue_choice_branch", "pass"), "dialogue branch and invalid choice scenario is included")
	_check(_has_result(results, "quest_reward_once", "pass"), "quest reward-once scenario is included")
	_check(_has_result(results, "manual_two_device_network", "skip"), "two-device network test is not claimed as automated")

	runner.free()
	print("[qa-runner] checks: %d, failures: %d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _has_result(results: Array, test_id: String, expected_status: String) -> bool:
	for result in results:
		if result is Dictionary and str(result.get("id", "")) == test_id:
			return str(result.get("status", "")) == expected_status
	return false


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
