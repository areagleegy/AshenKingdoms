extends RefCounted

# Shared startup input map for the main menu, single-player scene and network arena.
# Standard Joypad A/B/X/Y map to Cross/Circle/Square/Triangle on common controller drivers.
static func register_input_actions() -> void:
	_add_key_action(&"move_forward", [KEY_W, KEY_UP])
	_add_key_action(&"move_back", [KEY_S, KEY_DOWN])
	_add_key_action(&"move_left", [KEY_A, KEY_LEFT])
	_add_key_action(&"move_right", [KEY_D, KEY_RIGHT])
	_add_key_action(&"jump", [KEY_SPACE])
	_add_key_action(&"sprint", [KEY_SHIFT])
	_add_key_action(&"inventory", [KEY_I, KEY_TAB])
	_add_key_action(&"pause", [KEY_ESCAPE])
	_add_key_action(&"save", [KEY_F5])
	_add_key_action(&"load", [KEY_F9])
	_add_key_action(&"interact", [KEY_E, KEY_ENTER])

	# Left stick: movement. Right stick: camera look.
	_add_joy_axis_action(&"move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis_action(&"move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_axis_action(&"move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis_action(&"move_back", JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_axis_action(&"look_left", JOY_AXIS_RIGHT_X, -1.0)
	_add_joy_axis_action(&"look_right", JOY_AXIS_RIGHT_X, 1.0)
	_add_joy_axis_action(&"look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_add_joy_axis_action(&"look_down", JOY_AXIS_RIGHT_Y, 1.0)

	# Conventional face-button and menu layout.
	_add_joy_button_action(&"jump", JOY_BUTTON_A)
	_add_joy_button_action(&"interact", JOY_BUTTON_B)
	_add_joy_button_action(&"attack", JOY_BUTTON_X)
	_add_joy_button_action(&"inventory", JOY_BUTTON_Y)
	_add_joy_button_action(&"sprint", JOY_BUTTON_LEFT_STICK)
	_add_joy_button_action(&"pause", JOY_BUTTON_START)

	# Standard controller navigation for menus, dialogs, and focused buttons.
	_add_joy_button_action(&"ui_accept", JOY_BUTTON_A)
	_add_joy_button_action(&"ui_cancel", JOY_BUTTON_B)
	_add_joy_button_action(&"ui_up", JOY_BUTTON_DPAD_UP)
	_add_joy_button_action(&"ui_down", JOY_BUTTON_DPAD_DOWN)
	_add_joy_button_action(&"ui_left", JOY_BUTTON_DPAD_LEFT)
	_add_joy_button_action(&"ui_right", JOY_BUTTON_DPAD_RIGHT)

	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
	var attack_event := InputEventMouseButton.new()
	attack_event.button_index = MOUSE_BUTTON_LEFT
	if not InputMap.action_has_event("attack", attack_event):
		InputMap.action_add_event("attack", attack_event)


static func _add_key_action(action: StringName, key_codes: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key_code in key_codes:
		var key_event := InputEventKey.new()
		key_event.physical_keycode = int(key_code)
		if not InputMap.action_has_event(action, key_event):
			InputMap.action_add_event(action, key_event)


static func _add_joy_button_action(action: StringName, button_index: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var button_event := InputEventJoypadButton.new()
	button_event.button_index = button_index
	if not InputMap.action_has_event(action, button_event):
		InputMap.action_add_event(action, button_event)


static func _add_joy_axis_action(action: StringName, axis: int, axis_value: float) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var axis_event := InputEventJoypadMotion.new()
	axis_event.axis = axis
	axis_event.axis_value = axis_value
	if not InputMap.action_has_event(action, axis_event):
		InputMap.action_add_event(action, axis_event)
