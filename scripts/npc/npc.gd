class_name NPC
extends CharacterBody3D

@export var display_name: String = "غريب"
@export var dialogue_graph: DialogueGraph

@onready var talk_zone: Area3D = $TalkZone
@onready var prompt: Label3D = $Prompt


func _ready() -> void:
	add_to_group("npc")
	prompt.visible = false
	prompt.text = "E — تحدّث مع %s" % display_name
	prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	prompt.no_depth_test = true


func interact() -> void:
	if dialogue_graph == null:
		push_warning("NPC '%s' has no dialogue_graph." % name)
		return
	var manager := get_node_or_null("/root/DialogueManager")
	if manager == null:
		push_warning("DialogueManager Autoload is missing.")
		return
	if not manager.call("is_active"):
		manager.call("start", dialogue_graph)


func set_prompt_visible(value: bool) -> void:
	if is_instance_valid(prompt):
		prompt.visible = value
