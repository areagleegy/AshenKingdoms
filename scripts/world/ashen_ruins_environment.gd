extends Node3D

# Procedural, license-free first environment slice. Keep gameplay lanes clear:
# center combat area stays open; blockers live on the perimeter.
var _stone_dark: StandardMaterial3D
var _stone_mid: StandardMaterial3D
var _stone_light: StandardMaterial3D
var _ash_material: StandardMaterial3D
var _wood_dark: StandardMaterial3D
var _ember_material: StandardMaterial3D


func _ready() -> void:
	_build_materials()
	_build_entrance_arch()
	_build_perimeter_ruins()
	_build_ashen_monument()
	_build_ground_detail()
	_build_rubble_clusters()


func _build_materials() -> void:
	_stone_dark = _make_material(Color(0.105, 0.115, 0.135, 1.0), 0.96)
	_stone_mid = _make_material(Color(0.20, 0.215, 0.235, 1.0), 0.94)
	_stone_light = _make_material(Color(0.29, 0.30, 0.31, 1.0), 0.91)
	_ash_material = _make_material(Color(0.13, 0.14, 0.15, 1.0), 1.0)
	_wood_dark = _make_material(Color(0.105, 0.067, 0.048, 1.0), 0.98)
	_ember_material = _make_material(Color(0.72, 0.255, 0.065, 1.0), 0.8)
	_ember_material.emission_enabled = true
	_ember_material.emission = Color(0.8, 0.18, 0.035, 1.0)
	_ember_material.emission_energy_multiplier = 1.15


