class_name DialogueNode
extends DialogueAction

@export var id: StringName = &""
@export var speaker_name: String = ""
@export_multiline var text: String = ""
@export var next_id: StringName = &""
@export var choices: Array[DialogueChoice] = []
