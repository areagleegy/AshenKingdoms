extends SceneTree

const EFFECT_SCENE: PackedScene = preload("res://scenes/vfx/CombatHitEffect.tscn")

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var effect := EFFECT_SCENE.instantiate() as Node3D
	_check(effect != null, "combat hit effect scene instantiates")
	if effect == null:
		quit(1)
		return

	root.add_child(effect)
	await process_frame
	_check(effect.get_child_count() == 1 + 6, "effect creates a glow and six spark meshes")
	if is_instance_valid(effect):
		_check(effect.has_node("ImpactGlow"), "effect has the central glow mesh")

	await create_timer(0.35).timeout
	_check(not is_instance_valid(effect), "effect self-cleans after its animation")

	print("[combat-vfx-smoke] failures: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
