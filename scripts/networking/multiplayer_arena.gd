extends Node3D

const MENU_SCENE: String = "res://scenes/ui/MainMenu.tscn"
const NETWORK_AVATAR_SCENE: PackedScene = preload("res://scenes/network/NetworkAvatar.tscn")
const NETWORK_ENEMY_SCENE: PackedScene = preload("res://scenes/network/NetworkEnemy.tscn")
const INITIAL_ENEMY_COUNT: int = 4
const ENEMY_RESPAWN_SECONDS: float = 5.0

@onready var _entities: Node3D = $Entities
@onready var _spawner: MultiplayerSpawner = $EntitySpawner

var _status_label: Label
var _player_count_label: Label
var _combat_label: Label
var _local_avatar: Node3D


func _ready() -> void:
	if not NetworkManager.is_session_active():
		call_deferred("_return_to_menu")
		return

	_register_input_actions()
	_build_world()
	_build_hud()

	_spawner.add_spawnable_scene("res://scenes/network/NetworkAvatar.tscn")
	_spawner.add_spawnable_scene("res://scenes/network/NetworkEnemy.tscn")
	_spawner.spawn_function = _spawn_network_entity

	NetworkManager.peer_arena_ready.connect(_on_peer_arena_ready)
	NetworkManager.peer_left.connect(_on_peer_left)
	NetworkManager.session_ended.connect(_on_session_ended)
	NetworkManager.status_changed.connect(_on_network_status_changed)

	if multiplayer.is_server():
		for peer_id in NetworkManager.get_ready_peer_ids():
			_spawn_avatar(peer_id)
		NetworkManager.notify_arena_ready()
		_spawn_initial_enemies()
	else:
		NetworkManager.notify_arena_ready()
	_refresh_session_status()


func _process(_delta: float) -> void:
	_refresh_combat_hud()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		NetworkManager.leave_session()
		get_tree().quit()


func _register_input_actions() -> void:
	_add_key_action(&"move_forward", [KEY_W, KEY_UP])
	_add_key_action(&"move_back", [KEY_S, KEY_DOWN])
	_add_key_action(&"move_left", [KEY_A, KEY_LEFT])
	_add_key_action(&"move_right", [KEY_D, KEY_DOWN])
	_add_key_action(&"jump", [KEY_SPACE])
	_add_key_action(&"sprint", [KEY_SHIFT])
	_add_key_action(&"pause", [KEY_ESCAPE])
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
	var mouse_attack_exists := false
	for existing_event in InputMap.action_get_events("attack"):
		if existing_event is InputEventMouseButton and (existing_event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			mouse_attack_exists = true
			break
	if not mouse_attack_exists:
		var attack_event := InputEventMouseButton.new()
		attack_event.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("attack", attack_event)


func _add_key_action(action: StringName, key_codes: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key_code in key_codes:
		var already_added := false
		for existing_event in InputMap.action_get_events(action):
			if existing_event is InputEventKey and (existing_event as InputEventKey).physical_keycode == int(key_code):
				already_added = true
				break
		if already_added:
			continue
		var key_event := InputEventKey.new()
		key_event.physical_keycode = int(key_code)
		InputMap.action_add_event(action, key_event)


func _build_world() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.035, 0.035, 0.055, 1.0)
	environment_node.environment = environment
	add_child(environment_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_energy = 1.25
	add_child(sun)

	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.position.y = -0.5
	var ground_collision := CollisionShape3D.new()
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(80.0, 1.0, 80.0)
	ground_collision.shape = ground_shape
	ground.add_child(ground_collision)
	add_child(ground)

	var ground_visual := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(80.0, 80.0)
	ground_visual.mesh = ground_mesh
	ground_visual.position.y = -0.015
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.15, 0.17, 1.0)
	material.roughness = 1.0
	ground_visual.material_override = material
	add_child(ground_visual)

	_add_landmark(Vector3(0.0, 1.0, -8.0), Vector3(1.0, 2.0, 1.0))
	_add_landmark(Vector3(8.0, 1.0, 0.0), Vector3(1.0, 2.0, 1.0))
	_add_landmark(Vector3(-8.0, 1.0, 0.0), Vector3(1.0, 2.0, 1.0))


func _add_landmark(world_position: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = world_position
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	add_child(body)

	var mesh_node := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh_node.mesh = box_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.24, 0.19, 0.15, 1.0)
	mesh_node.material_override = material
	body.add_child(mesh_node)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "SessionHUD"
	add_child(layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(16.0, 16.0)
	panel.custom_minimum_size = Vector2(340.0, 0.0)
	layer.add_child(panel)

	var layout := VBoxContainer.new()
	panel.add_child(layout)

	var title := Label.new()
	title.text = "ممالك الرماد — ساحة الشبكة"
	layout.add_child(title)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_status_label)

	_player_count_label = Label.new()
	layout.add_child(_player_count_label)

	_combat_label = Label.new()
	_combat_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_combat_label)

	var help := Label.new()
	help.text = "الحركة: WASD أو الأسهم · القفز: Space · الركض: Shift\nالهجوم: زر الفأرة الأيسر أو زر «هجوم». حرّك الكاميرا بالماوس أو بالسحب يمين الشاشة."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(help)

	var leave_button := Button.new()
	leave_button.text = "مغادرة الجلسة"
	leave_button.pressed.connect(_return_to_menu)
	layout.add_child(leave_button)

	_build_touch_controls(layer)


