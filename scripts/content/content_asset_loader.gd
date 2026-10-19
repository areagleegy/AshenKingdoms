extends RefCounted
class_name ContentAssetLoader

const CatalogScript = preload("res://scripts/content/content_catalog.gd")
const MANIFEST_NAME := "installed_manifest.json"


func load_gltf(pack_id: String, relative_path: String) -> Dictionary:
	var resolved := _resolve_verified_path(pack_id, relative_path, ["glb"])
	if not bool(resolved.get("ok", false)):
		return resolved
	var absolute_path := ProjectSettings.globalize_path(str(resolved["path"]))
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var append_error := document.append_from_file(absolute_path, state, 0, absolute_path.get_base_dir())
	if append_error != OK:
		return _error("Could not parse GLB/glTF asset (error %d)." % append_error)
	var scene := document.generate_scene(state)
	if scene == null:
		return _error("Could not generate a scene from the verified asset.")
	return {"ok": true, "error": "", "node": scene}


func load_audio_stream(pack_id: String, relative_path: String) -> Dictionary:
	var resolved := _resolve_verified_path(pack_id, relative_path, ["ogg", "wav", "mp3"])
	if not bool(resolved.get("ok", false)):
		return resolved
	var absolute_path := ProjectSettings.globalize_path(str(resolved["path"]))
	var extension := relative_path.get_extension().to_lower()
	var stream: Resource
	match extension:
		"ogg":
			stream = AudioStreamOggVorbis.load_from_file(absolute_path)
		"wav":
			stream = AudioStreamWAV.load_from_file(absolute_path)
		"mp3":
			stream = AudioStreamMP3.load_from_file(absolute_path)
	if stream == null:
		return _error("Could not load the audio asset.")
	return {"ok": true, "error": "", "stream": stream}


func _resolve_verified_path(pack_id: String, relative_path: String, allowed_extensions: Array) -> Dictionary:
	var manager := Engine.get_main_loop().root.get_node_or_null("ContentManager") if Engine.get_main_loop() is SceneTree else null
	if manager == null or not manager.has_method("get_installed_pack_path"):
		return _error("Content manager is unavailable.")
	if not manager.call("is_pack_installed", pack_id):
		return _error("Requested content pack is not installed.")
	var catalog := CatalogScript.new()
	if not catalog.is_safe_relative_path(relative_path):
		return _error("Asset path is unsafe.")
	if not allowed_extensions.has(relative_path.get_extension().to_lower()):
		return _error("Asset extension is not allowed.")
	var pack_root := str(manager.call("get_installed_pack_path", pack_id))
	var manifest_path := pack_root.path_join(MANIFEST_NAME)
	var manifest_file := FileAccess.open(manifest_path, FileAccess.READ)
	if manifest_file == null:
		return _error("Installed content manifest is missing.")
	var manifest: Variant = JSON.parse_string(manifest_file.get_as_text())
	manifest_file.close()
	if not manifest is Dictionary or str(manifest.get("id", "")) != pack_id:
		return _error("Installed content manifest is invalid.")
	var files: Variant = manifest.get("files", {})
	if not files is Dictionary or not files.has(relative_path):
		return _error("Asset is not listed in the verified package manifest.")
	var record: Variant = files[relative_path]
	if not record is Dictionary:
		return _error("Asset manifest record is invalid.")
	var resolved_path := pack_root.path_join(relative_path)
	if not FileAccess.file_exists(resolved_path):
		return _error("Installed asset file is missing.")
	var expected_size := int(record.get("size", -1))
	var file := FileAccess.open(resolved_path, FileAccess.READ)
	if file == null:
		return _error("Installed asset cannot be opened.")
	var actual_size := file.get_length()
	file.close()
	if actual_size != expected_size:
		return _error("Installed asset size no longer matches the manifest.")
	var expected_digest := str(record.get("sha256", "")).to_lower()
	if FileAccess.get_sha256(resolved_path).to_lower() != expected_digest:
		return _error("Installed asset SHA-256 no longer matches the manifest.")
	return {"ok": true, "error": "", "path": resolved_path}


func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
