extends Node

signal dialogue_started
signal dialogue_line_shown(node: DialogueNode, choices: Array)
signal dialogue_ended
signal quest_start_requested(quest_id: StringName)

var flags: Dictionary = {}
var _graph: DialogueGraph
var _current: DialogueNode
var _player: Node
var _progression: Node
var _quest_manager: Node


func configure_context(player: Node, progression: Node, quest_manager: Node) -> void:
	_player = player
	_progression = progression
	_quest_manager = quest_manager


func start(graph: DialogueGraph) -> bool:
	if is_active() or graph == null:
		return false
	var entry := graph.get_node_by_id(graph.entry_node_id)
	if entry == null:
		push_warning("DialogueGraph entry node '%s' was not found." % graph.entry_node_id)
		return false

	_graph = graph
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	dialogue_started.emit()
	_show_node(entry)
	return is_active()


func next() -> void:
	if _current == null or _graph == null:
		return
	if _current.next_id == &"":
		finish()
		return

	var next_node := _graph.get_node_by_id(_current.next_id)
	if next_node == null:
		push_warning("DialogueGraph node '%s' was not found." % _current.next_id)
		finish()
		return
	_show_node(next_node)


func choose(index: int) -> void:
	if _current == null or _graph == null:
		return
	var available := _visible_choices(_current)
	if index < 0 or index >= available.size():
		return

	var choice: DialogueChoice = available[index]
	_apply_effects(choice)
	if choice.target_node_id == &"":
		finish()
		return

	var target := _graph.get_node_by_id(choice.target_node_id)
	if target == null:
		push_warning("Dialogue choice target '%s' was not found." % choice.target_node_id)
		finish()
		return
	_show_node(target)


func finish() -> void:
	if _graph == null and _current == null:
		return
	_graph = null
	_current = null
	dialogue_ended.emit()


func is_active() -> bool:
	return _graph != null


func set_flag(flag_name: StringName, value: bool = true) -> void:
	flags[flag_name] = value


func get_flag(flag_name: StringName) -> bool:
	return bool(flags.get(flag_name, false))


func _show_node(node: DialogueNode) -> void:
	if _graph == null:
		return

	# Follow conditional nodes that are unavailable, with a hard limit to
	# prevent malformed cyclic graphs from locking the game.
	var candidate := node
	var attempts := 0
	while candidate != null and not _check_conditions(candidate):
		attempts += 1
		if attempts > _graph.nodes.size() or candidate.next_id == &"":
			finish()
			return
		candidate = _graph.get_node_by_id(candidate.next_id)

	if candidate == null:
		finish()
		return

	_current = candidate
	_apply_effects(candidate)
	dialogue_line_shown.emit(candidate, _visible_choices(candidate))


func _visible_choices(node: DialogueNode) -> Array:
	var visible: Array = []
	for choice in node.choices:
		if choice != null and _check_conditions(choice):
			visible.append(choice)
	return visible


func _check_conditions(action: DialogueAction) -> bool:
	for flag_name in action.required_flags:
		if not get_flag(flag_name):
			return false
	for flag_name in action.forbidden_flags:
		if get_flag(flag_name):
			return false

	if action.min_level > 1:
		if not is_instance_valid(_progression):
			return false
		if int(_progression.get("level")) < action.min_level:
			return false

	if action.required_item_id != &"":
		if not is_instance_valid(_player):
			_player = get_tree().get_first_node_in_group("player")
		if not is_instance_valid(_player):
			return false
		var inventory := _player.get_node_or_null("Inventory")
		if inventory == null or not inventory.has_method("has_item"):
			return false
		if not bool(inventory.call("has_item", action.required_item_id, action.required_item_count)):
			return false

	return true


# All gameplay mutations from dialogue pass through this single function.
# In multiplayer, this is the intended seam for a validated server RPC.
func _apply_effects(action: DialogueAction) -> void:
	for flag_name in action.set_flags:
		set_flag(flag_name, true)

	if action.give_xp > 0:
		if is_instance_valid(_progression):
			_progression.call("add_experience", action.give_xp)
		else:
			push_warning("Dialogue attempted to grant XP without a progression manager.")

	if not action.give_items.is_empty():
		if not is_instance_valid(_player):
			_player = get_tree().get_first_node_in_group("player")
		var inventory := _player.get_node_or_null("Inventory") if is_instance_valid(_player) else null
		if inventory == null or not inventory.has_method("add_item"):
			push_warning("Dialogue attempted to grant items without a player inventory.")
		else:
			for item in action.give_items:
				if item != null:
					var remainder: int = int(inventory.call("add_item", item, 1))
					if remainder > 0:
						push_warning("Inventory is full; could not grant all of '%s'." % item.display_name)

	if action.start_quest_id != &"":
		quest_start_requested.emit(action.start_quest_id)


func serialize() -> Dictionary:
	var serialized_flags: Dictionary = {}
	for flag_name in flags:
		serialized_flags[String(flag_name)] = bool(flags[flag_name])
	return {"flags": serialized_flags}


func deserialize(data: Dictionary) -> void:
	flags.clear()
	var raw_flags = data.get("flags", {})
	if not (raw_flags is Dictionary):
		return
	for flag_name in raw_flags:
		flags[StringName(str(flag_name))] = bool(raw_flags[flag_name])
