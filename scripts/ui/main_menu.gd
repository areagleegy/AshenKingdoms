extends Control

const SOLO_SCENE: String = "res://scenes/boot/Main.tscn"
const NETWORK_SCENE: String = "res://scenes/network/MultiplayerArena.tscn"
const DEFAULT_PORT: int = 7777
const INPUT_SETUP_SCRIPT = preload("res://scripts/core/input_setup.gd")

var _address_input: LineEdit
var _port_input: LineEdit
var _status_label: Label
var _join_button: Button
var _solo_button: Button


func _ready() -> void:
	INPUT_SETUP_SCRIPT.register_input_actions()
	NetworkManager.status_changed.connect(_on_network_status_changed)
	NetworkManager.session_connected.connect(_on_session_connected)
	NetworkManager.connection_failed.connect(_on_connection_failed)

	if _is_server_mode():
		var result := NetworkManager.start_host(_server_port_from_arguments(), 32)
		if result == OK:
			call_deferred("_enter_network_scene")
		else:
			push_error("Dedicated server could not start: %s" % error_string(result))
			get_tree().quit(1)
		return

	_set_mouse_visible_for_menu()
	_build_ui()
	call_deferred("_focus_default_control")


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.035, 0.035, 0.055, 1.0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(500.0, 0.0)
	center.add_child(panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	panel.add_child(layout)

	var title := Label.new()
	title.text = "ممالك الرماد"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	layout.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "AshenKingdoms — نسخة تطوير تجريبية"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(subtitle)

	_solo_button = Button.new()
	_solo_button.text = "اللعب الفردي"
	_solo_button.custom_minimum_size = Vector2(0.0, 48.0)
	_solo_button.focus_mode = Control.FOCUS_ALL
	_solo_button.pressed.connect(_start_solo)
	layout.add_child(_solo_button)

	var separator := HSeparator.new()
	layout.add_child(separator)

	var network_title := Label.new()
	network_title.text = "جلسة شبكة تجريبية"
	network_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(network_title)

	_address_input = LineEdit.new()
	_address_input.text = "127.0.0.1"
	_address_input.placeholder_text = "عنوان الخادم (IP أو اسم المضيف)"
	_address_input.clear_button_enabled = true
	layout.add_child(_address_input)

	_port_input = LineEdit.new()
	_port_input.text = str(DEFAULT_PORT)
	_port_input.placeholder_text = "منفذ الاتصال"
	_port_input.max_length = 5
	_port_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	layout.add_child(_port_input)

	var network_supported := not OS.has_feature("web")
	var host_button := Button.new()
	host_button.text = "استضافة جلسة على هذا الجهاز"
	host_button.custom_minimum_size = Vector2(0.0, 46.0)
	host_button.disabled = not network_supported
	host_button.pressed.connect(_start_host)
	layout.add_child(host_button)

	_join_button = Button.new()
	_join_button.text = "الانضمام إلى الخادم"
	_join_button.custom_minimum_size = Vector2(0.0, 46.0)
	_join_button.disabled = not network_supported
	_join_button.pressed.connect(_start_client)
	layout.add_child(_join_button)

	var note := Label.new()
	if network_supported:
		note.text = "يد التحكم: العصا اليسرى للحركة واليمنى للكاميرا؛ A/Cross للقفز، X/Square أو RT/R2 للهجوم، B/Circle للتفاعل، Y/Triangle للحقيبة، ضغط العصا اليسرى للركض، Start/Options للإيقاف. جلسة الشبكة تجريبية."
	else:
		note.text = "نسخة Web تدعم اللعب الفردي في هذه المرحلة. جلسة ENet التجريبية متاحة عبر Desktop أو Android."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(note)

	_status_label = Label.new()
	_status_label.text = "اختر اللعب الفردي أو ابدأ جلسة شبكة." if network_supported else "استخدم نسخة Desktop أو Android لاختبار الشبكة."
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(0.0, 44.0)
	layout.add_child(_status_label)


func _start_solo() -> void:
	NetworkManager.leave_session()
	var result := get_tree().change_scene_to_file(SOLO_SCENE)
	if result != OK:
		_set_status("تعذر فتح مشهد اللعب الفردي: %s" % error_string(result))


func _start_host() -> void:
	if OS.has_feature("web"):
		_set_status("الاستضافة عبر ENet غير متاحة في نسخة Web.")
		return
	var port := _read_port()
	if port < 1 or port > 65535:
		_set_status("أدخل منفذًا صحيحًا بين 1 و65535.")
		return

	var result := NetworkManager.start_host(port)
	if result != OK:
		_set_status("تعذر بدء الاستضافة: %s" % error_string(result))
		return
	_enter_network_scene()


func _start_client() -> void:
	if OS.has_feature("web"):
		_set_status("الاتصال عبر ENet غير متاح في نسخة Web.")
		return
	var port := _read_port()
	var address := _address_input.text.strip_edges()
	if address.is_empty():
		_set_status("أدخل عنوان IP أو اسم المضيف.")
		return
	if port < 1 or port > 65535:
		_set_status("أدخل منفذًا صحيحًا بين 1 و65535.")
		return

	var result := NetworkManager.start_client(address, port)
	if result != OK:
		_set_status("تعذر بدء الاتصال: %s" % error_string(result))
		return
	_join_button.disabled = true


func _enter_network_scene() -> void:
	var result := get_tree().change_scene_to_file(NETWORK_SCENE)
	if result != OK:
		_set_status("تعذر فتح ساحة الشبكة: %s" % error_string(result))
		NetworkManager.leave_session()


func _read_port() -> int:
	if not _port_input.text.is_valid_int():
		return -1
	return _port_input.text.to_int()


func _server_port_from_arguments() -> int:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--server-port="):
			var value := argument.trim_prefix("--server-port=")
			if value.is_valid_int():
				return value.to_int()
	return DEFAULT_PORT


func _is_server_mode() -> bool:
	return (
		DisplayServer.get_name() == "headless"
		or OS.has_feature("dedicated_server")
		or "--server" in OS.get_cmdline_user_args()
	)


func _on_network_status_changed(message: String) -> void:
	_set_status(message)


func _on_session_connected() -> void:
	_enter_network_scene()


func _on_connection_failed(reason: String) -> void:
	_set_status(reason)
	if is_instance_valid(_join_button):
		_join_button.disabled = false




func _set_mouse_visible_for_menu() -> void:
	if OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"):
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _focus_default_control() -> void:
	if is_instance_valid(_solo_button) and _solo_button.is_visible_in_tree():
		_solo_button.grab_focus()


func _set_status(message: String) -> void:
	if is_instance_valid(_status_label):
		_status_label.text = message
