extends Node3D

const SERVER_SCRIPT: Script = preload("res://scripts/core/server.gd")
const HEALTH_SCRIPT: Script = preload("res://scripts/components/health.gd")
const PLAYER_SCRIPT: Script = preload("res://scripts/player/player.gd")
const PLAYER_MODEL_PATH: String = "res://assets/characters/player/player.glb"
const ENEMY_MODEL_PATH: String = "res://assets/characters/enemies/ash_wraith.glb"
const ASHEN_ARENA_SCRIPT: Script = preload("res://scripts/world/ashen_arena.gd")
const CAMERA_SCRIPT: Script = preload("res://scripts/player/player_camera.gd")
const ENEMY_SCRIPT: Script = preload("res://scripts/enemies/enemy.gd")
const INVENTORY_SCRIPT: Script = preload("res://scripts/components/inventory.gd")
const PROGRESSION_SCRIPT: Script = preload("res://scripts/core/progression_manager.gd")
const QUEST_SCRIPT: Script = preload("res://scripts/core/quest_manager.gd")
const SAVE_SCRIPT: Script = preload("res://scripts/core/save_system.gd")
const HUD_SCRIPT: Script = preload("res://scripts/ui/hud.gd")
const NPC_SCENE: PackedScene = preload("res://scenes/npc/NPC.tscn")
const INTERACTION_SCRIPT: Script = preload("res://scripts/player/interaction_detector.gd")

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
	var dialogue_manager := get_node_or_null("/root/DialogueManager")
	if dialogue_manager != null:
		dialogue_manager.call("configure_context", player, progression, quests)
		var quest_start_callback := Callable(self, "_on_dialogue_start_quest")
		if not dialogue_manager.is_connected("quest_start_requested", quest_start_callback):
			dialogue_manager.connect("quest_start_requested", quest_start_callback)
	_create_enemies()
	_create_npcs()
	_create_hud()
	var audio_feedback := get_node_or_null("/root/AudioFeedback")
	if audio_feedback != null:
		audio_feedback.call("start_ambience")

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
	_add_key_action(&"interact", [KEY_E, KEY_ENTER])
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
	var attack_event := InputEventMouseButton.new()
	attack_event.button_index = MOUSE_BUTTON_LEFT
	if not InputMap.action_has_event("attack", attack_event):
		InputMap.action_add_event("attack", attack_event)