func _make_material(color: Color, surface_roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = surface_roughness
	return material


func _build_entrance_arch() -> void:
	var arch := Node3D.new()
	arch.name = "EntranceArch"
	arch.position = Vector3(0.0, 0.0, 18.0)
	add_child(arch)

	_add_column(arch, "PillarLeft", Vector3(-3.15, 0.0, 0.0), 0.56, 4.0, _stone_mid, true)
	_add_column(arch, "PillarRight", Vector3(3.15, 0.0, 0.0), 0.56, 4.0, _stone_mid, true)
	_add_box(arch, "LintelLeft", Vector3(-2.0, 4.0, 0.0), Vector3(2.9, 0.72, 1.12), Vector3(0.0, 0.0, -3.0), _stone_light, true)
	_add_box(arch, "LintelRight", Vector3(2.1, 4.0, 0.0), Vector3(2.25, 0.72, 1.12), Vector3(0.0, 0.0, 4.5), _stone_mid, true)
	_add_box(arch, "BrokenKeystone", Vector3(0.65, 4.25, 0.08), Vector3(1.1, 0.62, 1.0), Vector3(0.0, 0.0, -11.0), _stone_dark, true)

	_add_box(arch, "LeftBase", Vector3(-3.15, 0.24, 0.0), Vector3(1.45, 0.48, 1.42), Vector3.ZERO, _stone_dark, true)
	_add_box(arch, "RightBase", Vector3(3.15, 0.24, 0.0), Vector3(1.45, 0.48, 1.42), Vector3.ZERO, _stone_dark, true)

	_add_box(arch, "EmberBowlLeft", Vector3(-4.35, 0.78, 0.0), Vector3(0.8, 0.25, 0.8), Vector3.ZERO, _stone_dark, true)
	_add_box(arch, "EmberBowlRight", Vector3(4.35, 0.78, 0.0), Vector3(0.8, 0.25, 0.8), Vector3.ZERO, _stone_dark, true)
	_add_box(arch, "EmberLeft", Vector3(-4.35, 1.12, 0.0), Vector3(0.22, 0.55, 0.22), Vector3(0.0, 0.0, 8.0), _ember_material, false)
	_add_box(arch, "EmberRight", Vector3(4.35, 1.12, 0.0), Vector3(0.22, 0.55, 0.22), Vector3(0.0, 0.0, -6.0), _ember_material, false)


func _build_perimeter_ruins() -> void:
	var perimeter := Node3D.new()
	perimeter.name = "PerimeterRuins"
	add_child(perimeter)

	# Low broken side walls frame the combat space without blocking the center.
	_add_box(perimeter, "WestWallSouth", Vector3(-16.0, 1.0, 4.0), Vector3(0.85, 2.0, 8.0), Vector3(0.0, 0.0, 1.5), _stone_dark, true)
	_add_box(perimeter, "WestWallNorth", Vector3(-16.0, 0.8, -7.0), Vector3(0.85, 1.6, 5.0), Vector3(0.0, 0.0, -2.0), _stone_mid, true)
	_add_box(perimeter, "EastWallSouth", Vector3(16.0, 0.9, 4.5), Vector3(0.85, 1.8, 7.0), Vector3(0.0, 0.0, -1.0), _stone_dark, true)
	_add_box(perimeter, "EastWallNorth", Vector3(16.0, 1.1, -7.2), Vector3(0.85, 2.2, 4.5), Vector3(0.0, 0.0, 2.0), _stone_mid, true)

	_add_box(perimeter, "NorthWallWest", Vector3(-10.5, 0.85, -15.5), Vector3(5.0, 1.7, 0.85), Vector3(0.0, 0.0, -1.5), _stone_mid, true)
	_add_box(perimeter, "NorthWallEast", Vector3(10.5, 0.65, -15.5), Vector3(4.5, 1.3, 0.85), Vector3(0.0, 0.0, 2.5), _stone_dark, true)
	_add_box(perimeter, "SouthWallWest", Vector3(-9.0, 0.65, 14.0), Vector3(4.0, 1.3, 0.85), Vector3(0.0, 0.0, -2.5), _stone_dark, true)
	_add_box(perimeter, "SouthWallEast", Vector3(9.0, 0.9, 14.0), Vector3(4.0, 1.8, 0.85), Vector3(0.0, 0.0, 2.0), _stone_mid, true)

	_add_column(perimeter, "WestSentinel", Vector3(-12.6, 0.0, -12.0), 0.44, 2.9, _stone_light, true)
	_add_column(perimeter, "EastSentinel", Vector3(12.6, 0.0, -12.0), 0.44, 2.9, _stone_light, true)
	_add_column(perimeter, "WestBrokenColumn", Vector3(-13.4, 0.0, 8.5), 0.48, 2.1, _stone_mid, true)
	_add_column(perimeter, "EastBrokenColumn", Vector3(13.4, 0.0, 8.5), 0.48, 2.5, _stone_mid, true)

	_add_box(perimeter, "WestCapStone", Vector3(-16.0, 2.0, -9.2), Vector3(1.4, 0.32, 2.0), Vector3(0.0, 0.0, 6.0), _stone_light, true)
	_add_box(perimeter, "EastCapStone", Vector3(16.0, 1.8, 1.4), Vector3(1.6, 0.34, 2.2), Vector3(0.0, 0.0, -8.0), _stone_light, true)


func _build_ashen_monument() -> void:
	var monument := Node3D.new()
	monument.name = "AshenMonument"
	monument.position = Vector3(0.0, 0.0, -20.0)
	add_child(monument)

	_add_box(monument, "LowerPlinth", Vector3(0.0, 0.22, 0.0), Vector3(3.8, 0.44, 2.6), Vector3.ZERO, _stone_dark, true)
	_add_box(monument, "UpperPlinth", Vector3(0.0, 0.56, 0.0), Vector3(2.7, 0.28, 1.8), Vector3(0.0, 0.0, 2.0), _stone_mid, true)
	_add_column(monument, "Obelisk", Vector3(0.0, 2.2, 0.0), 0.64, 3.2, _stone_light, true)
	_add_box(monument, "ObeliskCrown", Vector3(0.0, 4.0, 0.0), Vector3(1.1, 0.68, 1.05), Vector3(0.0, 10.0, 5.0), _stone_dark, true)
	_add_box(monument, "CrackedCrown", Vector3(0.55, 4.25, 0.08), Vector3(0.55, 0.48, 0.62), Vector3(0.0, 0.0, -13.0), _stone_mid, true)


func _build_ground_detail() -> void:
	var ground_marks := MultiMeshInstance3D.new()
	ground_marks.name = "AshenPathMarks"
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var tile_mesh := BoxMesh.new()
	tile_mesh.size = Vector3(1.7, 0.025, 0.78)
	multimesh.mesh = tile_mesh

	var marks: Array[Dictionary] = [
		{"position": Vector3(0.0, 0.012, 4.5), "rotation": 0.0},
		{"position": Vector3(0.0, 0.012, 6.0), "rotation": -4.0},
		{"position": Vector3(0.0, 0.012, 7.4), "rotation": 3.0},
		{"position": Vector3(0.0, 0.012, 8.8), "rotation": -2.0},
		{"position": Vector3(0.0, 0.012, 10.2), "rotation": 3.5},
		{"position": Vector3(0.0, 0.012, 11.6), "rotation": -3.0},
		{"position": Vector3(0.0, 0.012, 13.0), "rotation": 1.5},
		{"position": Vector3(-7.5, 0.012, -11.0), "rotation": -18.0},
		{"position": Vector3(-6.0, 0.012, -12.4), "rotation": 22.0},
		{"position": Vector3(7.0, 0.012, -11.0), "rotation": 15.0},
		{"position": Vector3(8.0, 0.012, -9.3), "rotation": -28.0},
		{"position": Vector3(-10.0, 0.012, 5.2), "rotation": 32.0},
		{"position": Vector3(10.5, 0.012, 6.0), "rotation": -24.0},
		{"position": Vector3(0.0, 0.012, -16.3), "rotation": 0.0}
	]
	multimesh.instance_count = marks.size()
	for index in range(marks.size()):
		var mark: Dictionary = marks[index]
		var rotation := Vector3(0.0, deg_to_rad(float(mark["rotation"])), 0.0)
		multimesh.set_instance_transform(index, Transform3D(Basis.from_euler(rotation), mark["position"]))
	ground_marks.multimesh = multimesh
	ground_marks.material_override = _stone_mid
	add_child(ground_marks)

	_add_ash_patch(Vector3(-10.0, 0.0, -2.0), Vector3(3.8, 0.035, 2.6))
	_add_ash_patch(Vector3(10.0, 0.0, 1.0), Vector3(3.2, 0.03, 3.4))
	_add_ash_patch(Vector3(-8.0, 0.0, 10.5), Vector3(2.5, 0.025, 2.0))
	_add_ash_patch(Vector3(8.5, 0.0, -13.5), Vector3(2.7, 0.03, 2.0))


func _add_ash_patch(position: Vector3, size: Vector3) -> void:
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "AshPatch"
	var mesh := SphereMesh.new()
	mesh.radial_segments = 8
	mesh.rings = 3
	mesh.radius = 1.0
	mesh.height = 0.12
	mesh_node.mesh = mesh
	mesh_node.position = position + Vector3(0.0, 0.015, 0.0)
	mesh_node.scale = size
	mesh_node.material_override = _ash_material
	add_child(mesh_node)


func _build_rubble_clusters() -> void:
	var rubble := Node3D.new()
	rubble.name = "RubbleClusters"
	add_child(rubble)

	_add_box(rubble, "RubbleNorthWestA", Vector3(-20.5, 0.34, -12.0), Vector3(1.5, 0.68, 1.2), Vector3(9.0, 17.0, -8.0), _stone_mid, true)
	_add_box(rubble, "RubbleNorthWestB", Vector3(-19.2, 0.24, -11.2), Vector3(1.1, 0.48, 0.85), Vector3(-8.0, -12.0, 17.0), _stone_dark, true)
	_add_box(rubble, "RubbleNorthEastA", Vector3(20.0, 0.3, -11.5), Vector3(1.4, 0.6, 1.25), Vector3(5.0, 24.0, 11.0), _stone_light, true)
	_add_box(rubble, "RubbleNorthEastB", Vector3(19.0, 0.18, -12.6), Vector3(1.05, 0.36, 0.95), Vector3(-12.0, 9.0, -4.0), _stone_dark, true)
	_add_box(rubble, "RubbleSouthWestA", Vector3(-20.0, 0.27, 12.4), Vector3(1.3, 0.54, 1.15), Vector3(4.0, -18.0, 11.0), _stone_mid, true)
	_add_box(rubble, "RubbleSouthEastA", Vector3(20.6, 0.35, 11.3), Vector3(1.6, 0.7, 1.2), Vector3(-7.0, 14.0, -13.0), _stone_light, true)


func _add_column(
	parent: Node3D,
	column_name: String,
	local_position: Vector3,
	radius: float,
	height: float,
	material: Material,
	collidable: bool
) -> Node3D:
	var body: Node3D = StaticBody3D.new() if collidable else Node3D.new()
	body.name = column_name
	body.position = local_position
	parent.add_child(body)

	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.82
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	visual.mesh = mesh
	visual.material_override = material
	visual.position.y = height * 0.5
	body.add_child(visual)

	if collidable:
		var collision := CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		collision.shape = shape
		collision.position.y = height * 0.5
		body.add_child(collision)
	return body


func _add_box(
	parent: Node3D,
	box_name: String,
	local_position: Vector3,
	size: Vector3,
	rotation_degrees: Vector3,
	material: Material,
	collidable: bool
) -> Node3D:
	var body: Node3D = StaticBody3D.new() if collidable else Node3D.new()
	body.name = box_name
	body.position = local_position
	body.rotation_degrees = rotation_degrees
	parent.add_child(body)

	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = material
	body.add_child(visual)

	if collidable:
		var collision := CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
	return body
