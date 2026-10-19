@tool
extends EditorPlugin

const SUPPORTED_EXTENSIONS = [
	"glb", "gltf", "obj", "dae",
	"png", "jpg", "jpeg", "webp", "svg",
	"wav", "ogg", "mp3", "flac",
	"mp4", "webm"
]

const CATEGORIES = [
	{"label": "الشخصيات والنماذج", "path": "res://assets/characters"},
	{"label": "البيئات", "path": "res://assets/environments"},
	{"label": "الخامات والصور", "path": "res://assets/materials"},
	{"label": "الموسيقى والمؤثرات والحوار", "path": "res://assets/audio"},
	{"label": "الفيديو السينمائي", "path": "res://assets/video/cinematics"},
	{"label": "واجهات اللعبة", "path": "res://assets/ui"}
]

var _panel: VBoxContainer
var _status_label: Label


func _enter_tree() -> void:
	_panel = VBoxContainer.new()
	_panel.name = "AshenFreeAssetPipelinePanel"
	_panel.custom_minimum_size = Vector2(0, 190)

	var heading := Label.new()
	heading.text = "مسار الأصول المجاني — ممالك الرماد"
	heading.add_theme_font_size_override("font_size", 16)
	_panel.add_child(heading)

	var explanation := Label.new()
	explanation.text = "يربط مجلدات استيراد الأصول داخل المشروع. لا يتصل بخدمات سحابية ولا يستهلك أرصدة."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(explanation)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(_status_label)

	var actions := HBoxContainer.new()
	var refresh_button := Button.new()
	refresh_button.text = "تحديث الجرد"
	refresh_button.pressed.connect(_refresh_summary)
	actions.add_child(refresh_button)

	var manifest_button := Button.new()
	manifest_button.text = "فتح مجلد الأصول"
	manifest_button.pressed.connect(_open_assets_root)
	actions.add_child(manifest_button)
	_panel.add_child(actions)

	var categories_row := HBoxContainer.new()
	for category in CATEGORIES:
		var open_button := Button.new()
		open_button.text = str(category["label"])
		open_button.tooltip_text = str(category["path"])
		open_button.pressed.connect(_open_category.bind(str(category["path"])))
		categories_row.add_child(open_button)
	_panel.add_child(categories_row)

	add_control_to_bottom_panel(_panel, "Ashen Free Assets")
	_refresh_summary()


func _exit_tree() -> void:
	if _panel != null:
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
	_panel = null
	_status_label = null


func _refresh_summary() -> void:
	if _status_label == null:
		return

	var lines := PackedStringArray()
	var total := 0
	for category in CATEGORIES:
		var path: String = str(category["path"])
		var count: int = _count_assets(path)
		total += count
		lines.append("%s: %d" % [str(category["label"]), count])

	lines.append("الإجمالي: %d ملف أصل معروف الصيغة." % total)
	lines.append("الفحص يرصد الملفات فقط؛ صلاحية الترخيص تُراجع عبر assets/asset_manifest.json.")
	_status_label.text = "\n".join(lines)


func _count_assets(directory_path: String) -> int:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return 0

	var count := 0
	for file_name in directory.get_files():
		if file_name.begins_with("."):
			continue
		var extension: String = file_name.get_extension().to_lower()
		if SUPPORTED_EXTENSIONS.has(extension):
			count += 1

	for child_name in directory.get_directories():
		if child_name.begins_with("."):
			continue
		count += _count_assets(directory_path.path_join(child_name))

	return count


func _open_assets_root() -> void:
	_open_category("res://assets")


func _open_category(resource_path: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(resource_path)
	var error := DirAccess.make_dir_recursive_absolute(absolute_path)
	if error != OK:
		_status_label.text = "تعذر إنشاء المجلد: " + resource_path
		return

	var open_error: Error = OS.shell_open(absolute_path)
	if open_error != OK:
		_status_label.text = "تعذر فتح المجلد تلقائيًا. المسار: " + absolute_path