func _add_key_action(action: StringName, key_codes: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key_code in key_codes:
		var key_event := InputEventKey.new()
		key_event.physical_keycode = int(key_code)
		if not InputMap.action_has_event(action, key_event):
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

	var arena_dressing := Node3D.new()
	arena_dressing.name = "AshenArenaDressing"
	arena_dressing.set_script(ASHEN_ARENA_SCRIPT)
	world.add_child(arena_dressing)


func _create_managers() -> void:
	progression = PROGRESSION_SCRIPT.new()
	progression.name = "ProgressionManager"
	add_child(progression)
	progression.connect("level_up", _on_level_up)

	quests = QUEST_SCRIPT.new()
	quests.name = "QuestManager"
	quests.set("progression", progression)
	add_child(quests)
	quests.call("refresh_ui")

	save_system = SAVE_SCRIPT.new()
	save_system.name = "SaveSystem"
	add_child(save_system)


func _create_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.set_script(PLAYER_SCRIPT)
	player.position = Vector3(0.0, 0.92, 0.0)
	player.collision_mask = 3
	if not _add_player_model_or_placeholder(player):
		_add_hero_fallback_visual(player)

	var health_node: Node = HEALTH_SCRIPT.new()
	health_node.name = "Health"
	health_node.set("max_health", 100.0)
	player.add_child(health_node)

	var inventory_node: Node = INVENTORY_SCRIPT.new()
	inventory_node.name = "Inventory"
	player.add_child(inventory_node)

	var interaction_detector := Area3D.new()
	interaction_detector.name = "InteractionDetector"
	interaction_detector.set_script(INTERACTION_SCRIPT)
	interaction_detector.collision_layer = 0
	interaction_detector.collision_mask = 4
	var interaction_shape_node := CollisionShape3D.new()
	var interaction_shape := SphereShape3D.new()
	interaction_shape.radius = 3.2
	interaction_shape_node.shape = interaction_shape
	interaction_detector.add_child(interaction_shape_node)
	player.add_child(interaction_detector)

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


func _add_player_model_or_placeholder(body: CharacterBody3D) -> bool:
	if not ResourceLoader.exists(PLAYER_MODEL_PATH):
		return false

	var model_scene := load(PLAYER_MODEL_PATH) as PackedScene
	if model_scene == null:
		push_warning("Player model exists but could not be loaded as a PackedScene: %s" % PLAYER_MODEL_PATH)
		return false

	# The legacy CharacterBody3D pivot is centered at half-height (y = 0.92).
	# Player GLB assets are expected to have their origin at the feet.
	_add_capsule_collision(body, 0.42, 1.84)
	var visual_root := Node3D.new()
	visual_root.name = "PlayerVisual"
	visual_root.position.y = -0.92
	body.add_child(visual_root)

	var model_instance := model_scene.instantiate()
	model_instance.name = "GeneratedPlayerModel"
	visual_root.add_child(model_instance)
	print("[PLAYER] Loaded optional model: %s" % PLAYER_MODEL_PATH)
	return true


func _add_hero_fallback_visual(body: CharacterBody3D) -> void:
	# Temporary original low-poly silhouette for development before a licensed GLB is supplied.
	# Keep collision independent from the visible meshes.
	_add_capsule_collision(body, 0.42, 1.84)

	var visual_root := Node3D.new()
	visual_root.name = "HeroFallbackVisual"
	visual_root.position.y = -0.92
	body.add_child(visual_root)

	var charcoal := Color(0.085, 0.095, 0.115, 1.0)
	var armor_gray := Color(0.20, 0.22, 0.24, 1.0)
	var leather_brown := Color(0.22, 0.145, 0.095, 1.0)
	var muted_bronze := Color(0.48, 0.33, 0.15, 1.0)
	var skin_tone := Color(0.36, 0.235, 0.17, 1.0)
	var dark_metal := Color(0.10, 0.115, 0.13, 1.0)

	var cape_mesh := BoxMesh.new()
	cape_mesh.size = Vector3(0.60, 0.76, 0.075)
	_add_hero_part(visual_root, "Cape", cape_mesh, Vector3(0.0, 1.03, 0.19), charcoal)

	var tunic_mesh := BoxMesh.new()
	tunic_mesh.size = Vector3(0.46, 0.62, 0.31)
	_add_hero_part(visual_root, "Tunic", tunic_mesh, Vector3(0.0, 1.05, 0.0), leather_brown)

	var chest_mesh := BoxMesh.new()
	chest_mesh.size = Vector3(0.39, 0.42, 0.065)
	_add_hero_part(visual_root, "ChestArmor", chest_mesh, Vector3(0.0, 1.13, -0.175), armor_gray)

	var belt_mesh := BoxMesh.new()
	belt_mesh.size = Vector3(0.48, 0.095, 0.34)
	_add_hero_part(visual_root, "Belt", belt_mesh, Vector3(0.0, 0.78, 0.0), charcoal)

	var buckle_mesh := BoxMesh.new()
	buckle_mesh.size = Vector3(0.085, 0.075, 0.025)
	_add_hero_part(visual_root, "BeltBuckle", buckle_mesh, Vector3(0.0, 0.78, -0.185), muted_bronze)

	var leg_mesh := CapsuleMesh.new()
	leg_mesh.radius = 0.095
	leg_mesh.height = 0.44
	var boot_mesh := BoxMesh.new()
	boot_mesh.size = Vector3(0.21, 0.16, 0.32)
	for side in [-1.0, 1.0]:
		_add_hero_part(
			visual_root, "Leg_%s" % str(side), leg_mesh,
			Vector3(side * 0.145, 0.38, 0.0), charcoal
		)
		_add_hero_part(
			visual_root, "Boot_%s" % str(side), boot_mesh,
			Vector3(side * 0.145, 0.09, -0.035), leather_brown
		)

	var arm_mesh := CapsuleMesh.new()
	arm_mesh.radius = 0.072
	arm_mesh.height = 0.47
	var shoulder_mesh := CapsuleMesh.new()
	shoulder_mesh.radius = 0.12
	shoulder_mesh.height = 0.25
	for side in [-1.0, 1.0]:
		_add_hero_part(
			visual_root, "Arm_%s" % str(side), arm_mesh,
			Vector3(side * 0.30, 1.02, 0.0), leather_brown,
			Vector3(0.0, 0.0, side * 9.0)
		)
		_add_hero_part(
			visual_root, "Shoulder_%s" % str(side), shoulder_mesh,
			Vector3(side * 0.275, 1.29, -0.015), armor_gray
		)

	var hood_mesh := CapsuleMesh.new()
	hood_mesh.radius = 0.17
	hood_mesh.height = 0.34
	_add_hero_part(visual_root, "Hood", hood_mesh, Vector3(0.0, 1.60, 0.015), charcoal)

	var face_mesh := SphereMesh.new()
	face_mesh.radius = 0.105
	face_mesh.height = 0.21
	_add_hero_part(visual_root, "Face", face_mesh, Vector3(0.0, 1.57, -0.12), skin_tone)

	var eye_mesh := BoxMesh.new()
	eye_mesh.size = Vector3(0.025, 0.018, 0.012)
	for side in [-1.0, 1.0]:
		_add_hero_part(
			visual_root, "Eye_%s" % str(side), eye_mesh,
			Vector3(side * 0.037, 1.595, -0.218), dark_metal
		)

	var sheath_mesh := BoxMesh.new()
	sheath_mesh.size = Vector3(0.075, 0.58, 0.075)
	_add_hero_part(
		visual_root, "SwordSheath", sheath_mesh,
		Vector3(0.34, 0.78, 0.105), leather_brown,
		Vector3(0.0, 0.0, -14.0)
	)
	var sword_handle_mesh := BoxMesh.new()
	sword_handle_mesh.size = Vector3(0.065, 0.18, 0.065)
	_add_hero_part(
		visual_root, "SwordHandle", sword_handle_mesh,
		Vector3(0.38, 1.13, 0.085), muted_bronze,
		Vector3(0.0, 0.0, -14.0)
	)
	print("[PLAYER] Using procedural low-poly fallback; no player.glb was loaded.")


func _add_hero_part(
	parent: Node3D,
	part_name: String,
	mesh: Mesh,
	local_position: Vector3,
	tint: Color,
	local_rotation_degrees: Vector3 = Vector3.ZERO
) -> void:
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = part_name
	mesh_node.mesh = mesh
	mesh_node.position = local_position
	mesh_node.rotation_degrees = local_rotation_degrees

	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.92
	mesh_node.material_override = material
	parent.add_child(mesh_node)


func _add_capsule_parts(body: CharacterBody3D, radius: float, height: float, tint: Color) -> void:
	_add_capsule_collision(body, radius, height)

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


func _add_capsule_collision(body: CharacterBody3D, radius: float, height: float) -> void:
	var collision_node := CollisionShape3D.new()
	collision_node.name = "CollisionShape3D"
	var collision := CapsuleShape3D.new()
	collision.radius = radius
	collision.height = height
	collision_node.shape = collision
	body.add_child(collision_node)


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
		if not _add_enemy_model_or_placeholder(enemy):
			_add_capsule_parts(enemy, 0.4, 1.7, Color(0.32, 0.36, 0.43, 1.0))

		var health_node: Node = HEALTH_SCRIPT.new()
		health_node.name = "Health"
		health_node.set("max_health", 55.0)
		enemy.add_child(health_node)
		enemy.connect("died", _on_enemy_died)
		enemies_container.add_child(enemy)



func _add_enemy_model_or_placeholder(body: CharacterBody3D) -> bool:
	if not ResourceLoader.exists(ENEMY_MODEL_PATH):
		return false

	var model_scene := load(ENEMY_MODEL_PATH) as PackedScene
	if model_scene == null:
		push_warning("Ash Wraith model exists but could not be loaded: %s" % ENEMY_MODEL_PATH)
		return false

	_add_capsule_collision(body, 0.4, 1.7)
	var visual_root := Node3D.new()
	visual_root.name = "EnemyVisual"
	visual_root.position.y = -0.92
	body.add_child(visual_root)

	var model_instance := model_scene.instantiate()
	model_instance.name = "AshWraithModel"
	visual_root.add_child(model_instance)
	print("[ENEMY] Loaded Ash Wraith model: %s" % ENEMY_MODEL_PATH)
	return true


func _create_npcs() -> void:
	var npc := NPC_SCENE.instantiate() as CharacterBody3D
	if npc == null:
		push_error("Could not instantiate NPC scene.")
		return
	npc.name = "WanderingElder"
	npc.position = Vector3(-4.0, 0.92, -2.0)
	world.add_child(npc)


func _on_dialogue_start_quest(quest_id: StringName) -> void:
	if not is_instance_valid(quests):
		return
	var started := bool(quests.call("start_quest", quest_id))
	if is_instance_valid(hud):
		if started:
			hud.call("show_message", "تم قبول المهمة: اقتفاء الرماد.")
		else:
			hud.call("show_message", "تعذر بدء المهمة أو أنها مكتملة بالفعل.")


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
		"quest": quests.call("to_save_data"),
		"dialogue": _serialize_dialogue_state()
	}
	print("[SAVE] dialogue: %s" % str(data.get("dialogue", {})))
	var success := bool(save_system.call("save_game", data))
	print("[SAVE] success: %s" % str(success))
	hud.call("show_saved_status", success)


