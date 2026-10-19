extends CanvasLayer

@onready var open_button: Button = $OpenButton
@onready var panel: PanelContainer = $Panel
@onready var title_label: Label = $Panel/Margin/VBox/Title
@onready var status_label: Label = $Panel/Margin/VBox/Status
@onready var packs_list: VBoxContainer = $Panel/Margin/VBox/Scroll/Packs
@onready var refresh_button: Button = $Panel/Margin/VBox/Actions/Refresh
@onready var close_button: Button = $Panel/Margin/VBox/Actions/Close


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel.visible = false
	open_button.pressed.connect(_toggle_panel)
	refresh_button.pressed.connect(_refresh_catalog)
	close_button.pressed.connect(func() -> void: panel.visible = false)
	ContentManager.catalog_updated.connect(_on_catalog_updated)
	ContentManager.pack_state_changed.connect(_on_pack_state_changed)
	ContentManager.download_progress.connect(_on_download_progress)
	_update_status()


func _toggle_panel() -> void:
	panel.visible = not panel.visible
	if panel.visible:
		_update_status()
		_render_packs()


func _refresh_catalog() -> void:
	status_label.text = "جارٍ الاتصال بخدمة المحتوى..."
	ContentManager.refresh_catalog()


func _on_catalog_updated(_catalog: Dictionary) -> void:
	_update_status()
	_render_packs()


func _on_pack_state_changed(_pack_id: String, _state: String, _details: Dictionary) -> void:
	_update_status()
	_render_packs()


func _on_download_progress(pack_id: String, downloaded_bytes: int, total_bytes: int) -> void:
	if panel.visible:
		var downloaded_mb := float(downloaded_bytes) / 1048576.0
		var total_mb := float(total_bytes) / 1048576.0
		status_label.text = "تنزيل %s: %.1f / %.1f MB" % [pack_id, downloaded_mb, total_mb]


func _update_status() -> void:
	var state := ContentManager.get_catalog_state()
	match state:
		"ready":
			status_label.text = "المحتوى جاهز. اختر الحزم التي تريد تنزيلها."
		"loading":
			status_label.text = "جارٍ تحميل فهرس المحتوى..."
		"not_configured":
			status_label.text = "خدمة الحزم غير مهيأة بعد؛ اللعبة الأساسية تعمل دون إنترنت."
		"not_loaded":
			status_label.text = "لم يُحمّل فهرس المحتوى بعد. اضغط تحديث."
		_:
			status_label.text = "تعذر تحميل المحتوى: %s" % ContentManager.get_last_error()


func _render_packs() -> void:
	for child in packs_list.get_children():
		child.queue_free()
	var catalog: Dictionary = ContentManager.get_catalog()
	var installed: Dictionary = ContentManager.get_installed_packs()
	if catalog.is_empty() and installed.is_empty():
		var empty_label := Label.new()
		empty_label.text = "لا توجد حزم متاحة حاليًا."
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		packs_list.add_child(empty_label)
		return
	if catalog.is_empty():
		var offline_label := Label.new()
		offline_label.text = "الفهرس غير متاح؛ يمكنك إدارة الحزم المثبتة محليًا."
		offline_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		packs_list.add_child(offline_label)
		for installed_id in installed:
			var installed_row := HBoxContainer.new()
			var installed_label := Label.new()
			installed_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			installed_label.text = "%s · %s" % [str(installed_id), str(installed[installed_id].get("version", ""))]
			installed_row.add_child(installed_label)
			var installed_delete := Button.new()
			installed_delete.text = "حذف"
			installed_delete.custom_minimum_size = Vector2(108, 42)
			installed_delete.pressed.connect(_delete_pack.bind(str(installed_id)))
			installed_row.add_child(installed_delete)
			packs_list.add_child(installed_row)
		return
	for pack_id in catalog:
		var record: Dictionary = catalog[pack_id]
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var description := Label.new()
		description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.text = "%s  ·  %s  ·  %.1f MB" % [
			str(record.get("name", pack_id)),
			str(record.get("type", "content")),
			float(record.get("download_size", 0)) / 1048576.0
		]
		row.add_child(description)
		var action := Button.new()
		action.custom_minimum_size = Vector2(108, 42)
		if _is_downloading(str(pack_id)):
			action.text = "إلغاء"
			action.pressed.connect(_cancel_pack.bind(str(pack_id)))
		elif installed.has(str(pack_id)):
			var installed_record: Dictionary = installed[str(pack_id)]
			if str(installed_record.get("version", "")) != str(record.get("version", "")):
				action.text = "تحديث"
				action.pressed.connect(_download_pack.bind(str(pack_id)))
			else:
				action.text = "حذف"
				action.pressed.connect(_delete_pack.bind(str(pack_id)))
		else:
			action.text = "تنزيل"
			action.pressed.connect(_download_pack.bind(str(pack_id)))
		row.add_child(action)
		packs_list.add_child(row)
	for installed_id in installed:
		if catalog.has(str(installed_id)):
			continue
		var installed_row := HBoxContainer.new()
		var installed_label := Label.new()
		installed_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		installed_label.text = "%s · %s (مثبتة محليًا)" % [str(installed_id), str(installed[installed_id].get("version", ""))]
		installed_row.add_child(installed_label)
		var installed_delete := Button.new()
		installed_delete.text = "حذف"
		installed_delete.custom_minimum_size = Vector2(108, 42)
		installed_delete.pressed.connect(_delete_pack.bind(str(installed_id)))
		installed_row.add_child(installed_delete)
		packs_list.add_child(installed_row)


func _is_downloading(pack_id: String) -> bool:
	return ContentManager.has_method("is_downloading") and bool(ContentManager.call("is_downloading", pack_id))


func _download_pack(pack_id: String) -> void:
	var result: int = ContentManager.download_pack(pack_id)
	if result != OK:
		status_label.text = "تعذر بدء التنزيل. رمز الخطأ: %d" % result


func _cancel_pack(pack_id: String) -> void:
	ContentManager.cancel_download(pack_id)


func _delete_pack(pack_id: String) -> void:
	var result: Dictionary = ContentManager.delete_pack(pack_id)
	if not bool(result.get("ok", false)):
		status_label.text = str(result.get("error", "تعذر حذف الحزمة."))
		return
	_render_packs()
