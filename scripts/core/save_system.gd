extends Node

const SAVE_PATH: String = "user://savegame.json"
const TEMP_PATH: String = "user://savegame.json.tmp"
const BACKUP_PATH: String = "user://savegame.json.bak"
const BACKUP_TEMP_PATH: String = "user://savegame.json.bak.tmp"

const CURRENT_SCHEMA_VERSION: int = 1
const MAX_SAVE_BYTES: int = 2 * 1024 * 1024
const MAX_JSON_DEPTH: int = 32
const MAX_CONTAINER_ITEMS: int = 4096
const MAX_STRING_LENGTH: int = 262144
const MAX_ABS_NUMBER: float = 1000000000.0
const MAX_PLAYER_LEVEL: int = 50
const MAX_INVENTORY_SLOTS: int = 80
const MAX_INVENTORY_STACK: int = 999
const MAX_QUEST_PROGRESS: int = 100

const READ_CANDIDATES: Array[String] = [
    SAVE_PATH,
    BACKUP_PATH,
    BACKUP_TEMP_PATH,
    TEMP_PATH,
]


func save_game(data: Dictionary) -> bool:
    var prepared: Dictionary = _prepare_save_data(data)
    if prepared.is_empty():
        push_warning("Save rejected: data failed schema or bounds validation.")
        return false

    var serialized := JSON.stringify(prepared, "\t")
    var serialized_bytes: PackedByteArray = serialized.to_utf8_buffer()
    if serialized_bytes.is_empty() or serialized_bytes.size() > MAX_SAVE_BYTES:
        push_warning("Save rejected: serialized data is empty or exceeds the size limit.")
        return false

    # A directory at the temp path is treated as a write failure. Do not touch
    # the primary save or the existing backup in that case.
    if _is_directory(TEMP_PATH) or _is_directory(SAVE_PATH):
        push_warning("Save aborted: a managed save path is a directory.")
        return false

    if not _write_verified_file(TEMP_PATH, serialized):
        push_warning("Save aborted: could not write and verify the temporary save.")
        return false
    if _read_save_data(TEMP_PATH).is_empty():
        push_warning("Save aborted: the temporary save failed validation.")
        _remove_file_if_present(TEMP_PATH)
        return false

    # Rotate only a validated primary save into the backup. If the primary is
    # corrupt, preserve the previous backup instead of overwriting it.
    if not _read_save_data(SAVE_PATH).is_empty():
        if not _rotate_primary_to_backup():
            _remove_file_if_present(TEMP_PATH)
            push_warning("Save aborted: could not safely refresh the backup.")
            return false

    var replace_error: Error = DirAccess.rename_absolute(
        _absolute_path(TEMP_PATH),
        _absolute_path(SAVE_PATH)
    )
    if replace_error != OK:
        push_warning("Save aborted: could not replace the primary save (%s)." % error_string(replace_error))
        _remove_file_if_present(TEMP_PATH)
        return false

    if _read_save_data(SAVE_PATH).is_empty():
        push_warning("Save replacement completed but verification failed; keep the backup for recovery.")
        return false
    return true


func load_game() -> Dictionary:
    var primary: Dictionary = _read_save_data(SAVE_PATH)
    if not primary.is_empty():
        if _file_needs_migration(SAVE_PATH):
            # Persist the migration while retaining the raw, validated legacy
            # file as backup until the schema-v1 replacement is verified.
            if not save_game(primary):
                push_warning("Loaded a legacy save, but could not persist its migration.")
        return primary

    if FileAccess.file_exists(SAVE_PATH):
        push_warning("Primary save is invalid; trying a validated recovery candidate.")

    # Prefer the previous known-good save over an uncommitted temp file.
    for candidate in [BACKUP_PATH, BACKUP_TEMP_PATH, TEMP_PATH]:
        var recovered: Dictionary = _read_save_data(candidate)
        if recovered.is_empty():
            continue
        push_warning("Recovering save data from %s." % candidate)
        if not save_game(recovered):
            push_warning("Recovered data is usable, but restoring the primary save failed.")
        return recovered

    return {}


func has_save() -> bool:
    for candidate in READ_CANDIDATES:
        if not _read_save_data(candidate).is_empty():
            return true
    return false


func delete_save() -> bool:
    var succeeded := true
    for path in [SAVE_PATH, TEMP_PATH, BACKUP_PATH, BACKUP_TEMP_PATH]:
        if _is_directory(path):
            push_warning("Cannot delete managed save path because it is a directory: %s" % path)
            succeeded = false
            continue
        if not FileAccess.file_exists(path):
            continue
        var remove_error: Error = DirAccess.remove_absolute(_absolute_path(path))
        if remove_error != OK:
            push_warning("Could not remove save file %s (%s)." % [path, error_string(remove_error)])
            succeeded = false
    return succeeded


