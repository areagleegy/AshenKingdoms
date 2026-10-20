extends CanvasLayer

signal save_requested
signal load_requested

var _player: CharacterBody3D
var _progression: Node
var _quests: Node
var _inventory: Node

var _health_bar: ProgressBar
var _health_label: Label
var _xp_bar: ProgressBar
var _xp_label: Label
var _quest_label: Label
var _quest_icon: TextureRect
var _message_label: Label
var _root: Control
var _inventory_panel: PanelContainer
var _inventory_list: VBoxContainer
var _pause_panel: PanelContainer

const ICON_INVENTORY: Texture2D = preload("res://assets/ui/icons/backpack.svg")
const ICON_PAUSE: Texture2D = preload("res://assets/ui/icons/pause.svg")
const ICON_SWORD: Texture2D = preload("res://assets/ui/icons/sword.svg")
const ICON_JUMP: Texture2D = preload("res://assets/ui/icons/jump.svg")
const ICON_SPRINT: Texture2D = preload("res://assets/ui/icons/sprint.svg")
const ICON_QUEST: Texture2D = preload("res://assets/ui/icons/quest.svg")
const ICON_QUEST_COMPLETE: Texture2D = preload("res://assets/ui/icons/quest_complete.svg")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func bind_game(player: CharacterBody3D, progression: Node, quest_manager: Node, inventory: Node) -> void:
	_player = player
	_progression = progression
	_quests = quest_manager
	_inventory = inventory

	var health := _player.get_node("Health") as Health
	health.health_changed.connect(_on_health_changed)
	_progression.connect("experience_changed", _on_experience_changed)
	_quests.connect("quest_updated", _on_quest_updated)
	_quests.connect("quest_completed", _on_quest_completed)
	_inventory.connect("inventory_changed", _refresh_inventory)

	_on_health_changed(health.current, health.max_health)
	_on_experience_changed(
		int(_progression.get("experience")),
		int(_progression.call("xp_to_next_level")),
		int(_progression.get("level"))
	)
	_quests.call("refresh_ui")
	_refresh_inventory()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_root)

	var status_panel := PanelContainer.new()
	status_panel.position = Vector2(16, 16)
	status_panel.custom_minimum_size = Vector2(300, 108)
	_root.add_child(status_panel)
	var status_box := VBoxContainer.new()
	status_box.add_theme_constant_override("separation", 5)
	status_panel.add_child(status_box)

	_health_label = Label.new()
	_health_label.text = "الصحة: -- / --"
	status_box.add_child(_health_label)
	_health_bar = ProgressBar.new()
	_health_bar.custom_minimum_size = Vector2(270, 18)
	_health_bar.show_percentage = false
	status_box.add_child(_health_bar)

	_xp_label = Label.new()
	_xp_label.text = "المستوى 1 — الخبرة 0 / 100"
	status_box.add_child(_xp_label)
	_xp_bar = ProgressBar.new()
	_xp_bar.custom_minimum_size = Vector2(270, 14)
	_xp_bar.show_percentage = false
	status_box.add_child(_xp_bar)

	var quest_panel := PanelContainer.new()
	quest_panel.anchor_left = 1.0
	quest_panel.anchor_right = 1.0
	quest_panel.offset_left = -336.0
	quest_panel.offset_right = -16.0
	quest_panel.offset_top = 16.0
	quest_panel.offset_bottom = 112.0
	_root.add_child(quest_panel)
	var quest_row := HBoxContainer.new()
	quest_row.add_theme_constant_override("separation", 8)
	quest_panel.add_child(quest_row)

	_quest_icon = TextureRect.new()
	_quest_icon.texture = ICON_QUEST
	_quest_icon.custom_minimum_size = Vector2(28, 28)
	_quest_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	quest_row.add_child(_quest_icon)

	_quest_label = Label.new()
	_quest_label.custom_minimum_size = Vector2(248, 80)
	_quest_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	quest_row.add_child(_quest_label)

	var inventory_button := Button.new()
	inventory_button.text = "الحقيبة (I)"
	inventory_button.icon = ICON_INVENTORY
	inventory_button.add_theme_constant_override("icon_max_width", 26)
	inventory_button.position = Vector2(16, 136)
	inventory_button.custom_minimum_size = Vector2(132, 42)
	inventory_button.pressed.connect(toggle_inventory)
	inventory_button.pressed.connect(_play_ui_select)
	_root.add_child(inventory_button)

	var pause_button := Button.new()
	pause_button.text = "إيقاف (Esc)"
	pause_button.icon = ICON_PAUSE
	pause_button.add_theme_constant_override("icon_max_width", 26)
	pause_button.position = Vector2(156, 136)
	pause_button.custom_minimum_size = Vector2(132, 42)
	pause_button.pressed.connect(toggle_pause)
	pause_button.pressed.connect(_play_ui_select)
	_root.add_child(pause_button)

	_message_label = Label.new()
	_message_label.position = Vector2(16, 190)
	_message_label.custom_minimum_size = Vector2(380, 32)
	_root.add_child(_message_label)

	_build_inventory_panel()
	_build_pause_panel()
	_build_touch_controls()


