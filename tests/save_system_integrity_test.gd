extends SceneTree

const SaveSystemScript: Script = preload("res://scripts/core/save_system.gd")
const SAVE_PATH: String = "user://savegame.json"
const TEMP_PATH: String = "user://savegame.json.tmp"
const BACKUP_PATH: String = "user://savegame.json.bak"
const BACKUP_TEMP_PATH: String = "user://savegame.json.bak.tmp"
const MANAGED_PATHS: Array[String] = [
    SAVE_PATH,
    TEMP_PATH,
    BACKUP_PATH,
    BACKUP_TEMP_PATH,
]

var _failures: int = 0
var _save_system: Node
var _original_files: Dictionary = {}


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    for path in MANAGED_PATHS:
        if _is_directory(path):
            push_error("Refusing to run save tests because a managed save path is a directory: %s" % path)
            quit(1)
            return

    _snapshot_original_files()
    _save_system = SaveSystemScript.new()
    _save_system.name = "SaveSystemIntegrityTest"
    root.add_child(_save_system)

    _test_normal_save_and_load()
    _test_repeated_save_rotates_backup()
    _test_corrupt_primary_recovers_backup()
    _test_empty_and_malformed_files()
    _test_legacy_schema_migration()
    _test_future_schema_is_rejected()
    _test_invalid_values_preserve_current_save()
    _test_write_failure_preserves_current_save()

    _restore_original_files()
    print("[save-integrity] failures: %d" % _failures)
    quit(1 if _failures > 0 else 0)


func _test_normal_save_and_load() -> void:
    _check(_reset_managed_files(), "managed save files can be reset before the normal case")
    var saved: bool = _save_system.call("save_game", {
        "version": 1,
        "marker": "normal",
        "level": 1,
        "experience": 10,
        "player_health": 85.0,
    })
    _check(saved, "normal save is committed")
    var loaded: Dictionary = _save_system.call("load_game")
    _check(loaded.get("marker", "") == "normal", "normal save loads the same marker")
    _check(int(loaded.get("schema_version", 0)) == 1, "normal save receives schema version 1")
    _check(bool(_save_system.call("has_save")), "has_save sees a validated primary save")


func _test_repeated_save_rotates_backup() -> void:
    _check(_reset_managed_files(), "managed save files can be reset before backup rotation")
    _check(bool(_save_system.call("save_game", {"marker": "previous", "level": 1})), "first save succeeds before rotation")
    _check(bool(_save_system.call("save_game", {"marker": "latest", "level": 1})), "second save replaces the primary")
    _check(FileAccess.file_exists(BACKUP_PATH), "second save preserves a previous valid backup")
    var backup: Dictionary = _read_json_dictionary(BACKUP_PATH)
    _check(backup.get("marker", "") == "previous", "backup contains the previous primary state")
    var latest: Dictionary = _save_system.call("load_game")
    _check(latest.get("marker", "") == "latest", "primary contains the newest committed state")


func _test_corrupt_primary_recovers_backup() -> void:
    _check(_reset_managed_files(), "managed save files can be reset before recovery")
    _check(bool(_save_system.call("save_game", {"marker": "last-good", "level": 1})), "recovery fixture creates the first valid save")
    _check(bool(_save_system.call("save_game", {"marker": "newer", "level": 1})), "recovery fixture rotates the first save")
    _check(_write_raw_text(SAVE_PATH, "{invalid json"), "test writes a corrupt primary fixture")
    var recovered: Dictionary = _save_system.call("load_game")
    _check(recovered.get("marker", "") == "last-good", "corrupt primary falls back to the previous valid backup")
    var restored_primary: Dictionary = _read_json_dictionary(SAVE_PATH)
    _check(restored_primary.get("marker", "") == "last-good", "recovery restores a valid primary save")
    _check(int(restored_primary.get("schema_version", 0)) == 1, "recovered primary carries a supported schema marker")


func _test_empty_and_malformed_files() -> void:
    _check(_reset_managed_files(), "managed save files can be reset before malformed-file cases")
    _check(_write_raw_text(SAVE_PATH, ""), "test creates an empty save file")
    _check(((_save_system.call("load_game")) as Dictionary).is_empty(), "empty save file is rejected without a crash")
    _check(_reset_managed_files(), "empty save fixture can be removed")
    _check(_write_raw_text(SAVE_PATH, "{not valid JSON"), "test creates a malformed JSON fixture")
    _check(((_save_system.call("load_game")) as Dictionary).is_empty(), "malformed JSON returns no game state when no backup exists")
    _check(not bool(_save_system.call("has_save")), "has_save does not treat a malformed-only save as valid")


func _test_legacy_schema_migration() -> void:
    _check(_reset_managed_files(), "managed save files can be reset before migration")
    var legacy_text := JSON.stringify({
        "version": 1,
        "marker": "legacy",
        "level": 2,
        "experience": 100,
        "player_health": 105.0,
    })
    _check(_write_raw_text(SAVE_PATH, legacy_text), "test creates a legacy schema-0 save")
    var loaded: Dictionary = _save_system.call("load_game")
    _check(loaded.get("marker", "") == "legacy", "migration preserves legacy game data")
    _check(int(loaded.get("schema_version", 0)) == 1, "legacy save migrates in memory to schema version 1")
    var persisted: Dictionary = _read_json_dictionary(SAVE_PATH)
    _check(int(persisted.get("schema_version", 0)) == 1, "legacy migration is persisted to the primary save")


