extends Node
class_name ContentManager

signal catalog_updated(catalog: Dictionary)
signal pack_state_changed(pack_id: String, state: String, details: Dictionary)
signal download_progress(pack_id: String, downloaded_bytes: int, total_bytes: int)

const CatalogScript = preload("res://scripts/content/content_catalog.gd")
const InstallerScript = preload("res://scripts/content/content_package_installer.gd")
const REGISTRY_PATH := "user://content/registry.json"
const REGISTRY_TEMP_PATH := "user://content/registry.tmp"
const DOWNLOAD_ROOT := "user://content/downloads"
const MAX_CATALOG_BYTES := 4 * 1024 * 1024

var _catalog: Dictionary = {}
var _installed: Dictionary = {}
var _downloads: Dictionary = {}
var _active_references: Dictionary = {}
var _catalog_request: HTTPRequest
var _catalog_state := "not_configured"
var _last_error := ""


func _ready() -> void:
	_load_registry()
	var configured_url := str(ProjectSettings.get_setting("ashen/content/catalog_url", ""))
	if configured_url.is_empty():
		_catalog_state = "not_configured"
		_last_error = "Content catalog URL is not configured."
	else:
		_catalog_state = "not_loaded"


func get_catalog_state() -> String:
	return _catalog_state


func get_last_error() -> String:
	return _last_error


func get_catalog() -> Dictionary:
	return _catalog.duplicate(true)


func get_installed_packs() -> Dictionary:
	return _installed.duplicate(true)


func refresh_catalog() -> void:
	var catalog_url := str(ProjectSettings.get_setting("ashen/content/catalog_url", "")).strip_edges()
	var public_key := str(ProjectSettings.get_setting("ashen/content/catalog_public_key", "")).strip_edges()
	if not catalog_url.begins_with("https://") or catalog_url.length() > 2048:
		_fail_catalog("A valid HTTPS content catalog URL is not configured.")
		return
	if public_key.is_empty():
		_fail_catalog("The catalog verification public key is not configured.")
		return
	if _catalog_request != null and is_instance_valid(_catalog_request):
		_catalog_request.cancel_request()
		_catalog_request.queue_free()
	_catalog_request = HTTPRequest.new()
	_catalog_request.timeout = 30.0
	_catalog_request.max_redirects = 2
	_catalog_request.body_size_limit = MAX_CATALOG_BYTES
	add_child(_catalog_request)
	_catalog_request.request_completed.connect(_on_catalog_request_completed)
	_catalog_state = "loading"
	_last_error = ""
	var request_error := _catalog_request.request(catalog_url)
	if request_error != OK:
		_fail_catalog("Could not start catalog request (error %d)." % request_error)


func download_pack(pack_id: String) -> Error:
	if not _is_safe_id(pack_id):
		_emit_pack_state(pack_id, "failed", {"error": "Invalid pack ID."})
		return ERR_INVALID_PARAMETER
	if _downloads.has(pack_id):
		return ERR_BUSY
	if not _catalog.has(pack_id):
		_emit_pack_state(pack_id, "failed", {"error": "Pack is not present in the verified catalog."})
		return ERR_DOES_NOT_EXIST
	var pack_record: Dictionary = _catalog[pack_id]
	var download_root_absolute := ProjectSettings.globalize_path(DOWNLOAD_ROOT)
	if DirAccess.make_dir_recursive_absolute(download_root_absolute) != OK:
		_emit_pack_state(pack_id, "failed", {"error": "Could not prepare private download storage."})
		return ERR_CANT_CREATE
	var temporary_path := "%s/%s-%s.part" % [DOWNLOAD_ROOT, pack_id, str(randi())]
	var request := HTTPRequest.new()
	request.timeout = 60.0
	request.max_redirects = 2
	request.download_file = temporary_path
	add_child(request)
	var state := {"request": request, "path": temporary_path, "record": pack_record.duplicate(true)}
	_downloads[pack_id] = state
	request.request_completed.connect(_on_download_completed.bind(pack_id, pack_record.duplicate(true), temporary_path))
	request.downloaded_bytes = 0
	_emit_pack_state(pack_id, "downloading", {"download_size": int(pack_record.get("download_size", 0))})
	var request_error := request.request(str(pack_record.get("url", "")))
	if request_error != OK:
		_cleanup_download(pack_id, temporary_path)
		_emit_pack_state(pack_id, "failed", {"error": "Could not start package download (error %d)." % request_error})
		return request_error
	return OK


