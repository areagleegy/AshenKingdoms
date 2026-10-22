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

	var arena_entities := current_scene.get_node_or_null("Entities") as Node3D
	if OS.get_environment("ASHEN_TEST_COMBAT") == "1" and saw_local_avatar and enemy_count == 4 and arena_entities != null:
		var local_avatar := arena_entities.get_node_or_null("Peer_%d" % local_peer_id)
		var target := arena_entities.get_node_or_null("Enemy_01")
		if not is_instance_valid(local_avatar) or not is_instance_valid(target):
			_fail("combat integration setup entities are missing")
		else:
			var enemy_slot := int(target.get("enemy_slot"))
			var initial_health := float(target.get("current_health"))
			var defeated_enemy_id := target.get_instance_id()

			# First real input-RPC attack: the server stages the enemy outside range.
			Input.action_press("attack")
			await create_timer(0.12).timeout
			Input.action_release("attack")
			await create_timer(0.20).timeout
			_check(
				is_instance_valid(target) and is_equal_approx(float(target.get("current_health")), initial_health),
				"remote attack RPC cannot damage an enemy outside attack range"
			)

			# The attack attempt starts the server cooldown even if no target is hit.
			await create_timer(0.75).timeout
			Input.action_press("attack")
			await create_timer(0.12).timeout
			Input.action_release("attack")
			await create_timer(0.20).timeout
			_check(
				is_instance_valid(target) and is_equal_approx(float(target.get("current_health")), initial_health),
				"remote attack RPC cannot damage an enemy behind the avatar"
			)

			await create_timer(0.75).timeout
			Input.action_press("attack")
			var first_hit_deadline := Time.get_ticks_msec() + 2500
			while (
				Time.get_ticks_msec() < first_hit_deadline
				and is_instance_valid(target)
				and float(target.get("current_health")) >= initial_health
			):
				await process_frame
			Input.action_release("attack")
			var first_hit_landed := is_instance_valid(target) and float(target.get("current_health")) < initial_health
			_check(first_hit_landed, "in-range forward attack RPC damages the enemy")
			var first_client_health := -1.0
			if first_hit_landed:
				first_client_health = float(target.get("current_health"))
				print("[combat-client] enemy_health slot=%d health=%.2f" % [enemy_slot, first_client_health])
				_check(
					is_equal_approx(first_client_health, initial_health - float(local_avatar.get("attack_damage"))),
					"client receives the expected authoritative enemy-health update"
				)

			# A new press immediately after the valid hit must be rejected by cooldown.
			await create_timer(0.05).timeout
			Input.action_press("attack")
			await create_timer(0.10).timeout
			Input.action_release("attack")
			await create_timer(0.15).timeout
			_check(
				is_instance_valid(target) and is_equal_approx(float(target.get("current_health")), first_client_health),
				"server cooldown rejects an immediate repeated attack RPC"
			)

			# Four more legitimate RPC edges should defeat the 85-HP test enemy.
			for hit_index in range(1, 5):
				if not is_instance_valid(target):
					break
				await create_timer(0.75).timeout
				var health_before := float(target.get("current_health"))
				Input.action_press("attack")
				var hit_deadline := Time.get_ticks_msec() + 2500
				while (
					Time.get_ticks_msec() < hit_deadline
					and is_instance_valid(target)
					and float(target.get("current_health")) >= health_before
				):
					await process_frame
				Input.action_release("attack")
				var hit_landed := false
				if is_instance_valid(target):
					hit_landed = float(target.get("current_health")) < health_before
				else:
					var observed_enemy := arena_entities.get_node_or_null("Enemy_01")
					hit_landed = observed_enemy == null or observed_enemy.get_instance_id() != defeated_enemy_id
				_check(hit_landed, "authoritative combat hit %d updates replicated enemy state" % (hit_index + 1))
				if is_instance_valid(target) and (bool(target.get("is_dead")) or float(target.get("current_health")) <= 0.0):
					break

			var removal_deadline := Time.get_ticks_msec() + 3500
			var enemy_removed := false
			while Time.get_ticks_msec() < removal_deadline:
				var current_enemy := arena_entities.get_node_or_null("Enemy_01")
				if current_enemy == null or current_enemy.get_instance_id() != defeated_enemy_id:
					enemy_removed = true
					break
				await process_frame
			_check(enemy_removed, "defeated enemy instance is removed on the client")

			var respawn_deadline := Time.get_ticks_msec() + 8000
			var respawned_enemy: Node3D
			while Time.get_ticks_msec() < respawn_deadline:
				var candidate := arena_entities.get_node_or_null("Enemy_01") as Node3D
				if (
					is_instance_valid(candidate)
					and candidate.get_instance_id() != defeated_enemy_id
					and not bool(candidate.get("is_dead"))
					and float(candidate.get("current_health")) > 0.0
				):
					respawned_enemy = candidate
					break
				await process_frame
			_check(
				is_instance_valid(respawned_enemy) and respawned_enemy.get_instance_id() != defeated_enemy_id,
				"server respawns a new enemy instance"
			)
			if is_instance_valid(respawned_enemy):
				_check(
					is_equal_approx(float(respawned_enemy.get("current_health")), float(respawned_enemy.get("max_health"))),
					"respawned enemy health is restored to maximum"
				)
				_check(not bool(respawned_enemy.get("is_dead")), "respawned enemy is alive")

			var quest_deadline := Time.get_ticks_msec() + 2500
			while Time.get_ticks_msec() < quest_deadline and int(local_avatar.get("quest_progress")) < 1:
				await process_frame
			_check(int(local_avatar.get("quest_progress")) == 1, "one enemy death grants exactly one replicated quest progress")

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
