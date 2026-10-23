extends Node3D
class_name WorldInteractable

signal interacted(interaction_id: StringName)

var interaction_id: StringName = &""
var region_id: StringName = &""
var display_name := "معلم"
var interaction_message := ""
var interaction_radius := 3.2

var _prompt: Label3D


func _ready() -> void:
	add_to_group("world_interactable")
	_build_interaction_zone()
	_build_prompt()


func interact() -> void:
	interacted.emit(interaction_id)
	var first_discovery := false
	var journal := get_tree().get_first_node_in_group("world_journal")
	if is_instance_valid(journal) and journal.has_method("discover_landmark"):
		first_discovery = bool(journal.call("discover_landmark", region_id, interaction_id))
	var message := interaction_message
	if first_discovery:
		message = "اكتشاف جديد: %s — %s" % [display_name, interaction_message]
	if message.is_empty():
		return
	var hud := get_tree().get_first_node_in_group("game_hud")
	if is_instance_valid(hud) and hud.has_method("show_message"):
		hud.call("show_message", message)


func set_prompt_visible(value: bool) -> void:
	if is_instance_valid(_prompt):
		_prompt.visible = value


func get_interaction_button_text() -> String:
	return "افحص"


func _build_interaction_zone() -> void:
	var zone := Area3D.new()
	zone.name = "InteractionZone"
	zone.collision_layer = 4
	zone.collision_mask = 0
	zone.monitoring = false
	zone.monitorable = true

	var collision_node := CollisionShape3D.new()
	collision_node.name = "CollisionShape3D"
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(interaction_radius, 0.5)
	collision_node.shape = sphere
	zone.add_child(collision_node)
	add_child(zone)


func _build_prompt() -> void:
	_prompt = Label3D.new()
	_prompt.name = "InteractionPrompt"
	_prompt.position = Vector3(0.0, 2.35, 0.0)
	_prompt.text = "E — افحص %s" % display_name
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.pixel_size = 0.01
	_prompt.visible = false
	add_child(_prompt)
