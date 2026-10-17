extends Node3D

const SERVER_SCRIPT: Script = preload("res://scripts/core/server.gd")
const HEALTH_SCRIPT: Script = preload("res://scripts/components/health.gd")
const PLAYER_SCRIPT: Script = preload("res://scripts/player/player.gd")
const CAMERA_SCRIPT: Script = preload("res://scripts/player/player_camera.gd")
const ENEMY_SCRIPT: Script = preload("res://scripts/enemies/enemy.gd")
const INVENTORY_SCRIPT: Script = preload("res://scripts/components/inventory.gd")
const PROGRESSION_SCRIPT: Script = preload("res://scripts/core/progression_manager.gd")
const QUEST_SCRIPT: Script = preload("res://scripts/core/quest_manager.gd")
const SAVE_SCRIPT: Script = preload("res://scripts/core/save_system.gd")
const HUD_SCRIPT: Script = preload("res://scripts/ui/hud.gd")

var world: Node3D
var player: CharacterBody3D
var camera_pivot: Node3D
var enemies_container: Node3D
var progression: Node
var quests: Node
var save_system: Node
var hud: CanvasLayer


func _ready() -> void:
	if _is_server_mode():
		var server_node: Node = SERVER_SCRIPT.new()
		server_node.name = "ServerBootstrap"
		add_child(server_node)
		return

	_register_input_actions()
	_create_world()
	_create_managers()
	_create_player()
	_create_enemies()
	_create_hud()

	if OS.get_cmdline_user_args().has("--continue"):
		_load_game()

	if not (OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("AshenKingdoms playable vertical slice started.")


func _process(_delta: float) -> void:
	if is_instance_valid(player) and is_instance_valid(camera_pivot):
		camera_pivot.global_position = player.global_position + Vector3.UP * 1.35


func _is_server_mode() -> bool:
	return (
		DisplayServer.get_name() == "headless"
		or OS.has_feature("dedicated_server")
		or "--server" in OS.get_cmdline_user_args()
	)


func _register_input_actions() -> void:
	_add_key_action(&"move_forward", [KEY_W, KEY_UP])
	_add_key_action(&"move_back", [KEY_S, KEY_DOWN])
	_add_key_action(&"move_left", [KEY_A, KEY_LEFT])
	_add_key_action(&"move_right", [KEY_D, KEY_RIGHT])
	_add_key_action(&"jump", [KEY_SPACE])
	_add_key_action(&"sprint", [KEY_SHIFT])
	_add_key_action(&"inventory", [KEY_I, KEY_TAB])
	_add_key_action(&"pause", [KEY_ESCAPE])
	_add_key_action(&"save", [KEY_F5])
	_add_key_action(&"load", [KEY_F9])
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
	var attack_event := InputEventMouseButton.new()
	attack_event.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("attack", attack_event)


func _add_key_action(action: StringName, key_codes: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key_code in key_codes:
		var key_event := InputEventKey.new()
		key_event.physical_keycode = int(key_code)
		InputMap.action_add_event(action, key_event)


func _create_world() -> void:
	world = Node3D.new()
	world.name = "World"
	add_child(world)

	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.035, 0.035, 0.055, 1.0)
	environment_node.environment = environment
	world.add_child(environment_node)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_energy = 1.25
	world.add_child(sun)

	var ground_body := StaticBody3D.new()
	ground_body.name = "Ground"
	ground_body.position.y = -0.5
	var ground_shape_node := CollisionShape3D.new()
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(80.0, 1.0, 80.0)
	ground_shape_node.shape = ground_shape
	ground_body.add_child(ground_shape_node)
	world.add_child(ground_body)

	var ground_mesh_node := MeshInstance3D.new()
	ground_mesh_node.name = "GroundVisual"
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(80.0, 80.0)
	ground_mesh_node.mesh = ground_mesh
	ground_mesh_node.position.y = -0.015
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.12, 0.15, 0.17, 1.0)
	ground_material.roughness = 1.0
	ground_mesh_node.material_override = ground_material
	world.add_child(ground_mesh_node)


func _create_managers() -> void:
	progression = PROGRESSION_SCRIPT.new()
	progression.name = "ProgressionManager"
	add_child(progression)
	progression.connect("level_up", _on_level_up)

	quests = QUEST_SCRIPT.new()
	quests.name = "QuestManager"
	quests.set("progression", progression)
	add_child(quests)
	quests.call("start_default_quest")

	save_system = SAVE_SCRIPT.new()
	save_system.name = "SaveSystem"
	add_child(save_system)


func _create_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.set_script(PLAYER_SCRIPT)
	player.position = Vector3(0.0, 0.92, 0.0)
	_add_capsule_parts(player, 0.42, 1.84, Color(0.62, 0.38, 0.22, 1.0))

	var health_node: Node = HEALTH_SCRIPT.new()
	health_node.name = "Health"
	health_node.set("max_health", 100.0)
	player.add_child(health_node)

	var inventory_node: Node = INVENTORY_SCRIPT.new()
	inventory_node.name = "Inventory"
	player.add_child(inventory_node)

	world.add_child(player)
	player.add_to_group("player")
	player.connect("died", _on_player_died)

	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	camera_pivot.set_script(CAMERA_SCRIPT)
	camera_pivot.position = player.position + Vector3.UP * 1.35
	world.add_child(camera_pivot)

	var spring_arm := SpringArm3D.new()
	spring_arm.name = "SpringArm3D"
	spring_arm.spring_length = 4.8
	spring_arm.margin = 0.25
	camera_pivot.add_child(spring_arm)

	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	spring_arm.add_child(camera)

	player.set("camera_pivot", camera_pivot)

	var potion := load("res://resources/items/health_potion.tres") as ItemResource
	if potion != null:
		inventory_node.call("add_item", potion, 3)


