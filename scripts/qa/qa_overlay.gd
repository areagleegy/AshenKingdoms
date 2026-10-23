extends CanvasLayer

const QA_FEATURE := "qa_tools"
const QATestRunnerScript: Script = preload("res://scripts/qa/qa_test_runner.gd")

var _report_button: Button


func _ready() -> void:
	if not OS.has_feature(QA_FEATURE):
		return
	layer = 100
	_report_button = Button.new()
	_report_button.name = "QAReportButton"
	_report_button.text = "QA / تقرير"
	_report_button.tooltip_text = "تشغيل فحوص QA وتصدير أدلة الجلسة"
	_report_button.custom_minimum_size = Vector2(104.0, 42.0)
	_report_button.anchor_left = 1.0
	_report_button.anchor_right = 1.0
	_report_button.anchor_top = 0.0
	_report_button.anchor_bottom = 0.0
	_report_button.offset_left = -116.0
	_report_button.offset_right = -12.0
	_report_button.offset_top = 12.0
	_report_button.offset_bottom = 54.0
	_report_button.pressed.connect(_run_and_export)
	add_child(_report_button)
	set_process(true)
	_update_visibility()


func _process(_delta: float) -> void:
	_update_visibility()


func _update_visibility() -> void:
	if not is_instance_valid(_report_button):
		return
	var current := get_tree().current_scene
	# The main menu already exposes the QA action; this overlay follows the
	# tester into gameplay so an end-of-session report can include real play.
	_report_button.visible = current == null or current.scene_file_path != "res://scenes/ui/MainMenu.tscn"


func _run_and_export() -> void:
	var reporter := get_tree().root.get_node_or_null("QAReporter")
	if reporter == null:
		_show_window("تعذر العثور على QAReporter.", "")
		return

	var runner := QATestRunnerScript.new() as Node
	if runner == null:
		_show_window("تعذر إنشاء مشغل اختبارات QA.", "")
		return
	runner.name = "QATestRunner"
	get_tree().root.add_child(runner)
	var summary: Dictionary = runner.call("run_smoke_tests")
	runner.queue_free()

	reporter.call("record_event", "qa_report_requested", {
		"passed": int(summary.get("passed", 0)),
		"failed": int(summary.get("failed", 0)),
		"skipped": int(summary.get("skipped", 0)),
	})
	var exported: Dictionary = reporter.call("export_report")
	var report_json := str(reporter.call("get_report_json"))
	var heading := "نجح: %d | فشل: %d | يحتاج تحققًا يدويًا: %d" % [
		int(summary.get("passed", 0)),
		int(summary.get("failed", 0)),
		int(summary.get("skipped", 0)),
	]
	if bool(exported.get("ok", false)):
		heading += "\nحُفظ التقرير داخل بيانات التطبيق: " + str(exported.get("path", ""))
	else:
		heading += "\nتعذر حفظ الملف؛ استخدم زر نسخ JSON."
	_show_window(heading, report_json)


func _show_window(heading: String, report_json: String) -> void:
	var window := Window.new()
	window.title = "AshenKingdoms — QA beta report"
	window.size = Vector2i(860, 620)
	window.min_size = Vector2i(360, 360)
	window.close_requested.connect(window.queue_free)

	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 12.0
	layout.offset_top = 12.0
	layout.offset_right = -12.0
	layout.offset_bottom = -12.0
	layout.add_theme_constant_override("separation", 8)
	window.add_child(layout)

	var summary_label := Label.new()
	summary_label.text = heading
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(summary_label)

	var report_text := TextEdit.new()
	report_text.editable = false
	report_text.text = report_json
	report_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(report_text)

	var controls := HBoxContainer.new()
	layout.add_child(controls)
	var copy_button := Button.new()
	copy_button.text = "نسخ JSON"
	copy_button.disabled = report_json.is_empty()
	copy_button.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(report_json)
		copy_button.text = "تم النسخ"
	)
	controls.add_child(copy_button)
	var close_button := Button.new()
	close_button.text = "إغلاق"
	close_button.pressed.connect(window.queue_free)
	controls.add_child(close_button)

	get_tree().root.add_child(window)
	window.popup_centered()


