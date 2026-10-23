extends RefCounted
class_name StartingRegionBuilder

const STARTER_REGION_ID := "ashen_basin"
const STONE_DARK := Color(0.16, 0.17, 0.19, 1.0)
const STONE_MID := Color(0.25, 0.26, 0.27, 1.0)
const ASH_WOOD := Color(0.17, 0.12, 0.09, 1.0)
const EMBER_GLOW := Color(0.62, 0.23, 0.075, 1.0)
const WELL_WATER := Color(0.035, 0.10, 0.13, 1.0)
const WORLD_INTERACTABLE_SCRIPT: Script = preload("res://scripts/world/world_interactable.gd")


func build(parent: Node3D, region: Dictionary) -> Node3D:
	var feature_root := Node3D.new()
	feature_root.name = "RegionFeatures"
	feature_root.set_meta("region_id", str(region.get("id", "")))
	parent.add_child(feature_root)

	if str(region.get("id", "")) != STARTER_REGION_ID:
		return feature_root

	var landmarks: Variant = region.get("landmarks", [])
	if not landmarks is Array:
		push_warning("Starting region landmarks are malformed; only the terrain will be shown.")
		return feature_root

	if landmarks.has("cinder_gate"):
		_build_cinder_gate(feature_root)
	if landmarks.has("pilgrims_well"):
		_build_pilgrims_well(feature_root)
	if landmarks.has("broken_waystone"):
		_build_broken_waystone(feature_root)

	_build_perimeter_props(feature_root)
	return feature_root


func _build_cinder_gate(parent: Node3D) -> void:
	var poi := _create_poi(parent, "cinder_gate", Vector3(0.0, 0.0, -25.0))
	_add_box(poi, "GateLeftPillar", Vector3(0.9, 4.2, 1.0), Vector3(-5.5, 2.1, 0.0), STONE_DARK, true)
	_add_box(poi, "GateRightPillar", Vector3(0.9, 4.2, 1.0), Vector3(5.5, 2.1, 0.0), STONE_DARK, true)
	_add_box(poi, "GateLintel", Vector3(11.9, 0.65, 1.1), Vector3(0.0, 4.05, 0.0), STONE_MID, true)
	_add_box(poi, "LeftOuterWall", Vector3(7.2, 1.35, 0.85), Vector3(-9.6, 0.68, 0.0), STONE_DARK, true)
	_add_box(poi, "RightOuterWall", Vector3(7.2, 1.35, 0.85), Vector3(9.6, 0.68, 0.0), STONE_DARK, true)
	_add_box(poi, "BrokenCopingLeft", Vector3(2.8, 0.22, 1.05), Vector3(-9.0, 1.47, 0.0), STONE_MID, false, Vector3(0.0, 0.0, -3.0))
	_add_box(poi, "BrokenCopingRight", Vector3(2.2, 0.2, 1.05), Vector3(9.3, 1.45, 0.0), STONE_MID, false, Vector3(0.0, 0.0, 4.0))


func _build_pilgrims_well(parent: Node3D) -> void:
	var poi := _create_poi(parent, "pilgrims_well", Vector3(-14.0, 0.0, -6.0))
	_add_cylinder(poi, "WellFoundation", 1.65, 0.18, Vector3(0.0, 0.09, 0.0), STONE_DARK, true)
	for index in range(8):
		var angle := TAU * float(index) / 8.0
		var segment_position := Vector3(cos(angle) * 1.18, 0.53, sin(angle) * 1.18)
		_add_box(
			poi, "WellStone_%02d" % index,
			Vector3(0.88, 0.82, 0.42), segment_position, STONE_MID, true,
			Vector3(0.0, rad_to_deg(angle), 0.0)
		)
	_add_cylinder(poi, "DarkWater", 0.91, 0.035, Vector3(0.0, 0.39, 0.0), WELL_WATER, false)
	_add_box(poi, "RopePost", Vector3(0.12, 1.45, 0.12), Vector3(1.45, 0.9, -0.05), ASH_WOOD, true)
	_add_box(poi, "RopeArm", Vector3(1.35, 0.12, 0.12), Vector3(0.8, 1.48, -0.05), ASH_WOOD, false, Vector3(0.0, 0.0, -7.0))


func _build_broken_waystone(parent: Node3D) -> void:
	var poi := _create_poi(parent, "broken_waystone", Vector3(13.0, 0.0, -13.0))
	_add_box(poi, "WaystoneBase", Vector3(2.4, 0.42, 1.65), Vector3(0.0, 0.21, 0.0), STONE_DARK, true)
	_add_box(
		poi, "MainFragment", Vector3(0.62, 2.7, 0.48), Vector3(0.0, 1.75, 0.0),
		STONE_MID, true, Vector3(0.0, 0.0, -8.0)
	)
	_add_box(
		poi, "BrokenFragmentLeft", Vector3(0.42, 1.15, 0.4), Vector3(-0.58, 0.83, 0.05),
		STONE_DARK, true, Vector3(0.0, 0.0, 23.0)
	)
	_add_box(
		poi, "BrokenFragmentRight", Vector3(0.38, 0.84, 0.36), Vector3(0.54, 0.62, -0.04),
		STONE_MID, true, Vector3(0.0, 0.0, -31.0)
	)
	_add_box(poi, "FaintEmberMark", Vector3(0.08, 1.05, 0.025), Vector3(0.0, 1.55, -0.25), EMBER_GLOW, false)


