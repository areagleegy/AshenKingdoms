@tool
extends EditorPlugin

const PLAYER_MODEL_PATH: String = "res://assets/characters/player/player.glb"
const PLAYER_ASSET_DIRECTORY: String = "res://assets/characters/player"

var _panel: VBoxContainer
var _status_label: Label


func _enter_tree() -> void:
	_panel = VBoxContainer.new()
	_panel.name = "AshenAssetBridgePanel"
	_panel.custom_minimum_size = Vector2(0, 150)

	var heading := Label.new()
	heading.text = "مساعد أصول ممالك الرماد"
	heading.add_theme_font_size_override("font_size", 16)
	_panel.add_child(heading)

	var details := Label.new()
	details.text = "يفحص نموذج اللاعب المستورد ومكونات الشبكة والهيكل العظمي والحركات."
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(details)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(_status_label)

	var buttons := HBoxContainer.new()
	var validate_button := Button.new()
	validate_button.text = "فحص نموذج اللاعب"
	validate_button.pressed.connect(_validate_player_model)
	buttons.add_child(validate_button)

	var folder_button := Button.new()
	folder_button.text = "فتح مجلد النموذج"
	folder_button.pressed.connect(_open_player_asset_folder)
	buttons.add_child(folder_button)
	_panel.add_child(buttons)

	add_control_to_bottom_panel(_panel, "Ashen Assets")
	_show_missing_model_status()


func _exit_tree() -> void:
	if _panel != null:
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
	_panel = null
	_status_label = null


func _show_status(message: String, is_error: bool = false) -> void:
	if _status_label == null or not is_instance_valid(_status_label):
		return
	_status_label.text = message
	var color := Color(0.92, 0.72, 0.32, 1.0)
	if is_error:
		color = Color(1.0, 0.42, 0.38, 1.0)
	else:
		color = Color(0.55, 0.86, 0.62, 1.0)
	_status_label.add_theme_color_override("font_color", color)


func _show_missing_model_status() -> void:
	if not FileAccess.file_exists(PLAYER_MODEL_PATH):
		_show_status(
			"لم يُضف player.glb بعد. تعمل اللعبة بهيئة البطل المؤقتة. استخدم أداة Meshy المحلية لتوليد GLB ثم أعد الفحص."
		)
		return
	_show_status("عُثر على ملف player.glb. اضغط «فحص نموذج اللاعب» للتحقق من استيراده.")


func _validate_player_model() -> void:
	if not FileAccess.file_exists(PLAYER_MODEL_PATH):
		_show_status("الملف غير موجود: " + PLAYER_MODEL_PATH, true)
		return

	var model_resource := load(PLAYER_MODEL_PATH)
	var model_scene := model_resource as PackedScene
	if model_scene == null:
		_show_status("تعذر تحميل GLB كمشهد. افتح تبويب Import وأعد استيراد الملف.", true)
		return

	var instance := model_scene.instantiate()
	if instance == null:
		_show_status("تعذر إنشاء نسخة من النموذج المستورد.", true)
		return

	var mesh_nodes: Array = instance.find_children("*", "MeshInstance3D", true, false)
	var skeleton_nodes: Array = instance.find_children("*", "Skeleton3D", true, false)
	var animation_nodes: Array = instance.find_children("*", "AnimationPlayer", true, false)
	var animation_count := 0
	if not animation_nodes.is_empty():
		var animation_player := animation_nodes[0] as AnimationPlayer
		if animation_player != null:
			animation_count = animation_player.get_animation_list().size()
	instance.free()

	if mesh_nodes.is_empty():
		_show_status("تم تحميل المشهد، لكن لم يُعثر على MeshInstance3D؛ تحقق من ملف GLB.", true)
		return

	var summary := "نجح الاستيراد. الشبكات: %d | الهياكل العظمية: %d | مشغلات الأنيميشن: %d | المقاطع في أول مشغل: %d" % [
		mesh_nodes.size(), skeleton_nodes.size(), animation_nodes.size(), animation_count
	]
	if skeleton_nodes.is_empty():
		summary += "\nتنبيه: لا يوجد Skeleton3D؛ قد تحتاج إلى تجهيز الهيكل والتحريك لاحقًا."
	if animation_count == 0:
		summary += "\nتنبيه: لا توجد مقاطع أنيميشن مكتشفة؛ ستبقى الحركة مرئية دون تحريك عظمي."
	_show_status(summary)
	print("[Ashen Asset Bridge] ", summary)


func _open_player_asset_folder() -> void:
	var absolute_path := ProjectSettings.globalize_path(PLAYER_ASSET_DIRECTORY)
	var error := DirAccess.open(PLAYER_ASSET_DIRECTORY)
	if error == null:
		DirAccess.make_dir_recursive_absolute(absolute_path)
	OS.shell_open(absolute_path)
