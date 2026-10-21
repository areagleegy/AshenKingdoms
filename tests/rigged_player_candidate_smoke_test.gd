extends SceneTree

const CANDIDATE_PATH: String = "res://assets/characters/player/player_rigged_candidate_ci.glb"
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(ResourceLoader.exists(CANDIDATE_PATH), "CI-generated rigged player candidate exists")
	var packed := load(CANDIDATE_PATH) as PackedScene
	_check(packed != null, "rigged player candidate imports as PackedScene")
	if packed != null:
		var model := packed.instantiate()
		root.add_child(model)
		var skeletons := model.find_children("*", "Skeleton3D", true, false)
		if model is Skeleton3D:
			skeletons.append(model)
		_check(not skeletons.is_empty(), "candidate imports a Skeleton3D")
		if not skeletons.is_empty():
			var skeleton := skeletons[0] as Skeleton3D
			_check(skeleton != null and skeleton.get_bone_count() >= 15, "candidate exposes at least 15 bones")
		var animation_nodes := model.find_children("*", "AnimationPlayer", true, false)
		_check(not animation_nodes.is_empty(), "candidate imports an AnimationPlayer")
		if not animation_nodes.is_empty():
			var animation_player := animation_nodes[0] as AnimationPlayer
			var normalized_names: Array[String] = []
			for clip_name in animation_player.get_animation_list():
				normalized_names.append(_normalize(String(clip_name)))
			for clip_alias in ["idle", "walking", "running", "jump", "heavyattack", "hit", "death"]:
				var found := false
				for actual_name in normalized_names:
					if actual_name.contains(clip_alias):
						found = true
						break
				_check(found, "animation clip available: %s" % clip_alias)
		model.free()
	print("[rigged-player-candidate-smoke] failures: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _normalize(value: String) -> String:
	return value.to_lower().replace("_", "").replace("-", "").replace(" ", "")


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)
