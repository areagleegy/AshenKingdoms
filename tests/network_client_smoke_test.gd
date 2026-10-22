extends SceneTree

const NETWORK_ARENA_PATH: String = "res://scenes/network/MultiplayerArena.tscn"
const CONNECTION_TIMEOUT_MSEC: int = 8000
const SPAWN_TIMEOUT_MSEC: int = 8000

var _failures: int = 0


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

	var start_result: int = int(manager.call("start_client", "127.0.0.1", port))
	if start_result != OK:
		_fail("Client failed to initialize: %s" % error_string(start_result))
		quit(1)
		return
	print("[network-loopback] client transport initialized")

	var connection_deadline := Time.get_ticks_msec() + CONNECTION_TIMEOUT_MSEC
	while Time.get_ticks_msec() < connection_deadline:
		if bool(manager.call("is_connected_to_server")):
			break
		await process_frame

	if not bool(manager.call("is_connected_to_server")):
		_fail("Client did not connect to the local ENet host before timeout")
		manager.call("leave_session", false)
		quit(1)
		return
	print("[PASS] independent client connects to the local ENet host")

	var scene_result := change_scene_to_file(NETWORK_ARENA_PATH)
	if scene_result != OK:
		_fail("Could not open network arena: %s" % error_string(scene_result))
		manager.call("leave_session", false)
		quit(1)
		return

	var multiplayer_api: MultiplayerAPI = manager.get_multiplayer()
	var local_peer_id: int = multiplayer_api.get_unique_id()
	var saw_host := false
	var saw_local_avatar := false
	var enemy_count := 0
	var spawn_deadline := Time.get_ticks_msec() + SPAWN_TIMEOUT_MSEC

	while Time.get_ticks_msec() < spawn_deadline:
		await process_frame
		var arena := current_scene
		if arena == null:
			continue
		var entities := arena.get_node_or_null("Entities") as Node3D
		if entities == null:
			continue

		saw_host = entities.get_node_or_null("Peer_1") != null
		saw_local_avatar = entities.get_node_or_null("Peer_%d" % local_peer_id) != null
		enemy_count = 0
		for slot in range(1, 5):
			if entities.get_node_or_null("Enemy_%02d" % slot) != null:
				enemy_count += 1
		if saw_host and saw_local_avatar and enemy_count == 4:
			break

	_check(saw_host, "client receives the host avatar")
	_check(saw_local_avatar, "client receives its own authoritative avatar")
	_check(enemy_count == 4, "client receives all four existing enemies")

	var arena_for_input_test := current_scene
	var input_entities := arena_for_input_test.get_node_or_null("Entities") as Node3D if arena_for_input_test != null else null
	var local_avatar := input_entities.get_node_or_null("Peer_%d" % local_peer_id) as CharacterBody3D if input_entities != null else null
	if local_avatar == null:
		_check(false, "client has a local avatar for invalid-input RPC test")
	else:
		# Let the spawn settle, then suspend normal local input so a valid packet
		# cannot overwrite the malicious test packet before the server processes it.
		await create_timer(0.25).timeout
		var position_before_invalid: Vector3 = local_avatar.global_position
		local_avatar.set_physics_process(false)
		local_avatar.rpc_id(1, "_rpc_submit_input", Vector3(NAN, 0.0, 0.0), false, false, false)
		await create_timer(0.15).timeout
		var position_after_invalid: Vector3 = local_avatar.global_position
		local_avatar.set_physics_process(true)
		_check(position_after_invalid.is_finite(), "non-finite RPC input does not corrupt the replicated avatar position")
		# Vertical movement can continue while gravity settles the avatar onto the floor.
		# The rejected horizontal input should not change the requested X/Z movement.
		var horizontal_delta := Vector2(
			position_after_invalid.x - position_before_invalid.x,
			position_after_invalid.z - position_before_invalid.z
		)
		_check(horizontal_delta.length() < 0.25, "non-finite RPC input does not materially move the avatar horizontally")
	if _failures > 0 and current_scene != null:
		var entities := current_scene.get_node_or_null("Entities") as Node3D
		if entities != null:
			var child_names: PackedStringArray = []
			for child in entities.get_children():
				child_names.append(child.name)
			print("[network-loopback] observed entities: %s" % ", ".join(child_names))

	manager.call("leave_session", false)
	print("[network-loopback] failures: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] %s" % description)
	else:
		_fail(description)


func _fail(description: String) -> void:
	_failures += 1
	push_error("[FAIL] %s" % description)