func _rotate_primary_to_backup() -> bool:
    var raw_primary := _read_raw_text(SAVE_PATH)
    if raw_primary.is_empty():
        return false
    if _is_directory(BACKUP_PATH) or _is_directory(BACKUP_TEMP_PATH):
        return false
    if not _write_verified_file(BACKUP_TEMP_PATH, raw_primary):
        _remove_file_if_present(BACKUP_TEMP_PATH)
        return false
    if _read_save_data(BACKUP_TEMP_PATH).is_empty():
        _remove_file_if_present(BACKUP_TEMP_PATH)
        return false

    var rename_error: Error = DirAccess.rename_absolute(
        _absolute_path(BACKUP_TEMP_PATH),
        _absolute_path(BACKUP_PATH)
    )
    if rename_error != OK:
        push_warning("Could not rotate the previous save into the backup (%s)." % error_string(rename_error))
        _remove_file_if_present(BACKUP_TEMP_PATH)
        return false
    return not _read_save_data(BACKUP_PATH).is_empty()


func _write_verified_file(path: String, text: String) -> bool:
    if _is_directory(path):
        return false
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        push_warning("Could not open %s for writing (%s)." % [path, error_string(FileAccess.get_open_error())])
        return false

    file.store_string(text)
    file.flush()
    var write_error: Error = file.get_error()
    file.close()
    if write_error != OK:
        push_warning("Write failed for %s (%s)." % [path, error_string(write_error)])
        return false

    var written := _read_raw_text(path)
    return written == text and not written.is_empty() and written.to_utf8_buffer().size() <= MAX_SAVE_BYTES


func _read_save_data(path: String) -> Dictionary:
    if _is_directory(path) or not FileAccess.file_exists(path):
        return {}
    var raw_text := _read_raw_text(path)
    if raw_text.is_empty() or raw_text.to_utf8_buffer().size() > MAX_SAVE_BYTES:
        return {}

    var parser := JSON.new()
    var parse_error: Error = parser.parse(raw_text)
    if parse_error != OK:
        return {}
    var parsed: Variant = parser.data
    if not (parsed is Dictionary):
        return {}
    return _prepare_save_data(parsed as Dictionary)


func _prepare_save_data(data: Dictionary) -> Dictionary:
    if data.is_empty() or not _is_safe_json_value(data, 0):
        return {}

    var prepared: Dictionary = data.duplicate(true)
    var schema_value: Variant = prepared.get("schema_version", 0)
    if not _is_integer_value(schema_value):
        return {}
    var schema_version := int(schema_value)
    if schema_version < 0 or schema_version > CURRENT_SCHEMA_VERSION:
        return {}

    while schema_version < CURRENT_SCHEMA_VERSION:
        match schema_version:
            0:
                prepared = _migrate_v0_to_v1(prepared)
                schema_version = 1
            _:
                return {}

    prepared["schema_version"] = CURRENT_SCHEMA_VERSION
    if not _validate_gameplay_fields(prepared):
        return {}
    return prepared


func _migrate_v0_to_v1(legacy: Dictionary) -> Dictionary:
    # Schema 0 is the existing format: it has no schema_version key. Preserve
    # all known game fields and add the explicit format marker.
    var migrated: Dictionary = legacy.duplicate(true)
    migrated["schema_version"] = 1
    return migrated


