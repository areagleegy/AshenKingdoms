extends Control

const SOLO_SCENE: String = "res://scenes/boot/Main.tscn"
const NETWORK_SCENE: String = "res://scenes/network/MultiplayerArena.tscn"
const DEFAULT_PORT: int = 7777

var _address_input: LineEdit
var _port_input: LineEdit
var _status_label: Label
var _join_button: Button


func _ready() -> void:
	_initialize_qa_reporter()
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

	_build_ui()


func _initialize_qa_reporter() -> void:
	if not OS.has_feature("qa_tools"):
		return
	if get_tree().root.get_node_or_null("QAReporter") != null:
		return
	var reporter_script := load("res://scripts/qa/qa_reporter.gd") as Script
	if reporter_script == null:
		push_warning("QA reporter script could not be loaded in this QA build.")
		return
	var reporter := reporter_script.new() as Node
	reporter.name = "QAReporter"
	get_tree().root.add_child(reporter)
	reporter.call("record_event", "main_menu_ready")

	var overlay_script := load("res://scripts/qa/qa_overlay.gd") as Script
	if overlay_script != null and get_tree().root.get_node_or_null("QAOverlay") == null:
		var overlay := overlay_script.new() as CanvasLayer
		if overlay != null:
			overlay.name = "QAOverlay"
			get_tree().root.add_child(overlay)
	else:
		_qa_record_event("qa_overlay_load_failed")


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

	if OS.has_feature("qa_tools"):
		var qa_button := Button.new()
		qa_button.text = "فحص QA ونسخ التقرير"
		qa_button.custom_minimum_size = Vector2(0.0, 46.0)
		qa_button.pressed.connect(_run_qa_diagnostics)
		layout.add_child(qa_button)

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
		note.text = "تشمل هذه المرحلة حركة متزامنة وقتالًا وصحة وأعداءً ومهمة قتل تجريبية. لا تتوفر مزامنة كاملة للجرد والحوار أو حفظ شبكي دائم."
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


func _run_qa_diagnostics() -> void:
	if not OS.has_feature("qa_tools"):
		return

	var reporter := get_tree().root.get_node_or_null("QAReporter")
	if reporter == null:
		_set_status("تعذّر تشغيل QAReporter في هذا البناء.")
		return

	var runner_script := load("res://scripts/qa/qa_test_runner.gd") as Script
	if runner_script == null:
		reporter.call("record_event", "qa_test_runner_load_failed")
		_set_status("تعذّر تحميل مشغّل اختبارات QA.")
		return

	var runner := runner_script.new() as Node
	runner.name = "QATestRunner"
	get_tree().root.add_child(runner)
	var summary: Dictionary = runner.call("run_smoke_tests")
	runner.queue_free()

	reporter.call("record_event", "qa_report_requested", {
		"passed": int(summary.get("passed", 0)),
		"failed": int(summary.get("failed", 0)),
	})
	var export_result: Dictionary = reporter.call("export_report")
	var report_json: String = str(reporter.call("get_report_json"))
	_show_qa_report_window(summary, export_result, report_json)


func _show_qa_report_window(summary: Dictionary, export_result: Dictionary, report_json: String) -> void:
	var qa_window := Window.new()
	qa_window.title = "تقرير QA — ممالك الرماد"
	qa_window.size = Vector2i(920, 640)
	qa_window.min_size = Vector2i(360, 360)
	qa_window.close_requested.connect(qa_window.queue_free)

	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 12.0
	layout.offset_top = 12.0
	layout.offset_right = -12.0
	layout.offset_bottom = -12.0
	layout.add_theme_constant_override("separation", 8)
	qa_window.add_child(layout)

	var summary_label := Label.new()
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_label.text = "نجح: %d | فشل: %d | يحتاج تحققًا يدويًا: %d | التقرير محلي." % [
		int(summary.get("passed", 0)),
		int(summary.get("failed", 0)),
		int(summary.get("skipped", 0)),
	]
	var report_path := str(export_result.get("path", ""))
	if bool(export_result.get("ok", false)):
		summary_label.text += "\nمسار الملف داخل بيانات التطبيق: " + report_path
	else:
		summary_label.text += "\nتعذّر حفظ الملف؛ يمكنك نسخ JSON من هذه النافذة."
	layout.add_child(summary_label)

	var report_view := TextEdit.new()
	report_view.editable = false
	report_view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	report_view.text = report_json
	report_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	report_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(report_view)

	var status_label := Label.new()
	status_label.text = "لا يوجد إرسال شبكي أو تحليل AI داخل APK."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(status_label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	layout.add_child(buttons)

	var copy_button := Button.new()
	copy_button.text = "نسخ JSON"
	copy_button.disabled = not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD)
	copy_button.pressed.connect(_copy_qa_report.bind(report_json, status_label))
	buttons.add_child(copy_button)

	var close_button := Button.new()
	close_button.text = "إغلاق"
	close_button.pressed.connect(qa_window.queue_free)
	buttons.add_child(close_button)

	add_child(qa_window)
	qa_window.popup_centered(qa_window.size)


func _copy_qa_report(report_json: String, status_label: Label) -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		status_label.text = "الحافظة غير مدعومة هنا؛ حدّد نص JSON وانسخه يدويًا."
		return
	DisplayServer.clipboard_set(report_json)
	status_label.text = "نُسخ تقرير QA إلى الحافظة. يمكنك لصقه في تقرير Issue أو رسالة."


func _set_status(message: String) -> void:
	if is_instance_valid(_status_label):
		_status_label.text = message
