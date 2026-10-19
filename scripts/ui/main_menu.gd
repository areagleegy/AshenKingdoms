extends Control

const SOLO_SCENE: String = "res://scenes/boot/Main.tscn"
const NETWORK_SCENE: String = "res://scenes/network/MultiplayerArena.tscn"
const DEFAULT_PORT: int = 7777
const DEFAULT_WEBSOCKET_PORT: int = 7778

var _address_input: LineEdit
var _port_input: LineEdit
var _status_label: Label
var _join_button: Button
var _host_button: Button
var _transport_option: OptionButton


func _ready() -> void:
	NetworkManager.status_changed.connect(_on_network_status_changed)
	NetworkManager.session_connected.connect(_on_session_connected)
	NetworkManager.connection_failed.connect(_on_connection_failed)

	if _is_server_mode():
		var server_port := _server_port_from_arguments()
		var result := (
			NetworkManager.start_websocket_host(server_port, 32)
			if _server_transport_from_arguments() == "websocket"
			else NetworkManager.start_host(server_port, 32)
		)
		if result == OK:
			call_deferred("_enter_network_scene")
		else:
			push_error("Dedicated server could not start: %s" % error_string(result))
			get_tree().quit(1)
		return

	_build_ui()


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

	var solo_button := Button.new()
	solo_button.text = "اللعب الفردي"
	solo_button.custom_minimum_size = Vector2(0.0, 48.0)
	solo_button.pressed.connect(_start_solo)
	layout.add_child(solo_button)

	var separator := HSeparator.new()
	layout.add_child(separator)

	var network_title := Label.new()
	network_title.text = "جلسة شبكة تجريبية"
	network_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(network_title)

	_transport_option = OptionButton.new()
	_transport_option.add_item("ENet عبر UDP — Desktop / Android", 0)
	_transport_option.add_item("WebSocket — Web / Online", 1)
	_transport_option.select(1 if OS.has_feature("web") else 0)
	_transport_option.item_selected.connect(_on_transport_selected)
	layout.add_child(_transport_option)

	_address_input = LineEdit.new()
	_address_input.text = "" if OS.has_feature("web") else "127.0.0.1"
	_address_input.placeholder_text = "عنوان الخادم (IP أو اسم المضيف)"
	_address_input.clear_button_enabled = true
	layout.add_child(_address_input)

	_port_input = LineEdit.new()
	_port_input.text = str(DEFAULT_WEBSOCKET_PORT if OS.has_feature("web") else DEFAULT_PORT)
	_port_input.placeholder_text = "منفذ الاتصال / الاستضافة"
	_port_input.max_length = 5
	_port_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	layout.add_child(_port_input)

	var browser_build := OS.has_feature("web")
	_host_button = Button.new()
	_host_button.text = "استضافة جلسة على هذا الجهاز"
	_host_button.custom_minimum_size = Vector2(0.0, 46.0)
	_host_button.disabled = browser_build
	_host_button.pressed.connect(_start_host)
	layout.add_child(_host_button)

	_join_button = Button.new()
	_join_button.text = "الانضمام إلى الخادم"
	_join_button.custom_minimum_size = Vector2(0.0, 46.0)
	_join_button.disabled = false
	_join_button.pressed.connect(_start_client)
	layout.add_child(_join_button)

	var note := Label.new()
	if browser_build:
		note.text = "المتصفح ينضم عبر WebSocket فقط ولا يستطيع استضافة خادم. أدخل رابط wss:// لخادم متاح عبر HTTPS."
	else:
		note.text = "ENet مناسب لشبكة LAN أو خادم UDP عام؛ WebSocket مناسب للمتصفح أو لخادم خلف وكيل TLS. لا تتضمن هذه النسخة غرفًا أو حسابات."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(note)

	_status_label = Label.new()
	_status_label.text = "اختر وسيلة النقل ثم اتصل بخادم متاح."
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(0.0, 44.0)
	layout.add_child(_status_label)
	_on_transport_selected(_transport_option.get_selected_id())


