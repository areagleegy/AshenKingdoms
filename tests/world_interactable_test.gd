extends SceneTree

const INTERACTABLE_PATH := "res://scripts/world/world_interactable.gd"
const DETECTOR_PATH := "res://scripts/player/interaction_detector.gd"
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var interactable_script := load(INTERACTABLE_PATH) as Script
	_check(interactable_script != null, "world interactable script loads")
	if interactable_script == null:
		quit(1)
		return

	var target := Node3D.new()
	target.name = "TestLandmark"
	target.set_script(interactable_script)
	target.set("interaction_id", &"pilgrims_well")
	target.set("display_name", "بئر الحجاج")
	target.set("interaction_message", "رسالة اختبار")
	root.add_child(target)

	_check(target.is_in_group("world_interactable"), "interactable registers its group")
	_check(target.has_method("interact"), "interactable exposes an interaction method")
	_check(target.call("get_interaction_button_text") == "افحص", "interactable exposes a localized touch-button label")
	var zone := target.get_node_or_null("InteractionZone") as Area3D
	_check(zone != null, "interactable creates an interaction area")
	if zone != null:
		_check(zone.collision_layer == 4, "interaction area uses the configured target collision layer")
		_check(zone.monitorable, "interaction area can be detected by the player's detector")
		_check(zone.get_node_or_null("CollisionShape3D") is CollisionShape3D, "interaction area has a collision shape")

	var prompt := target.get_node_or_null("InteractionPrompt") as Label3D
	_check(prompt != null, "interactable creates its world-space prompt")
	if prompt != null:
		_check(not prompt.visible, "interaction prompt starts hidden")
		target.call("set_prompt_visible", true)
		_check(prompt.visible, "interaction prompt can be shown")
		target.call("set_prompt_visible", false)
		_check(not prompt.visible, "interaction prompt can be hidden")

	var emitted_ids: Array[StringName] = []
	target.connect("interacted", func(interaction_id: StringName) -> void:
		emitted_ids.append(interaction_id)
	)
	target.call("interact")
	_check(emitted_ids.size() == 1 and emitted_ids[0] == &"pilgrims_well", "interact emits the stable landmark ID")

	var detector_script := load(DETECTOR_PATH) as Script
	_check(detector_script != null, "player interaction detector script loads")
	if detector_script != null and zone != null:
		var detector := Area3D.new()
		detector.name = "TestInteractionDetector"
		detector.set_script(detector_script)
		root.add_child(detector)
		detector.call("_on_area_entered", zone)
		_check(detector.get("current_target") == target, "player detector selects a world landmark target")
		_check(prompt != null and prompt.visible, "selecting a landmark shows its prompt")
		detector.call("interact")
		_check(prompt != null and prompt.visible, "inspecting a landmark keeps its prompt visible in range")
		_check(emitted_ids.size() == 2, "player interaction delegates to the selected landmark")
		detector.call("_on_area_exited", zone)
		_check(detector.get("current_target") == null, "leaving the target clears the interaction selection")
		_check(prompt != null and not prompt.visible, "leaving interaction range hides the landmark prompt")
		detector.free()

	target.free()
	print("[world-interactable] failures: %d" % failures)
	quit(1 if failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] %s" % message)
	else:
		failures += 1
		push_error("[FAIL] %s" % message)
