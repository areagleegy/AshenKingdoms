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
	var peer_avatar_count := 0
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
		peer_avatar_count = 0
		for child in entities.get_children():
			if child.name.begins_with("Peer_"):
				peer_avatar_count += 1
		enemy_count = 0
		for slot in range(1, 5):
			if entities.get_node_or_null("Enemy_%02d" % slot) != null:
				enemy_count += 1
		if saw_host and saw_local_avatar and peer_avatar_count == 2 and enemy_count == 4:
			break

	_check(saw_host, "client receives the host avatar")
	_check(saw_local_avatar, "client receives its own authoritative avatar")
	_check(peer_avatar_count == 2, "first connection creates exactly one avatar per connected peer")
	_check(enemy_count == 4, "client receives all four existing enemies")
	if _failures > 0 and current_scene != null:
		var entities := current_scene.get_node_or_null("Entities") as Node3D
		if entities != null:
			var child_names: PackedStringArray = []
			for child in entities.get_children():
				child_names.append(child.name)
			print("[network-loopback] observed entities: %s" % ", ".join(child_names))

	# Exercise disconnect/reconnect through the same client process.
	manager.call("leave_session", false)
	await process_frame
	var reconnect_result: int = int(manager.call("start_client", "127.0.0.1", port))
	_check(reconnect_result == OK, "client can initialize a second session after leaving")
	if reconnect_result == OK:
		var reconnect_deadline := Time.get_ticks_msec() + CONNECTION_TIMEOUT_MSEC
		while Time.get_ticks_msec() < reconnect_deadline:
			if bool(manager.call("is_connected_to_server")):
				break
			await process_frame
		_check(bool(manager.call("is_connected_to_server")), "client reconnects to the host after leaving")
		if bool(manager.call("is_connected_to_server")):
			var reconnect_scene_result := change_scene_to_file(NETWORK_ARENA_PATH)
			_check(reconnect_scene_result == OK, "network arena can be re-entered after reconnect")
			if reconnect_scene_result == OK:
				var reconnect_peer_id := int(multiplayer_api.get_unique_id())
				var reconnect_spawn_deadline := Time.get_ticks_msec() + SPAWN_TIMEOUT_MSEC
				var reconnect_avatar_seen := false
				var reconnect_peer_avatar_count := 0
				while Time.get_ticks_msec() < reconnect_spawn_deadline:
					await process_frame
					var reconnect_arena := current_scene
					if reconnect_arena == null:
						continue
					var reconnect_entities := reconnect_arena.get_node_or_null("Entities") as Node3D
					if reconnect_entities == null:
						continue
					reconnect_avatar_seen = reconnect_entities.get_node_or_null("Peer_%d" % reconnect_peer_id) != null
					reconnect_peer_avatar_count = 0
					for child in reconnect_entities.get_children():
						if child.name.begins_with("Peer_"):
							reconnect_peer_avatar_count += 1
					if reconnect_avatar_seen and reconnect_peer_avatar_count == 2:
						break
				_check(reconnect_avatar_seen, "reconnected client receives its avatar")
				_check(reconnect_peer_avatar_count == 2, "reconnect leaves exactly one avatar for each connected peer")
			else:
				manager.call("leave_session", false)

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
