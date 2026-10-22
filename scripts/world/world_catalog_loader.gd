extends Node
class_name WorldCatalogLoader

signal catalog_loaded(catalog: Dictionary)
signal catalog_load_failed(message: String)

const DEFAULT_CATALOG_PATH := "res://content/world/world_catalog.json"
const EXPECTED_SCHEMA_VERSION := 1
const MAX_CATALOG_BYTES := 2 * 1024 * 1024
const REQUIRED_ARRAYS := [
	"regions", "settlements", "factions", "characters",
	"creatures", "quest_chains", "waterways"
]

var _catalog: Dictionary = {}
var _last_error := ""


func _ready() -> void:
	load_catalog()


func load_catalog(path: String = DEFAULT_CATALOG_PATH) -> bool:
	_catalog.clear()
	_last_error = ""
	if path.is_empty():
		return _fail("World catalog path is empty.")
	if not FileAccess.file_exists(path):
		return _fail("World catalog file does not exist: %s" % path)

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("World catalog could not be opened (error %d)." % FileAccess.get_open_error())
	if file.get_length() <= 0 or file.get_length() > MAX_CATALOG_BYTES:
		file.close()
		return _fail("World catalog is empty or exceeds the size limit.")
	var raw_json := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(raw_json)
	if not parsed is Dictionary:
		return _fail("World catalog must contain a JSON object.")
	var candidate: Dictionary = parsed
	var validation_error := _validate_catalog(candidate)
	if not validation_error.is_empty():
		return _fail(validation_error)

	_catalog = candidate.duplicate(true)
	catalog_loaded.emit(get_catalog())
	return true


func get_catalog() -> Dictionary:
	return _catalog.duplicate(true)


func get_last_error() -> String:
	return _last_error


func get_region(region_id: String) -> Dictionary:
	for region in _catalog.get("regions", []):
		if region is Dictionary and str(region.get("id", "")) == region_id:
			return region.duplicate(true)
	return {}


func _validate_catalog(candidate: Dictionary) -> String:
	if int(candidate.get("schema_version", -1)) != EXPECTED_SCHEMA_VERSION:
		return "Unsupported world catalog schema version."
	if str(candidate.get("world_id", "")) != "ashen_kingdoms":
		return "Unexpected world catalog ID."

	var ids_by_collection: Dictionary = {}
	for collection_name in REQUIRED_ARRAYS:
		var collection: Variant = candidate.get(collection_name)
		if not collection is Array:
			return "World catalog field '%s' must be an array." % collection_name
		var ids: Dictionary = {}
		for index in range(collection.size()):
			var record: Variant = collection[index]
			if not record is Dictionary:
				return "World catalog field '%s' entry %d must be an object." % [collection_name, index]
			var record_id := str(record.get("id", ""))
			if record_id.is_empty():
				return "World catalog field '%s' contains an entry without an ID." % collection_name
			if ids.has(record_id):
				return "World catalog field '%s' contains duplicate ID '%s'." % [collection_name, record_id]
			ids[record_id] = true
		ids_by_collection[collection_name] = ids

	var region_ids: Dictionary = ids_by_collection["regions"]
	var creature_ids: Dictionary = ids_by_collection["creatures"]
	for region in candidate["regions"]:
		var names: Variant = region.get("name")
		if not names is Dictionary or str(names.get("ar", "")).is_empty() or str(names.get("en", "")).is_empty():
			return "Region '%s' must have Arabic and English names." % str(region.get("id", ""))
		var threats: Variant = region.get("threats", [])
		if not threats is Array:
			return "Region '%s' threats must be an array." % str(region.get("id", ""))
		for creature_id in threats:
			if not creature_ids.has(str(creature_id)):
				return "Region '%s' references unknown creature '%s'." % [str(region.get("id", "")), str(creature_id)]

	for settlement in candidate["settlements"]:
		if not region_ids.has(str(settlement.get("region", ""))):
			return "Settlement '%s' references an unknown region." % str(settlement.get("id", ""))

	return ""
	

func _fail(message: String) -> bool:
	_last_error = message
	catalog_load_failed.emit(message)
	push_warning(message)
	return false
