extends SceneTree

const ARENA_SCRIPT: Script = preload("res://scripts/world/ashen_arena.gd")
const MAIN_SCRIPT: Script = preload("res://scripts/core/main.gd")
const GROUND_SHADER_PATH: String = "res://shaders/world/ashen_ground.gdshader"

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arena := Node3D.new()
	arena.name = "AshenArenaSmokeTest"
	arena.set_script(ARENA_SCRIPT)
	root.add_child(arena)
	await process_frame

	var path := arena.get_node_or_null("PathStones") as Node3D
	_check(path != null, "ruins create a named path-stone group")
	if path != null:
		_check(path.get_child_count() == 9, "path has nine low-cost stone tiles")
		var first_tile := path.get_node_or_null("PathStone_00") as MeshInstance3D
		_check(first_tile != null and first_tile.mesh is BoxMesh, "path tile uses built-in BoxMesh geometry")
		if first_tile != null:
			_check(first_tile.material_override is StandardMaterial3D, "path tile has a reusable material")

	var pillars := arena.get_node_or_null("RuinPillars") as Node3D
	_check(pillars != null, "ruins create perimeter pillars")
	if pillars != null:
		_check(pillars.get_child_count() == 6, "perimeter uses six deliberate pillars")
		var first_pillar := pillars.get_node_or_null("BrokenPillar_00") as StaticBody3D
		_check(first_pillar != null, "pillar has a StaticBody3D for collision")
		if first_pillar != null:
			_check(first_pillar.get_node_or_null("CollisionShape3D") is CollisionShape3D, "pillar collision is independent from its visual mesh")

	var gate := arena.get_node_or_null("BrokenGate") as Node3D
	_check(gate != null, "ruins include a broken gate landmark")
	if gate != null:
		_check(gate.get_node_or_null("GateLeft") is StaticBody3D, "gate left post has collision")
		_check(gate.get_node_or_null("GateRight") is StaticBody3D, "gate right post has collision")
		_check(gate.get_node_or_null("BrokenLintel") is StaticBody3D, "gate lintel is a collidable static prop")
		_check(gate.get_node_or_null("GateRune") is MeshInstance3D, "gate has a small bronze point-of-interest detail")

	var weathered := arena.get_node_or_null("RubbleWeathered") as MultiMeshInstance3D
	var dark := arena.get_node_or_null("RubbleDark") as MultiMeshInstance3D
	_check(weathered != null and weathered.multimesh != null, "weathered rubble uses a MultiMesh batch")
	_check(dark != null and dark.multimesh != null, "dark rubble uses a second MultiMesh batch")
	if weathered != null and weathered.multimesh != null and dark != null and dark.multimesh != null:
		var total_instances: int = weathered.multimesh.instance_count + dark.multimesh.instance_count
		_check(total_instances == 36, "rubble is batched into exactly 36 deterministic instances")
		_check(weathered.material_override is StandardMaterial3D, "rubble batch reuses a mobile-friendly material")

	var solid_props := arena.find_children("*", "StaticBody3D", true, false)
	_check(solid_props.size() == 9, "all nine large ruin props have static collision")
	_check(arena.find_children("*", "GPUParticles3D", true, false).is_empty(), "environment does not add expensive particle emitters")

	arena.queue_free()
	await process_frame
	await _test_ground_material()
	print("[ashen-arena-smoke] failures: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _test_ground_material() -> void:
	var main_node := Node3D.new()
	main_node.name = "GroundMaterialSmokeTest"
	main_node.set_script(MAIN_SCRIPT)
	root.add_child(main_node)
	main_node.call("_create_world")
	await process_frame

	var world := main_node.get_node_or_null("World") as Node3D
	_check(world != null, "main world factory creates its World node")
	var ground_visual := world.get_node_or_null("GroundVisual") as MeshInstance3D if world != null else null
	_check(ground_visual != null, "ground visual exists")
	if ground_visual != null:
		_check(ground_visual.mesh is PlaneMesh, "ground retains its compact PlaneMesh")
		var material := ground_visual.material_override as ShaderMaterial
		_check(material != null, "ground uses the procedural shader material when available")
		if material != null:
			_check(material.shader != null, "procedural ground shader resource is attached")
			_check(material.shader.code.contains("stone_mask"), "ground shader draws stone seams without an image texture")
			_check(material.shader.code.contains("value_noise"), "ground shader adds deterministic low-cost surface variation")
			_check(is_equal_approx(float(material.get_shader_parameter("tile_scale")), 0.72), "ground shader receives the documented world tile scale")
	var ground_body := world.get_node_or_null("Ground") as StaticBody3D if world != null else null
	_check(ground_body != null, "procedural visual preserves separate ground collision")
	main_node.queue_free()
	await process_frame


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