func _validate_gameplay_fields(data: Dictionary) -> bool:
    var level := 1
    if data.has("level"):
        if not _is_integer_value(data["level"]):
            return false
        level = int(data["level"])
        if level < 1 or level > MAX_PLAYER_LEVEL:
            return false

    if data.has("experience"):
        if not _is_integer_value(data["experience"]):
            return false
        var required_xp := 100 + ((level - 1) * 50)
        if int(data["experience"]) < 0 or int(data["experience"]) >= required_xp:
            return false

    if data.has("player_health"):
        if typeof(data["player_health"]) != TYPE_INT and typeof(data["player_health"]) != TYPE_FLOAT:
            return false
        var current_health := float(data["player_health"])
        var max_health := 100.0 + (float(level - 1) * 10.0)
        if not is_finite(current_health) or current_health < 0.0 or current_health > max_health:
            return false

    if data.has("player_position"):
        if not (data["player_position"] is Dictionary):
            return false
        var position_data: Dictionary = data["player_position"]
        for axis in ["x", "y", "z"]:
            if not position_data.has(axis):
                return false
            var coordinate: Variant = position_data[axis]
            if typeof(coordinate) != TYPE_INT and typeof(coordinate) != TYPE_FLOAT:
                return false
            var numeric_coordinate := float(coordinate)
            if not is_finite(numeric_coordinate) or absf(numeric_coordinate) > 100000.0:
                return false

    if data.has("inventory"):
        if not (data["inventory"] is Array):
            return false
        var inventory: Array = data["inventory"]
        if inventory.size() > MAX_INVENTORY_SLOTS:
            return false
        for entry in inventory:
            if entry == null:
                continue
            if not (entry is Dictionary):
                return false
            var item_data: Dictionary = entry
            if not item_data.has("id") or typeof(item_data["id"]) != TYPE_STRING:
                return false
            if String(item_data["id"]).is_empty() or String(item_data["id"]).length() > 128:
                return false
            var amount: Variant = item_data.get("amount", 1)
            if not _is_integer_value(amount) or int(amount) < 1 or int(amount) > MAX_INVENTORY_STACK:
                return false

    if data.has("quest"):
        if not (data["quest"] is Dictionary):
            return false
        var quest: Dictionary = data["quest"]
        if quest.has("id") and typeof(quest["id"]) != TYPE_STRING:
            return false
        if quest.has("title") and typeof(quest["title"]) != TYPE_STRING:
            return false
        if quest.has("progress"):
            if not _is_integer_value(quest["progress"]):
                return false
            if int(quest["progress"]) < 0 or int(quest["progress"]) > MAX_QUEST_PROGRESS:
                return false
        if quest.has("active") and typeof(quest["active"]) != TYPE_BOOL:
            return false

    if data.has("dialogue"):
        if not (data["dialogue"] is Dictionary):
            return false
        var dialogue: Dictionary = data["dialogue"]
        if dialogue.has("flags"):
            if not (dialogue["flags"] is Dictionary):
                return false
            var flags: Dictionary = dialogue["flags"]
            for flag_name in flags:
                if typeof(flag_name) != TYPE_STRING or typeof(flags[flag_name]) != TYPE_BOOL:
                    return false
    return true



func _is_integer_value(value: Variant) -> bool:
    if typeof(value) == TYPE_INT:
        return true
    if typeof(value) != TYPE_FLOAT:
        return false
    var number := float(value)
    return is_finite(number) and absf(number) <= MAX_ABS_NUMBER and number == floorf(number)


func _is_safe_json_value(value: Variant, depth: int) -> bool:
    if depth > MAX_JSON_DEPTH:
        return false

    match typeof(value):
        TYPE_NIL, TYPE_BOOL, TYPE_INT:
            return true
        TYPE_FLOAT:
            var number := float(value)
            return is_finite(number) and absf(number) <= MAX_ABS_NUMBER
        TYPE_STRING:
            return String(value).length() <= MAX_STRING_LENGTH
        TYPE_ARRAY:
            var array_value: Array = value
            if array_value.size() > MAX_CONTAINER_ITEMS:
                return false
            for item in array_value:
                if not _is_safe_json_value(item, depth + 1):
                    return false
            return true
        TYPE_DICTIONARY:
            var dictionary_value: Dictionary = value
            if dictionary_value.size() > MAX_CONTAINER_ITEMS:
                return false
            for key in dictionary_value:
                if typeof(key) != TYPE_STRING or String(key).length() > 256:
                    return false
                if not _is_safe_json_value(dictionary_value[key], depth + 1):
                    return false
            return true
        _:
            return false


func _file_needs_migration(path: String) -> bool:
    var raw_text := _read_raw_text(path)
    if raw_text.is_empty():
        return false
    var parser := JSON.new()
    if parser.parse(raw_text) != OK or not (parser.data is Dictionary):
        return false
    var raw_data: Dictionary = parser.data
    return not raw_data.has("schema_version") or int(raw_data.get("schema_version", 0)) < CURRENT_SCHEMA_VERSION


func _read_raw_text(path: String) -> String:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return ""
    var text := file.get_as_text()
    file.close()
    return text


func _absolute_path(path: String) -> String:
    return ProjectSettings.globalize_path(path)


func _is_directory(path: String) -> bool:
    return DirAccess.dir_exists_absolute(_absolute_path(path))


func _remove_file_if_present(path: String) -> void:
    if _is_directory(path) or not FileAccess.file_exists(path):
        return
    DirAccess.remove_absolute(_absolute_path(path))