func _build_touch_controls(layer: CanvasLayer) -> void:
	if not (OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")):
		return

	_add_touch_button(layer, "↑", &"move_forward", 0.0, 1.0, 92.0, -208.0, 62.0, 62.0)
	_add_touch_button(layer, "←", &"move_left", 0.0, 1.0, 26.0, -142.0, 62.0, 62.0)
	_add_touch_button(layer, "→", &"move_right", 0.0, 1.0, 158.0, -142.0, 62.0, 62.0)
	_add_touch_button(layer, "↓", &"move_back", 0.0, 1.0, 92.0, -76.0, 62.0, 62.0)
	_add_touch_button(layer, "هجوم", &"attack", 1.0, 1.0, -100.0, -92.0, 84.0, 68.0)
	_add_touch_button(layer, "قفز", &"jump", 1.0, 1.0, -194.0, -158.0, 84.0, 68.0)
	_add_touch_button(layer, "ركض", &"sprint", 1.0, 1.0, -100.0, -174.0, 84.0, 68.0)


func _add_touch_button(
	layer: CanvasLayer,
	label_text: String,
	action: StringName,
	anchor_x: float,
	anchor_y: float,
	x: float,
	y: float,
	width: float,
	height: float
) -> void:
	var button := Button.new()
	button.text = label_text
	button.anchor_left = anchor_x
	button.anchor_right = anchor_x
	button.anchor_top = anchor_y
	button.anchor_bottom = anchor_y
	button.offset_left = x
	button.offset_top = y
	button.offset_right = x + width
	button.offset_bottom = y + height
	button.button_down.connect(func() -> void:
		Input.action_press(action)
	)
	button.button_up.connect(func() -> void:
		Input.action_release(action)
	)
	button.tree_exiting.connect(func() -> void:
		Input.action_release(action)
	)
	layer.add_child(button)


func _spawn_network_entity(data: Variant) -> Node:
	if not (data is Dictionary):
		push_error("Invalid network-spawn payload.")
		return Node3D.new()

	var kind := str(data.get("kind", ""))
	if kind == "player":
		var peer_id := int(data.get("peer_id", 0))
		if peer_id < 1:
			push_error("Refusing to spawn a player without a valid peer ID.")
			return Node3D.new()
		var avatar := NETWORK_AVATAR_SCENE.instantiate() as CharacterBody3D
		avatar.name = "Peer_%d" % peer_id
		avatar.call("configure_owner", peer_id)
		if peer_id == multiplayer.get_unique_id():
			_local_avatar = avatar
		return avatar

	if kind == "enemy":
		var slot := int(data.get("enemy_slot", 0))
		if slot < 1:
			push_error("Refusing to spawn an enemy without a valid slot.")
			return Node3D.new()
		var enemy := NETWORK_ENEMY_SCENE.instantiate() as CharacterBody3D
		enemy.name = "Enemy_%02d" % slot
		enemy.call("configure_spawn", slot)
		enemy.connect("died", _on_network_enemy_died)
		return enemy

	push_error("Unknown network entity kind: %s" % kind)
	return Node3D.new()


func _spawn_avatar(peer_id: int) -> void:
	if not multiplayer.is_server() or peer_id < 1:
		return
	if _entities.get_node_or_null("Peer_%d" % peer_id) != null:
		return
	_spawner.spawn({"kind": "player", "peer_id": peer_id})
	_refresh_session_status()


func _spawn_initial_enemies() -> void:
	if not multiplayer.is_server():
		return
	for slot in range(1, INITIAL_ENEMY_COUNT + 1):
		_spawn_enemy(slot)


func _spawn_enemy(slot: int) -> void:
	if not multiplayer.is_server() or not is_inside_tree() or slot < 1:
		return
	if _entities.get_node_or_null("Enemy_%02d" % slot) != null:
		return
	_spawner.spawn({"kind": "enemy", "enemy_slot": slot})


func _on_network_enemy_died(enemy: Node, attacker_peer_id: int) -> void:
	if not multiplayer.is_server() or not is_instance_valid(enemy):
		return
	if attacker_peer_id > 0:
		var attacker := _entities.get_node_or_null("Peer_%d" % attacker_peer_id)
		if is_instance_valid(attacker) and attacker.has_method("register_enemy_defeat"):
			attacker.call("register_enemy_defeat")
		if is_instance_valid(_status_label):
			_status_label.text = "هُزم العدو %s." % str(enemy.name)

	var slot := int(enemy.get("enemy_slot"))
	enemy.queue_free()
	_respawn_enemy_after_delay(slot)


func _respawn_enemy_after_delay(slot: int) -> void:
	await get_tree().create_timer(ENEMY_RESPAWN_SECONDS).timeout
	if not is_inside_tree() or not multiplayer.is_server():
		return
	_spawn_enemy(slot)


func _on_peer_arena_ready(peer_id: int) -> void:
	_spawn_avatar(peer_id)


func _on_peer_left(peer_id: int) -> void:
	if multiplayer.is_server():
		var avatar := _entities.get_node_or_null("Peer_%d" % peer_id)
		if avatar != null:
			avatar.queue_free()
	_refresh_session_status()


func _on_network_status_changed(_message: String) -> void:
	_refresh_session_status()


func _on_session_ended(_reason: String) -> void:
	call_deferred("_return_to_menu")


func _refresh_session_status() -> void:
	if not is_instance_valid(_status_label) or not is_instance_valid(_player_count_label):
		return
	var mode_label := "مضيف" if NetworkManager.session_mode == "host" else "عميل"
	_status_label.text = "نوع الجلسة: %s — القتال والضرر يقررهما الخادم." % mode_label
	var count := multiplayer.get_peers().size() + 1
	_player_count_label.text = "اللاعبون المتصلون: %d" % count


func _refresh_combat_hud() -> void:
	if not is_instance_valid(_combat_label) or not is_inside_tree():
		return
	if not is_instance_valid(_local_avatar):
		var wanted_id := multiplayer.get_unique_id()
		for node in _entities.get_children():
			if node.has_method("configure_owner") and int(node.get("owner_peer_id")) == wanted_id:
				_local_avatar = node
				break
	if not is_instance_valid(_local_avatar):
		_combat_label.text = "جارٍ إنشاء شخصية اللاعب..."
		return

	var health := roundi(float(_local_avatar.get("current_health")))
	var max_hp := roundi(float(_local_avatar.get("max_health")))
	var level := int(_local_avatar.get("level"))
	var xp := int(_local_avatar.get("experience"))
	var quest_progress := int(_local_avatar.get("quest_progress"))
	var quest_completed := bool(_local_avatar.get("quest_completed"))
	var next_xp := 0 if level >= 50 else 100 + ((level - 1) * 50)
	var quest_text := "مكتملة" if quest_completed else "%d / %d أشباح" % [quest_progress, 3]
	var life_text := " — تنتظر العودة..." if bool(_local_avatar.get("is_dead")) else ""
	_combat_label.text = "الصحة: %d / %d%s\nالمستوى: %d — الخبرة: %d / %d\nمهمة اقتفاء الرماد: %s" % [
		health, max_hp, life_text, level, xp, next_xp, quest_text
	]


func _return_to_menu() -> void:
	NetworkManager.leave_session()
	var result := get_tree().change_scene_to_file(MENU_SCENE)
	if result != OK:
		push_error("Could not return to the main menu: %s" % error_string(result))