func _build_inventory_panel() -> void:
	_inventory_panel = _make_center_panel(Vector2(420, 420))
	_inventory_panel.visible = false
	var box := VBoxContainer.new()
	_inventory_panel.add_child(box)

	var title_label := Label.new()
	title_label.text = "الحقيبة"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title_label)

	_inventory_list = VBoxContainer.new()
	box.add_child(_inventory_list)

	var close_button := Button.new()
	close_button.text = "إغلاق"
	close_button.pressed.connect(func() -> void:
		_set_inventory_visible(false)
	)
	close_button.pressed.connect(_play_ui_select)
	box.add_child(close_button)


func _build_pause_panel() -> void:
	_pause_panel = _make_center_panel(Vector2(360, 330))
	_pause_panel.visible = false
	var box := VBoxContainer.new()
	_pause_panel.add_child(box)

	var title_label := Label.new()
	title_label.text = "اللعبة متوقفة"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title_label)

	var resume_button := Button.new()
	resume_button.text = "استئناف"
	resume_button.pressed.connect(func() -> void:
		_set_paused(false)
	)
	resume_button.pressed.connect(_play_ui_select)
	box.add_child(resume_button)

	var save_button := Button.new()
	save_button.text = "حفظ اللعبة"
	save_button.pressed.connect(func() -> void:
		save_requested.emit()
	)
	save_button.pressed.connect(_play_ui_select)
	box.add_child(save_button)

	var load_button := Button.new()
	load_button.text = "تحميل الحفظ"
	load_button.pressed.connect(func() -> void:
		load_requested.emit()
	)
	load_button.pressed.connect(_play_ui_select)
	box.add_child(load_button)

	var quit_button := Button.new()
	quit_button.text = "خروج"
	quit_button.pressed.connect(func() -> void:
		get_tree().quit()
	)
	quit_button.pressed.connect(_play_ui_select)
	box.add_child(quit_button)


