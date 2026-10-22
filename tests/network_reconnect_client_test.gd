extends SceneTree

const ARENA_PATH := "res://scenes/network/MultiplayerArena.tscn"
const CONNECT_TIMEOUT_MSEC := 10000
const SPAWN_TIMEOUT_MSEC := 10000
const CYCLES := 2

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

	for cycle in range(CYCLES):
		var result := int(manager.call("start_client", "127.0.0.1", port))
		if result != OK:
			_fail("cycle %d: client initialization failed: %s" % [cycle + 1, error_string(result)])
			break
		if not await _wait_for_connection(manager):
			_fail("cycle %d: connection timed out" % [cycle + 1])
			manager.call("leave_session", false)
			break

		result = change_scene_to_file(ARENA_PATH)
		if result != OK:
			_fail("cycle %d: could not load arena: %s" % [cycle + 1, error_string(result)])
			manager.call("leave_session", false)
			break

		# Deliberately duplicate the readiness announcement. Server-side state
		# must remain idempotent and must not spawn duplicate player avatars.
		for _duplicate in range(3):
			manager.call("notify_arena_ready")

		var multiplayer_api: MultiplayerAPI = manager.get_multiplayer()
		var peer_id: int = multiplayer_api.get_unique_id()
		if not await _wait_for_single_avatar(peer_id):
			_fail("cycle %d: expected exactly one avatar for peer %d" % [cycle + 1, peer_id])
			manager.call("leave_session", false)
			break
		print("[PASS] reconnect cycle %d has one authoritative avatar (peer %d)" % [cycle + 1, peer_id])

		manager.call("leave_session", false)
		await create_timer(0.5).timeout

	print("[network-reconnect] cycles: %d, failures: %d" % [CYCLES, _failures])
	quit(1 if _failures > 0 else 0)


func _wait_for_connection(manager: Node) -> bool:
	var deadline := Time.get_ticks_msec() + CONNECT_TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		if bool(manager.call("is_connected_to_server")):
			return true
		await process_frame
	return false


func _wait_for_single_avatar(peer_id: int) -> bool:
	var deadline := Time.get_ticks_msec() + SPAWN_TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var entities := current_scene.get_node_or_null("Entities") if current_scene != null else null
		if entities == null:
			continue
		var avatar_count := 0
		for child in entities.get_children():
			if child.name == "Peer_%d" % peer_id:
				avatar_count += 1
		if avatar_count == 1:
			return true
	return false


func _fail(message: String) -> void:
	_failures += 1
	push_error("[FAIL] %s" % message)
