extends CharacterBody3D

const WALK_SPEED: float = 5.0
const TURN_SPEED: float = 10.0
const CAMERA_SENSITIVITY: float = 0.006
const TOUCH_BUTTON_SIZE: Vector2 = Vector2(64.0, 64.0)

var gravity: float = 9.8
var _camera_yaw: float = 0.0
var _camera_pitch: float = 0.0
var _camera_touch_index: int = -1
var _camera_dragging: bool = false
var _touch_pressed: Dictionary = {}
var _touch_buttons: Dictionary = {}
var _camera_pivot: Node3D
var _hud_root: Control


func _ready() -> void:
    _configure_input_actions()
    gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
    _create_character_mesh()
    _create_camera_rig()
    _create_touch_hud()


func _physics_process(delta: float) -> void:
    var move_input := Input.get_vector(
        "move_left",
        "move_right",
        "move_forward",
        "move_back"
    )

    var touch_input := Vector2.ZERO
    if bool(_touch_pressed.get("left", false)):
        touch_input.x -= 1.0
    if bool(_touch_pressed.get("right", false)):
        touch_input.x += 1.0
    if bool(_touch_pressed.get("forward", false)):
        touch_input.y -= 1.0
    if bool(_touch_pressed.get("back", false)):
        touch_input.y += 1.0

    move_input = (move_input + touch_input).limit_length(1.0)
    var move_direction := Vector3(move_input.x, 0.0, move_input.y)
    move_direction = move_direction.rotated(Vector3.UP, _camera_yaw)

    if move_direction.length_squared() > 0.001:
        velocity.x = move_direction.x * WALK_SPEED
        velocity.z = move_direction.z * WALK_SPEED
        var target_yaw := atan2(-move_direction.x, -move_direction.z)
        rotation.y = lerp_angle(rotation.y, target_yaw, clampf(TURN_SPEED * delta, 0.0, 1.0))
    else:
        velocity.x = move_toward(velocity.x, 0.0, WALK_SPEED * 7.0 * delta)
        velocity.z = move_toward(velocity.z, 0.0, WALK_SPEED * 7.0 * delta)

    if is_on_floor():
        if velocity.y < 0.0:
            velocity.y = 0.0
    else:
        velocity.y -= gravity * delta

    if _camera_pivot != null:
        _camera_pivot.rotation.y = wrapf(_camera_yaw - rotation.y, -PI, PI)
    move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
    var viewport_width: float = get_viewport().get_visible_rect().size.x

    if event is InputEventScreenTouch:
        var touch_event := event as InputEventScreenTouch
        if touch_event.pressed and touch_event.position.x >= viewport_width * 0.42:
            _camera_touch_index = touch_event.index
            _camera_dragging = true
        elif not touch_event.pressed and touch_event.index == _camera_touch_index:
            _camera_touch_index = -1
            _camera_dragging = false
    elif event is InputEventScreenDrag:
        var drag_event := event as InputEventScreenDrag
        if _camera_dragging and drag_event.index == _camera_touch_index:
            _rotate_camera(drag_event.relative)
    elif event is InputEventMouseButton:
        var mouse_button := event as InputEventMouseButton
        if mouse_button.button_index == MOUSE_BUTTON_RIGHT:
            _camera_dragging = mouse_button.pressed
    elif event is InputEventMouseMotion and _camera_dragging:
        _rotate_camera((event as InputEventMouseMotion).relative)


func _rotate_camera(relative_motion: Vector2) -> void:
    _camera_yaw = wrapf(_camera_yaw - relative_motion.x * CAMERA_SENSITIVITY, -PI, PI)
    _camera_pitch = clampf(
        _camera_pitch - relative_motion.y * CAMERA_SENSITIVITY,
        deg_to_rad(-22.0),
        deg_to_rad(28.0)
    )

    if _camera_pivot != null:
        _camera_pivot.rotation.x = _camera_pitch
        _camera_pivot.rotation.y = wrapf(_camera_yaw - rotation.y, -PI, PI)


func _configure_input_actions() -> void:
    _add_key_binding("move_left", KEY_A)
    _add_key_binding("move_left", KEY_LEFT)
    _add_key_binding("move_right", KEY_D)
    _add_key_binding("move_right", KEY_RIGHT)
    _add_key_binding("move_forward", KEY_W)
    _add_key_binding("move_forward", KEY_UP)
    _add_key_binding("move_back", KEY_S)
    _add_key_binding("move_back", KEY_DOWN)


func _add_key_binding(action: StringName, physical_code: int) -> void:
    if not InputMap.has_action(action):
        InputMap.add_action(action)

    var key_event := InputEventKey.new()
    key_event.physical_keycode = physical_code
    if not InputMap.action_has_event(action, key_event):
        InputMap.action_add_event(action, key_event)


