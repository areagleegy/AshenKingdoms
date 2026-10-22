extends RefCounted
class_name ContentPackageInstaller

const CatalogScript = preload("res://scripts/content/content_catalog.gd")
const STAGING_ROOT := "user://content/staging"
const INSTALLED_ROOT := "user://content/installed"
const MAX_ARCHIVE_BYTES := 2 * 1024 * 1024 * 1024
const MAX_FILES := 10000
const MAX_FILE_BYTES := 512 * 1024 * 1024
const MAX_UNPACKED_BYTES := 4 * 1024 * 1024 * 1024


func verify_archive(archive_path: String, pack_record: Dictionary) -> Dictionary:
	if not FileAccess.file_exists(archive_path):
		return _error("Package archive does not exist.")
	var archive_file := FileAccess.open(archive_path, FileAccess.READ)
	if archive_file == null:
		return _error("Package archive cannot be opened.")
	var file_size := archive_file.get_length()
	archive_file.close()
	if file_size < 1 or file_size > MAX_ARCHIVE_BYTES:
		return _error("Package archive size is outside allowed limits.")
	var expected_archive_size := int(pack_record.get("download_size", -1))
	if expected_archive_size != file_size:
		return _error("Package archive size does not match the catalog.")
	var expected_digest := str(pack_record.get("sha256", "")).to_lower()
	if not _is_sha256(expected_digest) or FileAccess.get_sha256(archive_path).to_lower() != expected_digest:
		return _error("Package archive SHA-256 verification failed.")

	var catalog := CatalogScript.new()
	var files_value: Variant = pack_record.get("files")
	if not files_value is Array or files_value.is_empty() or files_value.size() > MAX_FILES:
		return _error("Package file manifest is invalid.")
	var expected_files: Dictionary = {}
	var total_size := 0
	for item in files_value:
		if not item is Dictionary:
			return _error("Package file manifest contains an invalid record.")
		var record: Dictionary = item
		var path := str(record.get("path", ""))
		var size := int(record.get("size", -1))
		var digest := str(record.get("sha256", "")).to_lower()
		if not catalog.is_safe_relative_path(path) or path.to_lower() == "installed_manifest.json" or not _is_allowed_extension(path):
			return _error("Package file path or extension is not allowed.")
		if expected_files.has(path) or size < 0 or size > MAX_FILE_BYTES or not _is_sha256(digest):
			return _error("Package file record is invalid or duplicated.")
		var provenance_result: Dictionary = catalog.validate_asset_provenance(record)
		if not bool(provenance_result.get("ok", false)):
			return _error("Package file lacks valid license provenance: %s (%s)" % [path, str(provenance_result.get("error", "invalid metadata"))])
		expected_files[path] = {
			"size": size,
			"sha256": digest,
			"author": str(record["author"]).strip_edges(),
			"source_url": str(record["source_url"]),
			"license": str(record["license"]).strip_edges(),
			"license_url": str(record["license_url"]),
			"attribution": str(record["attribution"]).strip_edges(),
			"commercial_use": true,
			"redistribution_allowed": true
		}
		total_size += size
		if total_size > MAX_UNPACKED_BYTES:
			return _error("Package unpacked size exceeds the safety limit.")

	var zip := ZIPReader.new()
	var open_error := zip.open(archive_path)
	if open_error != OK:
		return _error("Package is not a readable ZIP archive.")
	var archive_files := zip.get_files()
	if archive_files.size() != expected_files.size():
		zip.close()
		return _error("Archive contents do not match the catalog manifest.")
	var seen: Dictionary = {}
	for archive_name in archive_files:
		var path := str(archive_name)
		if not catalog.is_safe_relative_path(path) or seen.has(path) or not expected_files.has(path):
			zip.close()
			return _error("Archive contains an unsafe, duplicate, or unlisted path.")
		seen[path] = true
		var bytes: PackedByteArray = zip.read_file(path)
		var expected: Dictionary = expected_files[path]
		if bytes.size() != int(expected["size"]):
			zip.close()
			return _error("File size does not match the catalog: %s" % path)
		if _sha256_bytes(bytes).hex_encode().to_lower() != str(expected["sha256"]):
			zip.close()
			return _error("File SHA-256 verification failed: %s" % path)
	zip.close()
	return {"ok": true, "error": "", "files": expected_files}


