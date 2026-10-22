extends CanvasLayer

@onready var panel: PanelContainer = $Panel
@onready var name_label: Label = %SpeakerLabel
@onready var text_label: RichTextLabel = %DialogueText
@onready var choices_box: VBoxContainer = %ChoicesBox
@onready var continue_hint: Label = %ContinueHint
@onready var continue_button: Button = %ContinueButton

const CHAR_TIME: float = 0.025

var _current_choices: Array = []
var _is_typing: bool = false
var _line_ready: bool = false
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel.visible = false
	continue_button.visible = false
	continue_button.pressed.connect(_advance)
	var manager := get_node_or_null("/root/DialogueManager")
	if manager != null:
		manager.connect("dialogue_started", _on_started)
		manager.connect("dialogue_line_shown", _on_line)
		manager.connect("dialogue_ended", _on_ended)


func _on_started() -> void:
	panel.visible = true
	get_tree().paused = true
	_set_mouse_visible(true)


func _on_ended() -> void:
	_clear_dialogue_focus()
	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = null
	panel.visible = false
	_is_typing = false
	_line_ready = false
	_current_choices.clear()
	_clear_choices()
	get_tree().paused = false
	_set_mouse_visible(false)


func _on_line(node: DialogueNode, choices: Array) -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = null
	_clear_choices()
	_current_choices = choices
	_line_ready = false
	_is_typing = true

	name_label.text = node.speaker_name if not node.speaker_name.is_empty() else "؟"
	text_label.text = node.text
	text_label.visible_ratio = 0.0
	continue_hint.visible = false
	continue_button.visible = false

	_tween = create_tween()
	var duration := maxf(float(node.text.length()) * CHAR_TIME, 0.05)
	_tween.tween_property(text_label, "visible_ratio", 1.0, duration)
	_tween.finished.connect(_on_typing_finished)


func _on_typing_finished() -> void:
	if _line_ready:
		return
	_line_ready = true
	_is_typing = false
	if _current_choices.is_empty():
		continue_hint.visible = true
		continue_button.visible = true
		call_deferred("_focus_continue_button")
		return

	continue_hint.visible = false
	continue_button.visible = false
	for index in range(_current_choices.size()):
		var choice := _current_choices[index] as DialogueChoice
		if choice == null:
			continue
		var button := Button.new()
		button.text = "%d. %s" % [index + 1, choice.text]
		button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(_on_choice.bind(index))
		choices_box.add_child(button)
	call_deferred("_focus_first_choice")


func _focus_continue_button() -> void:
	if panel.visible and continue_button.visible:
		continue_button.grab_focus()


func _focus_first_choice() -> void:
	if not panel.visible:
		return
	for child in choices_box.get_children():
		if child is Button and not child.is_queued_for_deletion() and child.is_visible_in_tree():
			(child as Button).grab_focus()
			return
	_focus_continue_button()


func _clear_dialogue_focus() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and panel.is_ancestor_of(focused):
		focused.release_focus()


func _on_choice(index: int) -> void:
	if _is_typing or index < 0 or index >= _current_choices.size():
		return
	var manager := get_node_or_null("/root/DialogueManager")
	if manager != null:
		manager.call("choose", index)


func _advance() -> void:
	if not panel.visible:
		return
	if _is_typing:
		_reveal_line()
	elif _current_choices.is_empty():
		var manager := get_node_or_null("/root/DialogueManager")
		if manager != null:
			manager.call("next")


func _reveal_line() -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	text_label.visible_ratio = 1.0
	_on_typing_finished()


func _clear_choices() -> void:
	for child in choices_box.get_children():
		child.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if not panel.visible:
		return

	# Do not allow the pause menu or inventory overlay to open behind dialogue.
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		_advance()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and not _is_typing:
			if key_event.keycode >= KEY_1 and key_event.keycode <= KEY_9:
				var index := key_event.keycode - KEY_1
				if index < _current_choices.size():
					_on_choice(index)
					get_viewport().set_input_as_handled()


func _set_mouse_visible(show_mouse: bool) -> void:
	if OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"):
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if show_mouse else Input.MOUSE_MODE_CAPTURED
