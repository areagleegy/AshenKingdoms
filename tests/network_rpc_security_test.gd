extends SceneTree

const AVATAR_SCRIPT_PATH := "res://scripts/networking/network_avatar.gd"

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var file := FileAccess.open(AVATAR_SCRIPT_PATH, FileAccess.READ)
	if file == null:
		_check(false, "network avatar source can be read")
		quit(1)
		return
	var source := file.get_as_text()
	file.close()

	_check(source.contains("@rpc(\"any_peer\", \"call_remote\", \"unreliable\")"), "movement RPC remains unreliable and client-callable")
	_check(source.contains("sender_id != owner_peer_id or sender_id <= 1"), "movement RPC verifies the owning remote peer")
	_check(source.contains("RPC_INPUT_RATE: float = 30.0"), "movement RPC has a sustained rate limit")
	_check(source.contains("RPC_INPUT_BURST: float = 60.0"), "movement RPC has a bounded burst allowance")
	_check(source.contains("_consume_rpc_input_token()"), "movement RPC consumes a rate-limit token")
	_check(source.contains("is_nan(direction.x)") and source.contains("is_inf(direction.z)"), "movement RPC rejects non-finite direction components")
	_check(source.contains("MAX_DIRECTION_LENGTH * MAX_DIRECTION_LENGTH"), "movement RPC rejects oversized direction vectors")

	print("[network-rpc-security] failures: %d" % failures)
	quit(1 if failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] %s" % description)
	else:
		failures += 1
		push_error("[FAIL] %s" % description)
