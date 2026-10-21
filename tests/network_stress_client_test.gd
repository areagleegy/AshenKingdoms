extends SceneTree

const ARENA_PATH := "res://scenes/network/MultiplayerArena.tscn"
const CONNECT_TIMEOUT_MSEC := 10000
const AVATAR_TIMEOUT_MSEC := 10000
const STRESS_PACKETS := 1200

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var manager := root.get_node_or_null("NetworkManager")
	if manager == null:
		_fail("NetworkManager autoload is missing")
		quit(1)
		return

	var port_text := OS.get_environment("ASHEN_TEST_PORT")
	if not port_text.is_valid_int():
		_fail("ASHEN_TEST_PORT must contain a valid port")
		quit(1)
		return
	var port := port_text.to_int()

	var result := int(manager.call("start_client", "127.0.0.1", port))
	if result != OK:
		_fail("Client initialization failed: %s" % error_string(result))
		quit(1)
		return

	var deadline := Time.get_ticks_msec() + CONNECT_TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline and not bool(manager.call("is_connected_to_server")):
		await process_frame
	if not bool(manager.call("is_connected_to_server")):
		_fail("Client connection timed out")
		manager.call("leave_session", false)
		quit(1)
		return

	result = change_scene_to_file(ARENA_PATH)
	if result != OK:
		_fail("Could not load network arena: %s" % error_string(result))
		manager.call("leave_session", false)
		quit(1)
		return

	var peer_id := multiplayer.get_unique_id()
	var avatar: Node = null
	deadline = Time.get_ticks_msec() + AVATAR_TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		await process_frame
		avatar = current_scene.get_node_or_null("Entities/Peer_%d" % peer_id) if current_scene != null else null
		if is_instance_valid(avatar):
			break
	if not is_instance_valid(avatar):
		_fail("Client avatar was not spawned before timeout")
		manager.call("leave_session", false)
		quit(1)
		return

	# Burst deliberately exceeds the server token bucket. The test asserts
	# transport stability and that the client remains connected afterward.
	for i in range(STRESS_PACKETS):
		var direction := Vector3(0.0, 0.0, -1.0) if i % 2 == 0 else Vector3(1.0, 0.0, 0.0)
		avatar.rpc_id(1, "_rpc_submit_input", direction, false, i % 3 == 0, false)
		if i % 100 == 0:
			await process_frame

	var settle_deadline := Time.get_ticks_msec() + 1200
	while Time.get_ticks_msec() < settle_deadline:
		await process_frame
	_check(bool(manager.call("is_connected_to_server")), "client stays connected after RPC burst")
	_check(is_instance_valid(current_scene.get_node_or_null("Entities/Peer_%d" % peer_id)), "client avatar remains present after RPC burst")

	manager.call("leave_session", false)
	print("[network-stress-client] peer %d failures: %d" % [peer_id, _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] %s" % message)
	else:
		_fail(message)


func _fail(message: String) -> void:
	_failures += 1
	push_error("[FAIL] %s" % message)
