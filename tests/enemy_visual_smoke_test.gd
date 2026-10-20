extends SceneTree

const MAIN_SCRIPT: Script = preload("res://scripts/core/main.gd")
const WRAITH_MODEL_PATH: String = "res://assets/characters/enemies/ash_wraith.glb"
var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(ResourceLoader.exists(WRAITH_MODEL_PATH), "Ash Wraith GLB exists")
	var imported := load(WRAITH_MODEL_PATH) as PackedScene
	_check(imported != null, "Ash Wraith GLB imports as a scene")
	if imported != null:
		var model := imported.instantiate()
		var meshes := model.find_children("*", "MeshInstance3D", true, false)
		if model is MeshInstance3D:
			meshes.append(model)

		var surface_count := 0
		var material_surface_count := 0
		for mesh_instance in meshes:
			var mesh := mesh_instance as MeshInstance3D
			if mesh == null or mesh.mesh == null:
				continue
			surface_count += mesh.mesh.get_surface_count()
			for surface_index in range(mesh.mesh.get_surface_count()):
				if mesh.mesh.surface_get_material(surface_index) != null:
					material_surface_count += 1

		_check(surface_count >= 8, "Ash Wraith exposes at least eight mesh surfaces (found %d across %d mesh instance(s))" % [surface_count, meshes.size()])
		_check(material_surface_count >= 7, "Ash Wraith surfaces retain multiple materials (found %d material-backed surface(s))" % material_surface_count)
		model.free()

	var main_node := Node3D.new()
	main_node.set_script(MAIN_SCRIPT)
	var enemy := CharacterBody3D.new()
	var loaded := bool(main_node.call("_add_enemy_model_or_placeholder", enemy))
	_check(loaded, "main scene chooses the imported enemy model")
	_check(enemy.get_node_or_null("CollisionShape3D") != null, "enemy keeps independent capsule collision")
	_check(enemy.get_node_or_null("EnemyVisual/AshWraithModel") != null, "enemy model attaches under EnemyVisual")
	enemy.free()
	main_node.free()
	print("[enemy-visual-smoke] failures: %d" % _failures)
	quit(1 if _failures > 0 else 0)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