func _make_center_panel(panel_size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -panel_size.x / 2.0
	panel.offset_right = panel_size.x / 2.0
	panel.offset_top = -panel_size.y / 2.0
	panel.offset_bottom = panel_size.y / 2.0
	_root.add_child(panel)
	return panel


func _build_touch_controls() -> void:
	if not (OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")):
		return
	_add_touch_button("↑", "move_forward", 0.0, 1.0, 92.0, -206.0, 62.0, 62.0)
	_add_touch_button("←", "move_left", 0.0, 1.0, 26.0, -140.0, 62.0, 62.0)
	_add_touch_button("→", "move_right", 0.0, 1.0, 158.0, -140.0, 62.0, 62.0)
	_add_touch_button("↓", "move_back", 0.0, 1.0, 92.0, -74.0, 62.0, 62.0)
	_add_touch_button("هجوم", "attack", 1.0, 1.0, -100.0, -92.0, 84.0, 68.0)
	_add_touch_button("قفز", "jump", 1.0, 1.0, -194.0, -158.0, 84.0, 68.0)
	_add_touch_button("ركض", "sprint", 1.0, 1.0, -100.0, -174.0, 84.0, 68.0)


func _add_touch_button(
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
	match action:
		&"attack":
			button.icon = ICON_SWORD
		&"jump":
			button.icon = ICON_JUMP
		&"sprint":
			button.icon = ICON_SPRINT
	button.add_theme_constant_override("icon_max_width", 26)
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
	_root.add_child(button)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not _is_echo(event):
		toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory") and not _is_echo(event):
		toggle_inventory()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("save") and not _is_echo(event):
		save_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("load") and not _is_echo(event):
		load_requested.emit()
		get_viewport().set_input_as_handled()


func _is_echo(event: InputEvent) -> bool:
	if event is InputEventKey:
		return (event as InputEventKey).echo
	return false


func toggle_pause() -> void:
	if _dialogue_active():
		return
	if _pause_panel.visible:
		_set_paused(false)
	else:
		_set_inventory_visible(false)
		_set_paused(true)


func toggle_inventory() -> void:
	if _dialogue_active() or _pause_panel.visible:
		return
	_set_inventory_visible(not _inventory_panel.visible)


func _set_paused(value: bool) -> void:
	_pause_panel.visible = value
	if value:
		_inventory_panel.visible = false
	get_tree().paused = value
	_set_mouse_for_ui(value)


func _set_inventory_visible(value: bool) -> void:
	_inventory_panel.visible = value
	get_tree().paused = value
	_set_mouse_for_ui(value)


func close_overlays() -> void:
	_pause_panel.visible = false
	_inventory_panel.visible = false
	get_tree().paused = false
	_set_mouse_for_ui(false)


func _dialogue_active() -> bool:
	var manager := get_node_or_null("/root/DialogueManager")
	return manager != null and bool(manager.call("is_active"))


func _set_mouse_for_ui(show_mouse: bool) -> void:
	if OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"):
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if show_mouse else Input.MOUSE_MODE_CAPTURED


func _refresh_inventory() -> void:
	if _inventory_list == null:
		return
	for child in _inventory_list.get_children():
		child.queue_free()

	if _inventory == null:
		return

	var slots: Array = _inventory.get("slots")
	var has_items := false
	for index in range(slots.size()):
		var slot: Dictionary = slots[index]
		if slot.is_empty():
			continue
		var item = slot.get("item")
		if item == null:
			continue
		has_items = true
		var item_button := Button.new()
		item_button.text = "%s × %d" % [String(item.get("display_name")), int(slot.get("amount", 1))]
		item_button.pressed.connect(_on_inventory_item_pressed.bind(index))
		item_button.pressed.connect(_play_ui_select)
		_inventory_list.add_child(item_button)

	if not has_items:
		var empty_label := Label.new()
		empty_label.text = "الحقيبة فارغة"
		_inventory_list.add_child(empty_label)


func _on_inventory_item_pressed(slot_index: int) -> void:
	if _inventory == null or _player == null:
		return

	var item_id: StringName = &""
	var slots: Array = _inventory.get("slots")
	if slot_index >= 0 and slot_index < slots.size():
		var item: Variant = slots[slot_index].get("item")
		if item != null:
			item_id = StringName(str(item.get("id")))

	var used: bool = bool(_inventory.call("use_item", slot_index, _player))
	if used and item_id == &"health_potion":
		_play_sfx(&"potion_use", -5.0)
	elif not used:
		show_message("لا يمكن استخدام العنصر الآن.")


func _on_health_changed(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current
	_health_label.text = "الصحة: %d / %d" % [roundi(current), roundi(maximum)]


func _on_experience_changed(experience: int, required: int, level: int) -> void:
	_xp_bar.max_value = maxf(float(required), 1.0)
	_xp_bar.value = experience
	_xp_label.text = "المستوى %d — الخبرة %d / %d" % [level, experience, required]


func _on_quest_updated(title: String, description: String, current: int, target: int) -> void:
	if title == "لا توجد مهمة نشطة":
		_quest_label.text = "%s\n%s" % [title, description]
		if is_instance_valid(_quest_icon):
			_quest_icon.texture = ICON_QUEST
		return
	var is_complete := current >= target
	if is_instance_valid(_quest_icon):
		_quest_icon.texture = ICON_QUEST_COMPLETE if is_complete else ICON_QUEST
	var status := "مكتملة" if is_complete else "%d / %d" % [current, target]
	_quest_label.text = "المهمة: %s\n%s\nالتقدم: %s" % [title, description, status]


func _on_quest_completed(title: String, reward_xp: int) -> void:
	_play_sfx(&"quest_complete", -5.0)
	show_message("اكتملت المهمة «%s»! +%d XP" % [title, reward_xp])


func show_message(message: String) -> void:
	_message_label.text = message


func show_saved_status(success: bool) -> void:
	show_message("تم حفظ اللعبة." if success else "تعذر حفظ اللعبة.")


func _play_ui_select() -> void:
	_play_sfx(&"ui_select", -11.0)


func _play_sfx(sound_id: StringName, volume_db: float = -6.0) -> void:
	var audio_feedback := get_node_or_null("/root/AudioFeedback")
	if audio_feedback != null:
		audio_feedback.call("play_sfx", sound_id, volume_db)
