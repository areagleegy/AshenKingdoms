extends Node3D

const SERVER_SCRIPT: Script = preload("res://scripts/core/server.gd")
const PLAYER_SCRIPT: Script = preload("res://scripts/player/player_controller.gd")


func _ready() -> void:
    if _is_server_mode():
        var server_node: Node = SERVER_SCRIPT.new()
        server_node.name = "ServerBootstrap"
        add_child(server_node)
        return

    _create_world()
    _create_player()
    print("AshenKingdoms movement prototype started.")


func _is_server_mode() -> bool:
    return (
        DisplayServer.get_name() == "headless"
        or OS.has_feature("dedicated_server")
        or "--server" in OS.get_cmdline_user_args()
    )


func _create_world() -> void:
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.035, 0.035, 0.055, 1.0)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.52, 0.55, 0.62, 1.0)
    environment.ambient_light_energy = 0.55

    var world_environment := WorldEnvironment.new()
    world_environment.name = "WorldEnvironment"
    world_environment.environment = environment
    add_child(world_environment)

    var ground_body := StaticBody3D.new()
    ground_body.name = "Ground"
    ground_body.position.y = -0.5

    var ground_collision := CollisionShape3D.new()
    var ground_shape := BoxShape3D.new()
    ground_shape.size = Vector3(60.0, 1.0, 60.0)
    ground_collision.shape = ground_shape
    ground_body.add_child(ground_collision)

    var ground_visual := MeshInstance3D.new()
    ground_visual.name = "GroundVisual"
    var ground_mesh := PlaneMesh.new()
    ground_mesh.size = Vector2(60.0, 60.0)
    ground_visual.mesh = ground_mesh
    ground_visual.position.y = 0.5

    var ground_material := StandardMaterial3D.new()
    ground_material.albedo_color = Color(0.12, 0.15, 0.17, 1.0)
    ground_material.roughness = 0.92
    ground_visual.material_override = ground_material
    ground_body.add_child(ground_visual)
    add_child(ground_body)

    var sun := DirectionalLight3D.new()
    sun.name = "Sun"
    sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
    sun.light_energy = 1.2
    add_child(sun)


func _create_player() -> void:
    var player := CharacterBody3D.new()
    player.name = "Player"
    player.position = Vector3(0.0, 0.05, 0.0)
    player.set_script(PLAYER_SCRIPT)
    add_child(player)
