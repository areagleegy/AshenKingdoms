extends Node3D

const SERVER_SCRIPT: Script = preload("res://scripts/core/server.gd")


func _ready() -> void:
    if _is_server_mode():
        var server_node := SERVER_SCRIPT.new()
        server_node.name = "ServerBootstrap"
        add_child(server_node)
        return

    _create_placeholder_world()
    print("AshenKingdoms prototype started.")


func _is_server_mode() -> bool:
    return (
        DisplayServer.get_name() == "headless"
        or OS.has_feature("dedicated_server")
        or "--server" in OS.get_cmdline_user_args()
    )


func _create_placeholder_world() -> void:
    var ground := MeshInstance3D.new()
    ground.name = "PlaceholderGround"
    var ground_mesh := PlaneMesh.new()
    ground_mesh.size = Vector2(60.0, 60.0)
    ground.mesh = ground_mesh
    ground.position.y = -0.55
    var ground_material := StandardMaterial3D.new()
    ground_material.albedo_color = Color(0.12, 0.15, 0.17)
    ground.material_override = ground_material
    add_child(ground)

    var marker := MeshInstance3D.new()
    marker.name = "PrototypePlayerMarker"
    var marker_mesh := BoxMesh.new()
    marker_mesh.size = Vector3(0.8, 1.8, 0.8)
    marker.mesh = marker_mesh
    marker.position.y = 0.45
    var marker_material := StandardMaterial3D.new()
    marker_material.albedo_color = Color(0.55, 0.32, 0.19)
    marker.material_override = marker_material
    add_child(marker)

    var sun := DirectionalLight3D.new()
    sun.name = "Sun"
    sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
    sun.light_energy = 1.2
    add_child(sun)

    var camera := Camera3D.new()
    camera.name = "PrototypeCamera"
    camera.position = Vector3(0.0, 5.5, 9.0)
    camera.look_at(Vector3(0.0, 0.3, 0.0), Vector3.UP)
    camera.current = true
    add_child(camera)