func _start_solo() -> void:
	NetworkManager.leave_session()
	var result := get_tree().change_scene_to_file(SOLO_SCENE)
	if result != OK:
		_set_status("تعذر فتح مشهد اللعب الفردي: %s" % error_string(result))


func _start_host() -> void:
	if OS.has_feature("web"):
		_set_status("لا يمكن للمتصفح استضافة خادم؛ اتصل بخادم WebSocket خارجي.")
		return
	var port := _read_port()
	if port < 1 or port > 65535:
		_set_status("أدخل منفذًا صحيحًا بين 1 و65535.")
		return

	var result := (
		NetworkManager.start_websocket_host(port)
		if _selected_transport() == "websocket"
		else NetworkManager.start_host(port)
	)
	if result != OK:
		_set_status("تعذر بدء الاستضافة: %s" % error_string(result))
		return
	_enter_network_scene()


func _start_client() -> void:
	var port := _read_port()
	var address := _address_input.text.strip_edges()
	if address.is_empty():
		_set_status("أدخل عنوان الخادم أو رابط WebSocket.")
		return
	if port < 1 or port > 65535:
		_set_status("أدخل منفذًا صحيحًا بين 1 و65535.")
		return

	var result: int
	if _selected_transport() == "websocket":
		var url := _normalize_websocket_url(address, port)
		if url.is_empty():
			_set_status("أدخل رابطًا يبدأ بـ ws:// أو wss://، أو اسم مضيف ومنفذ صالحين.")
			return
		result = NetworkManager.start_websocket_client(url)
	else:
		if OS.has_feature("web"):
			_set_status("نسخة المتصفح تستخدم WebSocket؛ اختره من قائمة وسيلة النقل.")
			return
		result = NetworkManager.start_client(address, port)

	if result != OK:
		_set_status("تعذر بدء الاتصال: %s" % error_string(result))
		return
	_join_button.disabled = true


func _selected_transport() -> String:
	if is_instance_valid(_transport_option) and _transport_option.get_selected_id() == 1:
		return "websocket"
	return "enet"


func _normalize_websocket_url(address: String, port: int) -> String:
	if address.begins_with("ws://") or address.begins_with("wss://"):
		return address
	if address.contains("://") or address.contains("/") or address.contains(" "):
		return ""
	var scheme := "wss://" if OS.has_feature("web") else "ws://"
	return "%s%s:%d" % [scheme, address, port]


func _on_transport_selected(_index: int) -> void:
	if not is_instance_valid(_address_input) or not is_instance_valid(_port_input):
		return
	if _selected_transport() == "websocket":
		_address_input.placeholder_text = "رابط ws:// أو wss://، أو اسم مضيف"
		if _address_input.text.strip_edges().is_empty():
			_address_input.text = "" if OS.has_feature("web") else "ws://127.0.0.1:7778"
		if _port_input.text == str(DEFAULT_PORT):
			_port_input.text = str(DEFAULT_WEBSOCKET_PORT)
		_set_status("WebSocket: في الإنتاج استخدم wss:// خلف وكيل TLS عند استضافة الموقع عبر HTTPS.")
	else:
		_address_input.placeholder_text = "عنوان الخادم (IP أو اسم المضيف)"
		if _address_input.text.begins_with("ws://") or _address_input.text.begins_with("wss://"):
			_address_input.text = "127.0.0.1"
		if _port_input.text == str(DEFAULT_WEBSOCKET_PORT):
			_port_input.text = str(DEFAULT_PORT)
		_set_status("ENet يستخدم UDP. للاتصال عبر الإنترنت يجب إتاحة منفذ UDP على الخادم.")


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


func _server_transport_from_arguments() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument == "--server-transport=websocket":
			return "websocket"
	return "enet"


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


func _set_status(message: String) -> void:
	if is_instance_valid(_status_label):
		_status_label.text = message
