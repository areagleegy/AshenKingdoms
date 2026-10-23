extends Node
class_name WorldCatalogLoader

signal catalog_loaded(catalog: Dictionary)
signal catalog_load_failed(message: String)

const DEFAULT_CATALOG_PATH := "res://content/world/world_catalog.json"
const EXPECTED_SCHEMA_VERSION := 1
const MAX_CATALOG_BYTES := 2 * 1024 * 1024
const REQUIRED_ARRAYS := [
	"regions", "settlements", "factions", "characters",
	"creatures", "quest_chains", "waterways", "world_events"
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


func get_record(collection_name: String, record_id: String) -> Dictionary:
	var collection: Variant = _catalog.get(collection_name, [])
	if not collection is Array:
		return {}
	for record in collection:
		if record is Dictionary and str(record.get("id", "")) == record_id:
			return record.duplicate(true)
	return {}


func get_equipment(item_type: String, item_id: String) -> Dictionary:
	var equipment: Variant = _catalog.get("equipment", {})
	if not equipment is Dictionary:
		return {}
	var collection: Variant = equipment.get(item_type, [])
	if not collection is Array:
		return {}
	for item in collection:
		if item is Dictionary and str(item.get("id", "")) == item_id:
			return item.duplicate(true)
	return {}


func get_region(region_id: String) -> Dictionary:
	var regions: Variant = _catalog.get("regions", [])
	if not regions is Array:
		return {}
	for region in regions:
		if region is Dictionary and str(region.get("id", "")) == region_id:
			return region.duplicate(true)
	return {}


func _validate_catalog(candidate: Dictionary) -> String:
	var schema_version: Variant = candidate.get("schema_version")
	if not (schema_version is int or schema_version is float):
		return "Unsupported world catalog schema version."
	if float(schema_version) != float(EXPECTED_SCHEMA_VERSION):
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
	var settlement_ids: Dictionary = ids_by_collection["settlements"]
	var creature_ids: Dictionary = ids_by_collection["creatures"]
	var landmark_ids: Dictionary = {}
	for region in candidate["regions"]:
		var names: Variant = region.get("name")
		if not names is Dictionary or str(names.get("ar", "")).is_empty() or str(names.get("en", "")).is_empty():
			return "Region '%s' must have Arabic and English names." % str(region.get("id", ""))
		var landmarks: Variant = region.get("landmarks", [])
		if not landmarks is Array:
			return "Region '%s' landmarks must be an array." % str(region.get("id", ""))
		for landmark in landmarks:
			if not landmark is String or str(landmark).is_empty():
				return "Region '%s' contains an invalid landmark ID." % str(region.get("id", ""))
			landmark_ids[str(landmark)] = true
		var threats: Variant = region.get("threats", [])
		if not threats is Array:
			return "Region '%s' threats must be an array." % str(region.get("id", ""))
		for creature_id in threats:
			if not creature_ids.has(str(creature_id)):
				return "Region '%s' references unknown creature '%s'." % [str(region.get("id", "")), str(creature_id)]

	for settlement in candidate["settlements"]:
		if not region_ids.has(str(settlement.get("region", ""))):
			return "Settlement '%s' references an unknown region." % str(settlement.get("id", ""))

	for creature in candidate["creatures"]:
		var habitats: Variant = creature.get("habitats", [])
		if not habitats is Array:
			return "Creature '%s' habitats must be an array." % str(creature.get("id", ""))
		for region_id in habitats:
			if not region_ids.has(str(region_id)):
				return "Creature '%s' references unknown habitat '%s'." % [str(creature.get("id", "")), str(region_id)]

	var faction_ids: Dictionary = ids_by_collection["factions"]
	var character_ids: Dictionary = ids_by_collection["characters"]
	var quest_titles_en: Dictionary = {}
	for quest in candidate["quest_chains"]:
		var title: Variant = quest.get("title", {})
		if not title is Dictionary or str(title.get("en", "")).is_empty() or str(title.get("ar", "")).is_empty():
			return "Quest '%s' must have Arabic and English titles." % str(quest.get("id", ""))
		var title_en := str(title.get("en", ""))
		if quest_titles_en.has(title_en):
			return "Quest titles must be unique: '%s'." % title_en
		quest_titles_en[title_en] = true

	for character in candidate["characters"]:
		var home_id := str(character.get("home", ""))
		if not settlement_ids.has(home_id) and not landmark_ids.has(home_id):
			return "Character '%s' references an unknown home settlement or landmark." % str(character.get("id", ""))
		var questline := str(character.get("questline", ""))
		if not quest_titles_en.has(questline):
			return "Character '%s' references an unknown questline." % str(character.get("id", ""))

	for quest in candidate["quest_chains"]:
		if not character_ids.has(str(quest.get("start_npc", ""))):
			return "Quest '%s' references an unknown starting character." % str(quest.get("id", ""))
		if not region_ids.has(str(quest.get("region", ""))):
			return "Quest '%s' references an unknown region." % str(quest.get("id", ""))

	for faction in candidate["factions"]:
		var relations: Variant = faction.get("relations", {})
		if not relations is Dictionary:
			return "Faction '%s' relations must be an object." % str(faction.get("id", ""))
		for related_faction in relations.keys():
			if not faction_ids.has(str(related_faction)):
				return "Faction '%s' references unknown faction '%s'." % [str(faction.get("id", "")), str(related_faction)]

	for waterway in candidate["waterways"]:
		var connected_regions: Variant = waterway.get("connects", [])
		if not connected_regions is Array:
			return "Waterway '%s' connects must be an array." % str(waterway.get("id", ""))
		for region_id in connected_regions:
			if not region_ids.has(str(region_id)):
				return "Waterway '%s' references unknown region '%s'." % [str(waterway.get("id", "")), str(region_id)]

	var equipment: Variant = candidate.get("equipment", {})
	if not equipment is Dictionary:
		return "World catalog equipment must be an object."
	for item_type in ["weapons", "armor", "shields"]:
		var items: Variant = equipment.get(item_type, [])
		if not items is Array:
			return "Equipment collection '%s' must be an array." % item_type
		var item_ids: Dictionary = {}
		for item in items:
			if not item is Dictionary:
				return "Equipment collection '%s' contains a non-object entry." % item_type
			var item_id := str(item.get("id", ""))
			if item_id.is_empty() or item_ids.has(item_id):
				return "Equipment collection '%s' contains a missing or duplicate ID." % item_type
			item_ids[item_id] = true
			for stat_name in ["damage", "reach_m", "windup_s", "recovery_s", "stamina_cost", "durability", "physical_resist", "elemental_resist", "guard", "stability"]:
				if item.has(stat_name) and (not (item[stat_name] is int or item[stat_name] is float) or float(item[stat_name]) < 0.0):
					return "Equipment '%s' has an invalid stat '%s'." % [item_id, stat_name]

	var transport: Variant = candidate.get("transport", {})
	if not transport is Dictionary:
		return "World catalog transport must be an object."
	for transport_type in ["mounts", "vehicles", "ships"]:
		var records: Variant = transport.get(transport_type, [])
		if not records is Array:
			return "Transport collection '%s' must be an array." % transport_type
		var transport_ids: Dictionary = {}
		for record in records:
			if not record is Dictionary:
				return "Transport collection '%s' contains a non-object entry." % transport_type
			var transport_id := str(record.get("id", ""))
			if transport_id.is_empty() or transport_ids.has(transport_id):
				return "Transport collection '%s' contains a missing or duplicate ID." % transport_type
			transport_ids[transport_id] = true
			var terrain_bonus: Variant = record.get("terrain_bonus", [])
			if not terrain_bonus is Array:
				return "Transport '%s' terrain_bonus must be an array." % transport_id
			for region_id in terrain_bonus:
				if not region_ids.has(str(region_id)):
					return "Transport '%s' references unknown region '%s'." % [transport_id, str(region_id)]

	var progression: Variant = candidate.get("progression", {})
	if not progression is Dictionary:
		return "World catalog progression must be an object."
	var recommended_order: Variant = progression.get("recommended_region_order", [])
	if not recommended_order is Array:
		return "Progression recommended_region_order must be an array."
	for region_id in recommended_order:
		if not region_ids.has(str(region_id)):
			return "Progression references unknown region '%s'." % str(region_id)
	var level_bands: Variant = progression.get("level_bands", [])
	if not level_bands is Array:
		return "Progression level_bands must be an array."
	for band in level_bands:
		if not band is Dictionary:
			return "Progression contains a non-object level band."
		var min_level: Variant = band.get("min")
		var max_level: Variant = band.get("max")
		if not (min_level is int or min_level is float) or not (max_level is int or max_level is float):
			return "Progression level band must have numeric min and max values."
		if float(min_level) < 0.0 or float(max_level) < float(min_level):
			return "Progression level band has an invalid range."
		if not region_ids.has(str(band.get("region", ""))):
			return "Progression level band references an unknown region."

	return ""


func _fail(message: String) -> bool:
	_last_error = message
	catalog_load_failed.emit(message)
	push_warning(message)
	return false