func _build_perimeter_props(parent: Node3D) -> void:
	var rock_positions: Array[Vector3] = [
		Vector3(-23.0, 0.0, -17.0), Vector3(23.0, 0.0, -19.0),
		Vector3(-26.0, 0.0, -3.0), Vector3(26.0, 0.0, 5.0),
		Vector3(-22.0, 0.0, 16.0), Vector3(20.0, 0.0, 21.0),
		Vector3(-10.0, 0.0, 30.0), Vector3(11.0, 0.0, 31.0)
	]
	var rock_sizes: Array[Vector3] = [
		Vector3(1.8, 1.0, 1.3), Vector3(2.1, 1.35, 1.4),
		Vector3(1.4, 0.8, 1.1), Vector3(1.7, 1.05, 1.6)
	]
	for index in range(rock_positions.size()):
		var rock_size: Vector3 = rock_sizes[index % rock_sizes.size()]
		var position := rock_positions[index] + Vector3.UP * rock_size.y * 0.5
		_add_box(
			parent, "AshRock_%02d" % index, rock_size, position, STONE_DARK, true,
			Vector3(0.0, float(index * 19), float((index % 3) * 7 - 7))
		)

	_build_burnt_tree(parent, "BurntTree_Northwest", Vector3(-20.0, 0.0, -20.0))
	_build_burnt_tree(parent, "BurntTree_East", Vector3(20.0, 0.0, -4.0))
	_build_burnt_tree(parent, "BurntTree_South", Vector3(16.0, 0.0, 23.0))


func _build_burnt_tree(parent: Node3D, tree_name: String, position: Vector3) -> void:
	_add_cylinder(
		parent, tree_name + "_Trunk", 0.24, 3.7, position + Vector3.UP * 1.85,
		ASH_WOOD, true, Vector3(0.0, 0.0, 6.0)
	)
	_add_box(
		parent, tree_name + "_BranchLeft", Vector3(1.55, 0.16, 0.2),
		position + Vector3(-0.45, 2.6, 0.0), ASH_WOOD, false, Vector3(0.0, 0.0, 31.0)
	)
	_add_box(
		parent, tree_name + "_BranchRight", Vector3(1.2, 0.16, 0.2),
		position + Vector3(0.38, 3.0, 0.02), ASH_WOOD, false, Vector3(0.0, 0.0, -34.0)
	)


func _create_poi(parent: Node3D, landmark_id: String, position: Vector3) -> Node3D:
	var poi := Node3D.new()
	poi.set_script(WORLD_INTERACTABLE_SCRIPT)
	poi.name = "POI_%s" % landmark_id
	poi.position = position
	poi.set_meta("landmark_id", landmark_id)
	poi.set("interaction_id", StringName(landmark_id))
	poi.set("display_name", _landmark_display_name(landmark_id))
	poi.set("interaction_message", _landmark_interaction_message(landmark_id))
	parent.add_child(poi)
	return poi


func _landmark_display_name(landmark_id: String) -> String:
	match landmark_id:
		"cinder_gate":
			return "بوابة الجمر"
		"pilgrims_well":
			return "بئر الحجاج"
		"broken_waystone":
			return "حجر الطريق المكسور"
		_:
			return "معلم مجهول"


func _landmark_interaction_message(landmark_id: String) -> String:
	match landmark_id:
		"cinder_gate":
			return "بوابة الجمر: الطريق الإقليمي يبدأ من هنا، لكن الطريق إلى الأطلال لن يُفتح قبل إصلاح إشارات الحراسة."
		"pilgrims_well":
			return "بئر الحجاج: آثار أقدام حول الحجر؛ يبدو أن قافلة توقفت هنا قبل العاصفة."
		"broken_waystone":
			return "حجر الطريق المكسور: نواة زجاج الجمر خامدة. قد تعيدها قطعة أثرية إلى العمل."
		_:
			return "لا توجد معلومات مسجلة عن هذا المعلم."


func _add_box(
	parent: Node3D,
	object_name: String,
	size: Vector3,
	position: Vector3,
	tint: Color,
	with_collision: bool,
	local_rotation: Vector3 = Vector3.ZERO
) -> Node3D:
	var object: Node3D
	if with_collision:
		object = StaticBody3D.new()
	else:
		object = Node3D.new()
	object.name = object_name
	object.position = position
	object.rotation_degrees = local_rotation
	parent.add_child(object)

	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Visual"
	mesh_node.mesh = box_mesh
	mesh_node.material_override = _make_material(tint)
	object.add_child(mesh_node)

	if with_collision:
		var collision_node := CollisionShape3D.new()
		collision_node.name = "CollisionShape3D"
		var collision_shape := BoxShape3D.new()
		collision_shape.size = size
		collision_node.shape = collision_shape
		object.add_child(collision_node)
	return object


func _add_cylinder(
	parent: Node3D,
	object_name: String,
	radius: float,
	height: float,
	position: Vector3,
	tint: Color,
	with_collision: bool,
	local_rotation: Vector3 = Vector3.ZERO
) -> Node3D:
	var object: Node3D
	if with_collision:
		object = StaticBody3D.new()
	else:
		object = Node3D.new()
	object.name = object_name
	object.position = position
	object.rotation_degrees = local_rotation
	parent.add_child(object)

	var cylinder_mesh := CylinderMesh.new()
	cylinder_mesh.top_radius = radius
	cylinder_mesh.bottom_radius = radius
	cylinder_mesh.height = height
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Visual"
	mesh_node.mesh = cylinder_mesh
	mesh_node.material_override = _make_material(tint)
	object.add_child(mesh_node)

	if with_collision:
		var collision_node := CollisionShape3D.new()
		collision_node.name = "CollisionShape3D"
		var collision_shape := CylinderShape3D.new()
		collision_shape.radius = radius
		collision_shape.height = height
		collision_node.shape = collision_shape
		object.add_child(collision_node)
	return object


func _make_material(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.96
	return material
