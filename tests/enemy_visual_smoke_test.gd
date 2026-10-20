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
		_check(meshes.size() >= 8, "Ash Wraith has multiple visible mesh surfaces")
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
