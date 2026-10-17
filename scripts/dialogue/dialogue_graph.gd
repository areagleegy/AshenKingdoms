class_name DialogueGraph
extends Resource

@export var entry_node_id: StringName = &"start"
@export var nodes: Array[DialogueNode] = []


func get_node_by_id(node_id: StringName) -> DialogueNode:
	for dialogue_node in nodes:
		if dialogue_node != null and dialogue_node.id == node_id:
			return dialogue_node
	return null
