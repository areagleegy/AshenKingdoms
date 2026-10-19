extends SceneTree

const RulesScript = preload("res://scripts/networking/battle_royale_rules.gd")

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var rules = RulesScript.new()
	_check(not rules.try_start(1), "match does not start with fewer than two players")
	_check(rules.phase == RulesScript.Phase.WAITING, "match remains waiting before minimum players")
	_check(rules.try_start(2), "match starts when two players are alive")
	_check(rules.phase == RulesScript.Phase.ACTIVE, "started match enters active phase")
	_check(is_equal_approx(rules.get_safe_radius(), 32.0), "safe zone begins at the configured radius")
	_check(rules.is_inside_safe_zone(Vector3(10.0, 50.0, 10.0)), "safe zone checks horizontal distance and ignores height")
	_check(not rules.is_inside_safe_zone(Vector3(40.0, 0.0, 0.0)), "position outside safe zone is detected")
	rules.advance(90.0, 2)
	_check(is_equal_approx(rules.get_safe_radius(), 18.5), "safe radius shrinks linearly halfway through the match")
	_check(rules.phase == RulesScript.Phase.ACTIVE, "match remains active while the zone shrinks")
	rules.advance(90.0, 2)
	_check(rules.phase == RulesScript.Phase.FINAL_CIRCLE, "match enters final circle when the radius reaches its minimum")
	_check(is_equal_approx(rules.get_safe_radius(), 5.0), "safe zone never shrinks below its configured minimum")
	rules.advance(1.0, 1, 17)
	_check(rules.phase == RulesScript.Phase.FINISHED, "match finishes when one survivor remains")
	_check(rules.winner_peer_id == 17, "last surviving peer is recorded as winner")
	rules.advance(10.0, 0)
	_check(rules.winner_peer_id == 17, "finished match cannot overwrite its winner")
	var empty_match = RulesScript.new()
	_check(empty_match.try_start(2), "second match instance starts independently")
	empty_match.advance(1.0, 0)
	_check(empty_match.phase == RulesScript.Phase.FINISHED, "match with no survivors ends without a winner")
	_check(empty_match.winner_peer_id == 0, "empty match does not invent a winner")
	_check(RulesScript.LONG_TERM_TARGET_PLAYERS == 100, "100 players is explicitly recorded as a long-term target")
	print("[battle-royale-rules] failures: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