func cancel_download(pack_id: String) -> void:
	if not _downloads.has(pack_id):
		return
	var state: Dictionary = _downloads[pack_id]
	var request: HTTPRequest = state.get("request")
	if request != null and is_instance_valid(request):
		request.cancel_request()
	var temporary_path := str(state.get("path", ""))
	_cleanup_download(pack_id, temporary_path)
	_emit_pack_state(pack_id, "cancelled", {})


func is_pack_installed(pack_id: String) -> bool:
	return _installed.has(pack_id) and _installed[pack_id] is Dictionary


func get_installed_pack_path(pack_id: String) -> String:
	if not is_pack_installed(pack_id):
		return ""
	return str(_installed[pack_id].get("path", ""))


func acquire_pack(pack_id: String) -> bool:
	if not is_pack_installed(pack_id):
		return false
	_active_references[pack_id] = int(_active_references.get(pack_id, 0)) + 1
	return true


func release_pack(pack_id: String) -> void:
	if not _active_references.has(pack_id):
		return
	var count := int(_active_references[pack_id]) - 1
	if count <= 0:
		_active_references.erase(pack_id)
	else:
		_active_references[pack_id] = count


func delete_pack(pack_id: String) -> Dictionary:
	if not _is_safe_id(pack_id):
		return _error("Invalid pack ID.")
	if not is_pack_installed(pack_id):
		return {"ok": true, "error": ""}
	if int(_active_references.get(pack_id, 0)) > 0:
		return _error("Package is currently in use.")
	for installed_id in _installed:
		if str(installed_id) == pack_id:
			continue
		var installed_record: Dictionary = _installed[installed_id]
		var catalog_record: Dictionary = _catalog.get(str(installed_id), {})
		var dependencies: Array = catalog_record.get("dependencies", [])
		if dependencies.has(pack_id):
			return _error("Package is required by installed package %s." % installed_id)
	var record: Dictionary = _installed[pack_id]
	var path := str(record.get("path", ""))
	if path.is_empty():
		return _error("Installed package registry entry is invalid.")
	var installer := InstallerScript.new()
	var result: Dictionary = installer.remove_installed_pack(pack_id, str(record.get("version", "")))
	if not bool(result.get("ok", false)):
		return result
	_installed.erase(pack_id)
	if not _save_registry():
		_emit_pack_state(pack_id, "failed", {"error": "Package removed, but registry could not be saved."})
		return _error("Could not save package registry after deletion.")
	_emit_pack_state(pack_id, "not_installed", {})
	return {"ok": true, "error": ""}


func _on_catalog_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _catalog_request != null and is_instance_valid(_catalog_request):
		_catalog_request.queue_free()
	_catalog_request = null
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300 or body.is_empty() or body.size() > MAX_CATALOG_BYTES:
		_fail_catalog("Catalog download failed (result %d, HTTP %d)." % [result, response_code])
		return
	var public_key := str(ProjectSettings.get_setting("ashen/content/catalog_public_key", "")).strip_edges()
	var catalog_parser := CatalogScript.new()
	var parsed: Dictionary = catalog_parser.parse_signed_envelope(body.get_string_from_utf8(), public_key)
	if not bool(parsed.get("ok", false)):
		_fail_catalog(str(parsed.get("error", "Catalog validation failed.")))
		return
	_catalog = parsed["catalog"].get("packs", []).reduce(func(acc: Dictionary, pack: Dictionary) -> Dictionary:
		acc[str(pack["id"])] = pack
		return acc
	, {})
	_catalog_state = "ready"
	_last_error = ""
	catalog_updated.emit(_catalog.duplicate(true))
	for pack_id in _catalog:
		_emit_pack_state(str(pack_id), "installed" if is_pack_installed(str(pack_id)) else "available", {})