func _serialize_dialogue_state() -> Dictionary:
	var dialogue_manager := get_node_or_null("/root/DialogueManager")
	if dialogue_manager == null:
		return {}
	var result = dialogue_manager.call("serialize")
	return result if result is Dictionary else {}


func _load_game() -> void:
	var data: Dictionary = save_system.call("load_game")
	print("[LOAD] data keys: %s" % str(data.keys()))
	print("[LOAD] dialogue: %s" % str(data.get("dialogue", {})))
	if data.is_empty():
		if is_instance_valid(hud):
			hud.call("show_message", "لا يوجد ملف حفظ بعد.")
		return

	if data.has("player_position") and data["player_position"] is Dictionary:
		var position_data: Dictionary = data["player_position"]
		player.global_position = Vector3(
			float(position_data.get("x", 0.0)), float(position_data.get("y", 0.92)), float(position_data.get("z", 0.0))
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
	var dialogue_data = data.get("dialogue", {})
	var dialogue_manager := get_node_or_null("/root/DialogueManager")
	if dialogue_manager != null:
		dialogue_manager.call("deserialize", dialogue_data if dialogue_data is Dictionary else {})
	if is_instance_valid(hud):
		hud.call("close_overlays")
		hud.call("show_message", "تم تحميل الحفظ.")
