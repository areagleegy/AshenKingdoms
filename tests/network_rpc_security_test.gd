extends SceneTree

const AVATAR_PATH := "res://scripts/networking/network_avatar.gd"
const MANAGER_PATH := "res://scripts/core/network_manager.gd"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_source_contains(AVATAR_PATH, [
		'@rpc("any_peer", "call_remote", "unreliable")',
		"sender_id != owner_peer_id",
		"sender_id <= 1",
		"_is_valid_input_direction(direction)",
		"INPUT_RATE_PER_SECOND",
		"INPUT_BURST_CAPACITY",
		"MAX_INPUT_PAYLOAD_BYTES",
		"var_to_bytes([direction, jump_down, sprint_down, attack_down])",
		"_consume_input_token()",
		"is_finite(direction.x)",
		"is_finite(direction.y)",
		"is_finite(direction.z)",
	], "avatar input RPC guards")

	_check_source_contains(MANAGER_PATH, [
		'@rpc("any_peer", "call_remote", "reliable")',
		"sender_id <= 1",
		"not multiplayer.get_peers().has(sender_id)",
		"_ready_peers.has(sender_id)",
		"RPC_RATE_PER_SECOND",
		"RPC_BURST_CAPACITY",
		"_consume_rpc_token(sender_id)",
		"_rpc_rate_limits.erase(peer_id)",
		"_ready_peers.erase(peer_id)",
	], "arena-ready RPC guards and disconnect cleanup")

	print("[network-rpc-security] checks: %d, failures: %d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check_source_contains(path: String, required_fragments: Array[String], label: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_check(false, "%s source file can be opened: %s" % [label, path])
		return
	var source := file.get_as_text()
	file.close()
	for fragment in required_fragments:
		_check(source.contains(fragment), "%s includes guard: %s" % [label, fragment])


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
