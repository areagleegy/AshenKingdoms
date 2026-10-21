extends Node3D
## Small, deterministic environment dressing for the Ashen Ruins vertical slice.
## Uses only built-in Godot meshes/materials so it stays offline and dependency-free.

const PATH_STONE_COUNT: int = 9
const RUBBLE_COUNT: int = 36

var _stone_material: StandardMaterial3D
var _weathered_material: StandardMaterial3D
var _dark_material: StandardMaterial3D
var _bronze_material: StandardMaterial3D
var _path_materials: Array[StandardMaterial3D] = []


func _ready() -> void:
	_stone_material = _make_material(Color(0.19, 0.205, 0.22, 1.0))
	_weathered_material = _make_material(Color(0.255, 0.245, 0.215, 1.0))
	_dark_material = _make_material(Color(0.085, 0.095, 0.105, 1.0))
	_bronze_material = _make_material(Color(0.37, 0.245, 0.105, 1.0), 0.72)
	_path_materials = [
		_stone_material,
		_make_material(Color(0.225, 0.225, 0.22, 1.0)),
		_weathered_material
	]
	_build_path_stones()
	_build_ruin_pillars()
	_build_broken_gate()
	_build_rubble()


func _make_material(color: Color, roughness: float = 0.96) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = 0.0
	return material


func _build_path_stones() -> void:
	var path := Node3D.new()
	path.name = "PathStones"
	add_child(path)
	for index in range(PATH_STONE_COUNT):
		var tile := MeshInstance3D.new()
		tile.name = "PathStone_%02d" % index
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.18, 0.085, 1.28)
		tile.mesh = mesh
		var lateral_offset := sin(float(index) * 1.31) * 0.22
		tile.position = Vector3(lateral_offset, 0.025, -2.0 - float(index) * 1.52)
		tile.rotation_degrees.y = sin(float(index) * 0.83) * 5.0
		tile.material_override = _path_materials[index % _path_materials.size()]
		path.add_child(tile)


func _build_ruin_pillars() -> void:
	var ruins := Node3D.new()
	ruins.name = "RuinPillars"
	add_child(ruins)
	var positions: Array[Vector3] = [
		Vector3(-8.5, 0.0, -3.5),
		Vector3(8.5, 0.0, -3.5),
		Vector3(-10.0, 0.0, -9.5),
		Vector3(10.0, 0.0, -9.5),
		Vector3(-8.5, 0.0, -18.5),
		Vector3(8.5, 0.0, -18.5)
	]
	var sizes: Array[Vector3] = [
		Vector3(0.82, 2.25, 0.82),
		Vector3(0.82, 2.8, 0.82),
		Vector3(0.9, 1.45, 0.9),
		Vector3(0.9, 2.05, 0.9),
		Vector3(0.78, 1.7, 0.78),
		Vector3(0.78, 2.45, 0.78)
	]
	for index in range(positions.size()):
		var size: Vector3 = sizes[index]
		var center := positions[index] + Vector3.UP * (size.y * 0.5)
		var material := _weathered_material if index % 2 == 0 else _stone_material
		_add_solid_block(
			ruins,
			"BrokenPillar_%02d" % index,
			center,
			size,
			material,
			float(index * 11 - 16)
		)


func _build_broken_gate() -> void:
	var gate := Node3D.new()
	gate.name = "BrokenGate"
	add_child(gate)
	var gate_z := -15.8
	_add_solid_block(
		gate,
		"GateLeft",
		Vector3(-4.7, 1.48, gate_z),
		Vector3(1.0, 2.96, 0.92),
		_weathered_material,
		-3.0
	)
	_add_solid_block(
		gate,
		"GateRight",
		Vector3(4.7, 1.22, gate_z),
		Vector3(1.0, 2.44, 0.92),
		_stone_material,
		2.0
	)
	_add_solid_block(
		gate,
		"BrokenLintel",
		Vector3(-0.15, 2.84, gate_z),
		Vector3(8.55, 0.48, 1.02),
		_weathered_material,
		-1.0
	)
	# A narrow, subdued bronze insert gives the gate a single readable point of interest.
	var rune := MeshInstance3D.new()
	rune.name = "GateRune"
	var rune_mesh := BoxMesh.new()
	rune_mesh.size = Vector3(0.12, 0.72, 0.035)
	rune.mesh = rune_mesh
	rune.position = Vector3(-0.15, 2.12, gate_z - 0.535)
	rune.material_override = _bronze_material
	gate.add_child(rune)


func _add_solid_block(
	parent: Node3D,
	block_name: String,
	center: Vector3,
	size: Vector3,
	material: StandardMaterial3D,
	yaw_degrees: float = 0.0
) -> void:
	var body := StaticBody3D.new()
	body.name = block_name
	body.position = center
	body.rotation_degrees.y = yaw_degrees
	body.collision_layer = 1
	body.collision_mask = 1

	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Visual"
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_node.mesh = mesh
	mesh_node.material_override = material
	body.add_child(mesh_node)

	var collision_node := CollisionShape3D.new()
	collision_node.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = size
	collision_node.shape = shape
	body.add_child(collision_node)
	parent.add_child(body)


func _build_rubble() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x415348454E
	var weathered_transforms: Array[Transform3D] = []
	var dark_transforms: Array[Transform3D] = []
	var unit_box := BoxMesh.new()
	unit_box.size = Vector3.ONE

	for index in range(RUBBLE_COUNT):
		var side := -1.0 if rng.randi_range(0, 1) == 0 else 1.0
		var x := side * rng.randf_range(6.2, 13.5)
		var z := rng.randf_range(-22.0, 5.0)
		var scale := Vector3(
			rng.randf_range(0.22, 0.68),
			rng.randf_range(0.14, 0.42),
			rng.randf_range(0.24, 0.82)
		)
		var position := Vector3(x, scale.y * 0.5, z)
		var rotation := Vector3(
			rng.randf_range(-0.16, 0.16),
			rng.randf_range(0.0, TAU),
			rng.randf_range(-0.16, 0.16)
		)
		var transform := Transform3D(Basis.from_euler(rotation).scaled(scale), position)
		if index % 3 == 0:
			dark_transforms.append(transform)
		else:
			weathered_transforms.append(transform)

	_add_rubble_batch("RubbleWeathered", unit_box, _weathered_material, weathered_transforms)
	_add_rubble_batch("RubbleDark", unit_box, _dark_material, dark_transforms)


func _add_rubble_batch(
	batch_name: String,
	mesh: Mesh,
	material: StandardMaterial3D,
	transforms: Array[Transform3D]
) -> void:
	var batch := MultiMeshInstance3D.new()
	batch.name = batch_name
	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.mesh = mesh
	multi_mesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		multi_mesh.set_instance_transform(index, transforms[index])
	batch.multimesh = multi_mesh
	batch.material_override = material
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(batch)
