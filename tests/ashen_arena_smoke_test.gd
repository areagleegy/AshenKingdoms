extends SceneTree

const ARENA_SCRIPT: Script = preload("res://scripts/world/ashen_arena.gd")

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
	print("[ashen-arena-smoke] failures: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