func _on_download_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray, pack_id: String, pack_record: Dictionary, temporary_path: String) -> void:
	var request_state: Dictionary = _downloads.get(pack_id, {})
	var request: HTTPRequest = request_state.get("request")
	if request != null and is_instance_valid(request):
		request.queue_free()
	_downloads.erase(pack_id)
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300 or not FileAccess.file_exists(temporary_path):
		_remove_file(temporary_path)
		_emit_pack_state(pack_id, "failed", {"error": "Package download failed (result %d, HTTP %d)." % [result, response_code]})
		return
	_emit_pack_state(pack_id, "verifying", {})
	var installer := InstallerScript.new()
	var installed: Dictionary = installer.install_archive(temporary_path, pack_record)
	_remove_file(temporary_path)
	if not bool(installed.get("ok", false)):
		_emit_pack_state(pack_id, "failed", {"error": str(installed.get("error", "Package installation failed."))})
		return
	_installed[pack_id] = {
		"id": pack_id,
		"version": str(pack_record.get("version", "")),
		"path": str(installed.get("installed_path", "")),
		"installed_at": int(Time.get_unix_time_from_system())
	}
	if not _save_registry():
		_emit_pack_state(pack_id, "failed", {"error": "Installed package could not be registered; please retry."})
		return
	_emit_pack_state(pack_id, "installed", {"path": _installed[pack_id]["path"]})


func _load_registry() -> void:
	_installed.clear()
	if not FileAccess.file_exists(REGISTRY_PATH):
		return
	var file := FileAccess.open(REGISTRY_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or not parsed.get("packs", {}) is Dictionary:
		return
	var candidate: Dictionary = parsed["packs"]
	for raw_id in candidate:
		var pack_id := str(raw_id)
		var record: Variant = candidate[raw_id]
		if not _is_safe_id(pack_id) or not record is Dictionary:
			continue
		var path := str(record.get("path", ""))
		var version := str(record.get("version", ""))
		if path != "%s/%s/%s" % [InstallerScript.INSTALLED_ROOT, pack_id, version]:
			continue
		var manifest_path := path.path_join("installed_manifest.json")
		if FileAccess.file_exists(manifest_path):
			_installed[pack_id] = record


func _save_registry() -> bool:
	var root_absolute := ProjectSettings.globalize_path("user://content")
	if DirAccess.make_dir_recursive_absolute(root_absolute) != OK:
		return false
	var file := FileAccess.open(REGISTRY_TEMP_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": 1, "packs": _installed}, "\t"))
	file.close()
	var temporary_absolute := ProjectSettings.globalize_path(REGISTRY_TEMP_PATH)
	var destination_absolute := ProjectSettings.globalize_path(REGISTRY_PATH)
	if FileAccess.file_exists(REGISTRY_PATH):
		if DirAccess.remove_absolute(destination_absolute) != OK:
			_remove_file(REGISTRY_TEMP_PATH)
			return false
	return DirAccess.rename_absolute(temporary_absolute, destination_absolute) == OK


func _cleanup_download(pack_id: String, temporary_path: String) -> void:
	var state: Dictionary = _downloads.get(pack_id, {})
	var request: HTTPRequest = state.get("request")
	if request != null and is_instance_valid(request):
		request.queue_free()
	_downloads.erase(pack_id)
	_remove_file(temporary_path)


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _fail_catalog(message: String) -> void:
	_catalog_state = "error"
	_last_error = message
	push_warning(message)
	catalog_updated.emit({})
	for pack_id in _catalog:
		_emit_pack_state(str(pack_id), "unavailable", {"error": message})


func _emit_pack_state(pack_id: String, state: String, details: Dictionary) -> void:
	pack_state_changed.emit(pack_id, state, details.duplicate(true))


func _is_safe_id(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 122) or code == 95 or code == 45):
			return false
	return true


func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