func _create_character_mesh() -> void:
    var collision := CollisionShape3D.new()
    collision.name = "CharacterCollision"
    var capsule_shape := CapsuleShape3D.new()
    capsule_shape.radius = 0.42
    capsule_shape.height = 1.75
    collision.shape = capsule_shape
    collision.position.y = 0.875
    add_child(collision)

    var character_mesh := MeshInstance3D.new()
    character_mesh.name = "CharacterVisual"
    var capsule_mesh := CapsuleMesh.new()
    capsule_mesh.radius = 0.42
    capsule_mesh.height = 1.75
    character_mesh.mesh = capsule_mesh
    character_mesh.position.y = 0.875

    var character_material := StandardMaterial3D.new()
    character_material.albedo_color = Color(0.55, 0.30, 0.17, 1.0)
    character_material.metallic = 0.08
    character_material.roughness = 0.72
    character_mesh.material_override = character_material
    add_child(character_mesh)


func _create_camera_rig() -> void:
    _camera_pivot = Node3D.new()
    _camera_pivot.name = "CameraPivot"
    _camera_pivot.position = Vector3(0.0, 1.2, 0.0)
    _camera_pivot.rotation = Vector3(_camera_pitch, _camera_yaw - rotation.y, 0.0)
    add_child(_camera_pivot)

    var camera := Camera3D.new()
    camera.name = "ThirdPersonCamera"
    camera.position = Vector3(0.0, 2.5, 6.5)
    _camera_pivot.add_child(camera)
    camera.look_at(_camera_pivot.global_position, Vector3.UP)
    camera.current = true


func _create_touch_hud() -> void:
    var canvas := CanvasLayer.new()
    canvas.name = "TouchControls"
    canvas.layer = 10
    add_child(canvas)

    _hud_root = Control.new()
    _hud_root.name = "HUD"
    _hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.add_child(_hud_root)

    var instructions := Label.new()
    instructions.name = "ControlInstructions"
    instructions.text = "WASD / Arrows: move\nDrag / Right mouse: rotate camera"
    instructions.position = Vector2(18.0, 14.0)
    instructions.add_theme_font_size_override("font_size", 16)
    instructions.add_theme_color_override("font_color", Color(0.9, 0.9, 0.86, 0.95))
    instructions.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _hud_root.add_child(instructions)

    _add_touch_button("forward", "▲")
    _add_touch_button("left", "◀")
    _add_touch_button("right", "▶")
    _add_touch_button("back", "▼")
    _layout_touch_buttons()


func _add_touch_button(action: StringName, caption: String) -> void:
    var button := Button.new()
    button.name = "Move_" + String(action)
    button.text = caption
    button.custom_minimum_size = TOUCH_BUTTON_SIZE
    button.focus_mode = Control.FOCUS_NONE
    button.add_theme_font_size_override("font_size", 26)
    button.add_theme_color_override("font_color", Color(0.95, 0.94, 0.88, 1.0))
    button.add_theme_stylebox_override("normal", _button_style(Color(0.06, 0.07, 0.09, 0.72)))
    button.add_theme_stylebox_override("hover", _button_style(Color(0.13, 0.15, 0.18, 0.88)))
    button.add_theme_stylebox_override("pressed", _button_style(Color(0.35, 0.22, 0.14, 0.92)))
    _hud_root.add_child(button)
    button.button_down.connect(_set_touch_action.bind(action, true))
    button.button_up.connect(_set_touch_action.bind(action, false))
    _touch_buttons[action] = button


func _button_style(background: Color) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = background
    style.border_color = Color(0.68, 0.55, 0.39, 0.72)
    style.border_width_left = 1
    style.border_width_top = 1
    style.border_width_right = 1
    style.border_width_bottom = 1
    style.corner_radius_top_left = 14
    style.corner_radius_top_right = 14
    style.corner_radius_bottom_left = 14
    style.corner_radius_bottom_right = 14
    return style


func _set_touch_action(action: StringName, pressed: bool) -> void:
    _touch_pressed[action] = pressed


func _layout_touch_buttons() -> void:
    var view_size: Vector2 = get_viewport().get_visible_rect().size
    var button_positions: Dictionary = {
        "forward": Vector2(90.0, view_size.y - 212.0),
        "left": Vector2(18.0, view_size.y - 140.0),
        "right": Vector2(162.0, view_size.y - 140.0),
        "back": Vector2(90.0, view_size.y - 68.0)
    }

    for action in button_positions:
        var button: Button = _touch_buttons[action]
        button.position = button_positions[action]
