extends SceneTree

const JOURNAL_PATH := "res://scripts/world/world_journal.gd"
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var journal_script := load(JOURNAL_PATH) as Script
	_check(journal_script != null, "world journal script loads")
	if journal_script == null:
		quit(1)
		return

	var journal := journal_script.new() as Node
	journal.name = "JournalTest"
	root.add_child(journal)
	_check(journal.is_in_group("world_journal"), "world journal registers its lookup group")
	var events: Array[String] = []
	journal.connect("landmark_discovered", func(region_id: StringName, landmark_id: StringName) -> void:
		events.append("%s/%s" % [String(region_id), String(landmark_id)])
	)
	_check(bool(journal.call("discover_landmark", &"ashen_basin", &"cinder_gate")), "known catalog landmark is discovered")
	_check(bool(journal.call("is_discovered", &"ashen_basin", &"cinder_gate")), "discovery state is queryable")
	_check(not bool(journal.call("discover_landmark", &"ashen_basin", &"cinder_gate")), "the same landmark is discovered only once")
	_check(events.size() == 1 and events[0] == "ashen_basin/cinder_gate", "first discovery emits one stable event")
	_check(not bool(journal.call("discover_landmark", &"missing_region", &"cinder_gate")), "unknown regions are rejected")
	_check(not bool(journal.call("discover_landmark", &"ashen_basin", &"missing_landmark")), "unknown landmarks are rejected")

	var saved: Dictionary = journal.call("to_save_data")
	_check(int(saved.get("version", 0)) == 1, "journal save data carries a schema version")
	var restored := journal_script.new() as Node
	restored.name = "RestoredJournalTest"
	root.add_child(restored)
	restored.call("restore_save_data", saved)
	_check(bool(restored.call("is_discovered", &"ashen_basin", &"cinder_gate")), "valid discovery persists through save/restore")
	_check(not bool(restored.call("is_discovered", &"ashen_basin", &"fabricated_landmark")), "save/restore never accepts unknown landmark IDs")

	var filtered_data := {
		"version": 1,
		"regions": {
			"ashen_basin": {"cinder_gate": true, "fabricated_landmark": true},
			"missing_region": {"missing_landmark": true}
		}
	}
	restored.call("restore_save_data", filtered_data)
	_check(bool(restored.call("is_discovered", &"ashen_basin", &"cinder_gate")), "restore accepts known landmarks from save data")
	_check(not bool(restored.call("is_discovered", &"ashen_basin", &"fabricated_landmark")), "restore filters fabricated landmark IDs")
	_check(not bool(restored.call("is_discovered", &"missing_region", &"missing_landmark")), "restore filters unknown regions")

	restored.call("restore_save_data", {"version": 999, "regions": {"ashen_basin": {"cinder_gate": true}}})
	_check(not bool(restored.call("is_discovered", &"ashen_basin", &"cinder_gate")), "unsupported journal schema clears saved discoveries safely")

	journal.free()
	restored.free()
	print("[world-journal] failures: %d" % failures)
	quit(1 if failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] %s" % message)
	else:
		failures += 1
		push_error("[FAIL] %s" % message)