func install_archive(archive_path: String, pack_record: Dictionary) -> Dictionary:
	var pack_id := str(pack_record.get("id", ""))
	var version := str(pack_record.get("version", ""))
	if not _is_safe_id(pack_id) or not _is_safe_version(version):
		return _error("Pack ID or version is unsafe.")
	var verification := verify_archive(archive_path, pack_record)
	if not bool(verification.get("ok", false)):
		return verification

	var destination := "%s/%s/%s" % [INSTALLED_ROOT, pack_id, version]
	var destination_absolute := ProjectSettings.globalize_path(destination)
	if DirAccess.dir_exists_absolute(destination_absolute):
		return _error("This package version is already installed.")
	var staging := "%s/%s-%s-%s" % [STAGING_ROOT, pack_id, version, str(randi())]
	var staging_absolute := ProjectSettings.globalize_path(staging)
	if DirAccess.make_dir_recursive_absolute(staging_absolute) != OK:
		return _error("Could not create package staging directory.")

	var zip := ZIPReader.new()
	if zip.open(archive_path) != OK:
		_remove_tree(staging_absolute)
		return _error("Could not reopen verified package archive.")
	for archive_name in zip.get_files():
		var relative_path := str(archive_name)
		var target_path := staging.path_join(relative_path)
		var target_absolute := ProjectSettings.globalize_path(target_path)
		var parent_path := target_absolute.get_base_dir()
		if DirAccess.make_dir_recursive_absolute(parent_path) != OK:
			zip.close()
			_remove_tree(staging_absolute)
			return _error("Could not create package directory.")
		var bytes: PackedByteArray = zip.read_file(relative_path)
		var output := FileAccess.open(target_path, FileAccess.WRITE)
		if output == null:
			zip.close()
			_remove_tree(staging_absolute)
			return _error("Could not write package file.")
		output.store_buffer(bytes)
		output.close()
	zip.close()

	var manifest_file := FileAccess.open(staging.path_join("installed_manifest.json"), FileAccess.WRITE)
	if manifest_file == null:
		_remove_tree(staging_absolute)
		return _error("Could not write installed manifest.")
	manifest_file.store_string(JSON.stringify({
		"id": pack_id,
		"version": version,
		"files": verification["files"]
	}, "\t"))
	manifest_file.close()

	if DirAccess.make_dir_recursive_absolute(destination_absolute.get_base_dir()) != OK:
		_remove_tree(staging_absolute)
		return _error("Could not create installed package directory.")
	var rename_error := DirAccess.rename_absolute(staging_absolute, destination_absolute)
	if rename_error != OK:
		_remove_tree(staging_absolute)
		return _error("Could not atomically promote verified package.")
	return {"ok": true, "error": "", "installed_path": destination}


func remove_installed_pack(pack_id: String, version: String) -> Dictionary:
	if not _is_safe_id(pack_id) or not _is_safe_version(version):
		return _error("Pack ID or version is unsafe.")
	var target := "%s/%s/%s" % [INSTALLED_ROOT, pack_id, version]
	var absolute := ProjectSettings.globalize_path(target)
	if not DirAccess.dir_exists_absolute(absolute):
		return {"ok": true, "error": ""}
	var err := _remove_tree(absolute)
	if err != OK:
		return _error("Could not remove installed package.")
	return {"ok": true, "error": ""}


func _remove_tree(absolute_path: String) -> Error:
	if not DirAccess.dir_exists_absolute(absolute_path):
		return OK
	var directory := DirAccess.open(absolute_path)
	if directory == null:
		return DirAccess.get_open_error()
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child := absolute_path.path_join(entry)
			var remove_error: Error
			if directory.current_is_dir():
				remove_error = _remove_tree(child)
			else:
				remove_error = DirAccess.remove_absolute(child)
			if remove_error != OK:
				directory.list_dir_end()
				return remove_error
		entry = directory.get_next()
	directory.list_dir_end()
	directory = null
	return DirAccess.remove_absolute(absolute_path)


func _is_allowed_extension(path: String) -> bool:
	var allowed := ["glb", "png", "jpg", "jpeg", "webp", "ktx2", "ogg", "wav", "mp3", "json"]
	return allowed.has(path.get_extension().to_lower())


func _is_safe_id(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 122) or code == 95 or code == 45):
			return false
	return true


func _is_safe_version(value: String) -> bool:
	if value.is_empty() or value.length() > 64 or value == "." or value == "..":
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		var allowed := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 46 or code == 95 or code == 45
		if not allowed:
			return false
	return true


func _sha256_bytes(bytes: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return PackedByteArray()
	if context.update(bytes) != OK:
		return PackedByteArray()
	return context.finish()


func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102) or (code >= 65 and code <= 70)):
			return false
	return true


func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
