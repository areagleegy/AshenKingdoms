extends Node
class_name WorldJournal

signal landmark_discovered(region_id: StringName, landmark_id: StringName)

const SAVE_VERSION := 1
const MAX_DISCOVERED_LANDMARKS := 128
var _discovered_landmarks: Dictionary = {}


func _ready() -> void:
	add_to_group("world_journal")


func discover_landmark(region_id: StringName, landmark_id: StringName) -> bool:
	var region_key := String(region_id)
	var landmark_key := String(landmark_id)
	if not _is_known_landmark(region_key, landmark_key):
		return false

	var region_discoveries: Variant = _discovered_landmarks.get(region_key, {})
	if not region_discoveries is Dictionary:
		region_discoveries = {}
	if bool(region_discoveries.get(landmark_key, false)):
		return false
	if _discovered_count() >= MAX_DISCOVERED_LANDMARKS:
		return false

	region_discoveries[landmark_key] = true
	_discovered_landmarks[region_key] = region_discoveries
	landmark_discovered.emit(region_id, landmark_id)
	return true


func is_discovered(region_id: StringName, landmark_id: StringName) -> bool:
	var region_discoveries: Variant = _discovered_landmarks.get(String(region_id), {})
	return region_discoveries is Dictionary and bool(region_discoveries.get(String(landmark_id), false))


func to_save_data() -> Dictionary:
	return {"version": SAVE_VERSION, "regions": _discovered_landmarks.duplicate(true)}


func restore_save_data(data: Variant) -> void:
	_discovered_landmarks.clear()
	if not data is Dictionary:
		return

	var version: Variant = data.get("version")
	if typeof(version) != TYPE_INT and typeof(version) != TYPE_FLOAT:
		return
	if float(version) != float(SAVE_VERSION):
		return
	var raw_regions: Variant = data.get("regions", {})
	if not raw_regions is Dictionary:
		return

	var accepted_count := 0
	for raw_region_id in raw_regions.keys():
		if typeof(raw_region_id) != TYPE_STRING:
			continue
		var region_id := String(raw_region_id)
		var raw_landmarks: Variant = raw_regions[raw_region_id]
		if not raw_landmarks is Dictionary:
			continue
		for raw_landmark_id in raw_landmarks.keys():
			if accepted_count >= MAX_DISCOVERED_LANDMARKS:
				return
			if typeof(raw_landmark_id) != TYPE_STRING:
				continue
			var landmark_id := String(raw_landmark_id)
			var marker: Variant = raw_landmarks[raw_landmark_id]
			if typeof(marker) != TYPE_BOOL or not bool(marker):
				continue
			if not _is_known_landmark(region_id, landmark_id):
				continue
			var region_discoveries: Dictionary = _discovered_landmarks.get(region_id, {})
			region_discoveries[landmark_id] = true
			_discovered_landmarks[region_id] = region_discoveries
			accepted_count += 1


func _is_known_landmark(region_id: String, landmark_id: String) -> bool:
	if region_id.is_empty() or landmark_id.is_empty():
		return false
	var catalog_loader := get_node_or_null("/root/WorldCatalog")
	if catalog_loader == null or not catalog_loader.has_method("get_region"):
		return false
	var raw_region: Variant = catalog_loader.call("get_region", region_id)
	if not raw_region is Dictionary or raw_region.is_empty():
		return false
	var landmarks: Variant = raw_region.get("landmarks", [])
	return landmarks is Array and landmarks.has(landmark_id)


func _discovered_count() -> int:
	var count := 0
	for region_value in _discovered_landmarks.values():
		if region_value is Dictionary:
			count += region_value.size()
	return count
