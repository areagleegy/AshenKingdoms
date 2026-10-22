extends SceneTree

const AVATAR_SCENE_PATH := "res://scenes/network/NetworkAvatar.tscn"
const AVATAR_SCRIPT_PATH := "res://scripts/networking/network_avatar.gd"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var avatar_script := load(AVATAR_SCRIPT_PATH) as Script
	_check(avatar_script != null, "network avatar script loads")
	if avatar_script == null:
		quit(1)
		return

	var source := FileAccess.get_file_as_string(AVATAR_SCRIPT_PATH)
	_check(source.contains("const RPC_INPUT_RATE: float = 30.0"), "input rate limit is configured")
	_check(source.contains("const RPC_INPUT_BURST: float = 60.0"), "input burst limit is configured")
	_check(source.contains("not is_finite(direction.x)"), "non-finite input components are rejected")
	_check(source.contains("MAX_DIRECTION_LENGTH * MAX_DIRECTION_LENGTH"), "unbounded input vectors are rejected")
	_check(source.contains("sender_id != owner_peer_id"), "RPC sender ownership is checked")

	var scene := load(AVATAR_SCENE_PATH) as PackedScene
	_check(scene != null, "network avatar scene loads")
	if scene == null:
		quit(1 if _failures > 0 else 0)
		return

	var avatar := scene.instantiate() as CharacterBody3D
	_check(avatar != null, "network avatar can be instantiated")
	if avatar == null:
		quit(1 if _failures > 0 else 0)
		return

	avatar.call("configure_owner", 2)
	root.add_child(avatar)
	avatar.set("_input_tokens", 0.0)
	avatar.set("_last_token_refill_msec", Time.get_ticks_msec())
	_check(not bool(avatar.call("_consume_input_token")), "empty token bucket rejects input")
	avatar.set("_input_tokens", 1.0)
	avatar.set("_last_token_refill_msec", Time.get_ticks_msec())
	_check(bool(avatar.call("_consume_input_token")), "available token allows input")
	_check(float(avatar.get("_input_tokens")) < 0.001, "accepted input consumes one token")

	avatar.free()
	print("[network-rpc-security] checks: %d, failures: %d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