func _add_capsule_parts(body: CharacterBody3D, radius: float, height: float, tint: Color) -> void:
	var collision_node := CollisionShape3D.new()
	var collision := CapsuleShape3D.new()
	collision.radius = radius
	collision.height = height
	collision_node.shape = collision
	body.add_child(collision_node)

	var mesh_node := MeshInstance3D.new()
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = radius
	capsule_mesh.height = height
	mesh_node.mesh = capsule_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.8
	mesh_node.material_override = material
	body.add_child(mesh_node)


func _create_enemies() -> void:
	enemies_container = Node3D.new()
	enemies_container.name = "Enemies"
	world.add_child(enemies_container)

	var spawn_points: Array[Vector3] = [
		Vector3(0.0, 0.92, -6.0),
		Vector3(5.0, 0.92, -8.0),
		Vector3(-5.0, 0.92, -8.0),
		Vector3(8.0, 0.92, 1.0)
	]
	for index in range(spawn_points.size()):
		var enemy := CharacterBody3D.new()
		enemy.name = "AshWraith_%02d" % (index + 1)
		enemy.set_script(ENEMY_SCRIPT)
		enemy.set("player", player)
		enemy.position = spawn_points[index]
		_add_capsule_parts(enemy, 0.4, 1.7, Color(0.32, 0.36, 0.43, 1.0))

		var health_node: Node = HEALTH_SCRIPT.new()
		health_node.name = "Health"
		health_node.set("max_health", 55.0)
		enemy.add_child(health_node)
		enemy.connect("died", _on_enemy_died)
		enemies_container.add_child(enemy)


func _create_hud() -> void:
	hud = HUD_SCRIPT.new()
	hud.name = "HUD"
	add_child(hud)
	hud.call("bind_game", player, progression, quests, player.get_node("Inventory"))
	hud.connect("save_requested", _save_game)
	hud.connect("load_requested", _load_game)


func _on_enemy_died(enemy: Node) -> void:
	var reward := int(enemy.get("experience_reward"))
	progression.call("add_experience", reward)
	quests.call("on_enemy_defeated", StringName(enemy.get("enemy_id")))
	if is_instance_valid(hud):
		hud.call("show_message", "هُزم عدو: +%d XP" % reward)


func _on_level_up(new_level: int) -> void:
	if not is_instance_valid(player):
		return
	var health := player.get_node("Health") as Health
	health.increase_max_health(10.0)
	player.set("attack_damage", float(player.get("attack_damage")) + 3.0)
	if is_instance_valid(hud):
		hud.call("show_message", "ارتقيت إلى المستوى %d! زادت الصحة والهجوم." % new_level)


func _on_player_died(_dead_player: Node) -> void:
	if is_instance_valid(hud):
		hud.call("show_message", "سقطت في المعركة... ستعود بعد لحظات.")
	await get_tree().create_timer(2.0).timeout
	if not is_instance_valid(player):
		return
	player.call("reset_after_death", Vector3(0.0, 0.92, 0.0))
	if is_instance_valid(hud):
		hud.call("show_message", "عدت إلى ساحة القتال.")


func _save_game() -> void:
	if not is_instance_valid(player):
		return
	var health := player.get_node("Health") as Health
	var player_pos := player.global_position
	var data: Dictionary = {
		"version": 1,
		"player_position": {"x": player_pos.x, "y": player_pos.y, "z": player_pos.z},
		"player_health": health.current,
		"level": int(progression.get("level")),
		"experience": int(progression.get("experience")),
		"inventory": player.get_node("Inventory").call("to_save_data"),
		"quest": quests.call("to_save_data")
	}
	var success := bool(save_system.call("save_game", data))
	hud.call("show_saved_status", success)


func _load_game() -> void:
	var data: Dictionary = save_system.call("load_game")
	if data.is_empty():
		if is_instance_valid(hud):
			hud.call("show_message", "لا يوجد ملف حفظ بعد.")
		return

	if data.has("player_position") and data["player_position"] is Dictionary:
		var position_data: Dictionary = data["player_position"]
		player.global_position = Vector3(
			float(position_data.get("x", 0.0)),
			float(position_data.get("y", 0.92)),
			float(position_data.get("z", 0.0))
		)

	progression.call(
		"restore_state",
		int(data.get("level", 1)),
		int(data.get("experience", 0))
	)
	var restored_level := int(progression.get("level"))
	var level_bonus := maxi(restored_level - 1, 0)
	var health := player.get_node("Health") as Health
	health.max_health = 100.0 + (float(level_bonus) * 10.0)
	player.set("attack_damage", 20.0 + (float(level_bonus) * 3.0))
	health.set_current_health(float(data.get("player_health", health.max_health)))
	player.get_node("Inventory").call("restore_save_data", data.get("inventory", []))
	quests.call("load_state", data.get("quest", {}))
	if is_instance_valid(hud):
		hud.call("close_overlays")
		hud.call("show_message", "تم تحميل الحفظ.")