func _test_future_schema_is_rejected() -> void:
    _check(_reset_managed_files(), "managed save files can be reset before future-schema test")
    _check(_write_raw_text(SAVE_PATH, JSON.stringify({
        "schema_version": 999,
        "marker": "future",
        "level": 1,
    })), "test writes an unsupported future-schema fixture")
    _check(((_save_system.call("load_game")) as Dictionary).is_empty(), "unsupported future schema is rejected")
    _check(not bool(_save_system.call("has_save")), "unsupported future schema is not advertised as a usable save")
    _check(not bool(_save_system.call("save_game", {
        "schema_version": 999,
        "marker": "should-not-write",
    })), "save writer refuses a future schema version")
    _check(((_save_system.call("load_game")) as Dictionary).is_empty(), "future-schema rejection leaves the original file unmodified")


func _test_invalid_values_preserve_current_save() -> void:
    _check(_reset_managed_files(), "managed save files can be reset before bounds tests")
    _check(bool(_save_system.call("save_game", {"marker": "safe", "level": 1})), "bounds test begins from a known-good save")

    _check(not bool(_save_system.call("save_game", {
        "marker": "bad-position",
        "player_position": {"x": 100001.0, "y": 0.92, "z": 0.0},
    })), "out-of-range player coordinates are rejected")
    _check(not bool(_save_system.call("save_game", {"marker": "bad-level", "level": 0})), "level below the supported minimum is rejected")
    _check(not bool(_save_system.call("save_game", {"marker": "bad-health", "level": 1, "player_health": -1.0})), "negative health is rejected")
    _check(not bool(_save_system.call("save_game", {"marker": "bad-xp", "level": 1, "experience": 100})), "experience beyond the level threshold is rejected")
    _check(not bool(_save_system.call("save_game", {
        "marker": "bad-inventory",
        "inventory": [{"id": "health_potion", "amount": 0}],
    })), "inventory stack sizes below one are rejected")
    var after_rejections: Dictionary = _save_system.call("load_game")
    _check(after_rejections.get("marker", "") == "safe", "rejected values do not replace the last valid primary save")


func _test_write_failure_preserves_current_save() -> void:
    _check(_reset_managed_files(), "managed save files can be reset before simulated write failure")
    _check(bool(_save_system.call("save_game", {"marker": "must-survive", "level": 1})), "write-failure test creates a valid baseline")
    var temp_directory_path := ProjectSettings.globalize_path(TEMP_PATH)
    var mkdir_error: Error = DirAccess.make_dir_absolute(temp_directory_path)
    _check(mkdir_error == OK, "write-failure simulation blocks the temp path with a directory")
    if mkdir_error != OK:
        return

    var failed_write: bool = _save_system.call("save_game", {"marker": "must-not-commit", "level": 1})
    _check(not failed_write, "save reports failure when the temp path cannot be opened as a file")
    var loaded: Dictionary = _save_system.call("load_game")
    _check(loaded.get("marker", "") == "must-survive", "simulated temp-write failure preserves the last good primary")
    var remove_error: Error = DirAccess.remove_absolute(temp_directory_path)
    _check(remove_error == OK, "test removes its temporary directory obstruction")


func _snapshot_original_files() -> void:
    for path in MANAGED_PATHS:
        if FileAccess.file_exists(path):
            var file := FileAccess.open(path, FileAccess.READ)
            if file == null:
                push_error("Could not snapshot pre-existing save file: %s" % path)
                continue
            _original_files[path] = {"exists": true, "text": file.get_as_text()}
            file.close()
        else:
            _original_files[path] = {"exists": false, "text": ""}


func _restore_original_files() -> void:
    for path in MANAGED_PATHS:
        if _is_directory(path):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
        var saved_state: Dictionary = _original_files.get(path, {"exists": false, "text": ""})
        if bool(saved_state.get("exists", false)):
            if not _write_raw_text(path, String(saved_state.get("text", ""))):
                _check(false, "pre-existing file is restored: %s" % path)
        else:
            if FileAccess.file_exists(path):
                var remove_error: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
                _check(remove_error == OK, "test-created file is removed: %s" % path)


func _reset_managed_files() -> bool:
    var succeeded := true
    for path in MANAGED_PATHS:
        if _is_directory(path):
            var remove_error: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
            if remove_error != OK:
                succeeded = false
        elif FileAccess.file_exists(path):
            var remove_error: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
            if remove_error != OK:
                succeeded = false
    return succeeded


func _write_raw_text(path: String, text: String) -> bool:
    if _is_directory(path):
        return false
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(text)
    file.flush()
    var write_error: Error = file.get_error()
    file.close()
    if write_error != OK:
        return false
    return _read_raw_text(path) == text


func _read_raw_text(path: String) -> String:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return ""
    var text := file.get_as_text()
    file.close()
    return text


func _read_json_dictionary(path: String) -> Dictionary:
    var raw_text := _read_raw_text(path)
    if raw_text.is_empty():
        return {}
    var parser := JSON.new()
    if parser.parse(raw_text) != OK or not (parser.data is Dictionary):
        return {}
    return parser.data


func _is_directory(path: String) -> bool:
    return DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, description: String) -> void:
    if condition:
        print("[PASS] %s" % description)
    else:
        _failures += 1
        push_error("[FAIL] %s" % description)
