extends SceneTree

const BUILDER_SCRIPT := "res://scripts/world/starting_region_builder.gd"
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var builder_script := load(BUILDER_SCRIPT) as Script
	_check(builder_script != null, "starting region builder script loads")
	if builder_script == null:
		quit(1)
		return

	var host := Node3D.new()
	host.name = "BuilderTestHost"
	root.add_child(host)
	var builder := builder_script.new() as RefCounted
	_check(builder != null, "starting region builder can be instantiated")
	if builder == null:
		host.queue_free()
		quit(1)
		return

	var region := {
		"id": "ashen_basin",
		"landmarks": ["cinder_gate", "pilgrims_well", "broken_waystone"]
	}
	var features: Node3D = builder.call("build", host, region) as Node3D
	_check(features != null, "builder returns the starter region features node")
	if features == null:
		host.queue_free()
		quit(1)
		return

	_check(features.get_node_or_null("POI_cinder_gate") != null, "catalog gate landmark creates a gate POI")
	_check(features.get_node_or_null("POI_pilgrims_well") != null, "catalog well landmark creates a well POI")
	_check(features.get_node_or_null("POI_broken_waystone") != null, "catalog waystone landmark creates a waystone POI")
	var gate := features.get_node_or_null("POI_cinder_gate")
	_check(gate.has_meta("landmark_id") and gate.get_meta("landmark_id") == "cinder_gate", "gate POI keeps its catalog landmark ID")
	_check(gate.get_node_or_null("GateLeftPillar/CollisionShape3D") != null, "gate structure includes physical collision")
	_check(features.get_node_or_null("BurntTree_East_Trunk/CollisionShape3D") != null, "perimeter props include physical collision")

	var other_host := Node3D.new()
	other_host.name = "OtherRegionTestHost"
	root.add_child(other_host)
	var other_features: Node3D = builder.call(
		"build", other_host, {"id": "coalwood", "landmarks": ["widow_tree"]}
	) as Node3D
	_check(other_features != null and other_features.get_child_count() == 0, "other regions do not receive the Ashen Basin layout")

	host.queue_free()
	other_host.queue_free()
	print("[starting-region-builder] failures: %d" % failures)
	quit(1 if failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] %s" % message)
	else:
		failures += 1
		push_error("[FAIL] %s" % message)
