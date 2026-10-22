extends RefCounted
class_name ContentCatalog

const SCHEMA_VERSION := 2
const MAX_PACKS := 500
const MAX_FILES_PER_PACK := 10000
const MAX_DOWNLOAD_BYTES := 2 * 1024 * 1024 * 1024
const MAX_SINGLE_FILE_BYTES := 512 * 1024 * 1024
const MAX_TOTAL_UNPACKED_BYTES := 4 * 1024 * 1024 * 1024
const ALLOWED_PACK_TYPES := ["character", "world", "equipment", "audio", "language"]
const ALLOWED_EXTENSIONS := [
	"glb", "png", "jpg", "jpeg", "webp", "ktx2",
	"ogg", "wav", "mp3", "json"
]
const SHA256_HEX_LENGTH := 64


func parse_signed_envelope(raw_json: String, public_key_pem: String) -> Dictionary:
	if raw_json.is_empty() or raw_json.length() > 4 * 1024 * 1024:
		return _error("Signed catalog envelope is empty or too large.")
	if public_key_pem.strip_edges().is_empty():
		return _error("Catalog verification key is not configured.")
	var envelope_value: Variant = JSON.parse_string(raw_json)
	if not envelope_value is Dictionary:
		return _error("Signed catalog envelope must be a JSON object.")
	var envelope: Dictionary = envelope_value
	if str(envelope.get("algorithm", "")) != "RSA-SHA256":
		return _error("Unsupported catalog signature algorithm.")
	var payload_b64 := str(envelope.get("payload_base64", ""))
	var signature_b64 := str(envelope.get("signature_base64", ""))
	if payload_b64.is_empty() or signature_b64.is_empty():
		return _error("Signed catalog envelope is incomplete.")
	var payload_bytes: PackedByteArray = Marshalls.base64_to_raw(payload_b64)
	var signature: PackedByteArray = Marshalls.base64_to_raw(signature_b64)
	if payload_bytes.is_empty() or signature.is_empty() or payload_bytes.size() > 2 * 1024 * 1024:
		return _error("Signed catalog payload or signature is invalid.")
	var public_key := CryptoKey.new()
	if public_key.load_from_string(public_key_pem, true) != OK or not public_key.is_public_only():
		return _error("Catalog public key is invalid.")
	var crypto := Crypto.new()
	var payload_hash: PackedByteArray = _sha256_bytes(payload_bytes)
	if not crypto.verify(HashingContext.HASH_SHA256, payload_hash, signature, public_key):
		return _error("Catalog signature verification failed.")
	var payload_value: Variant = JSON.parse_string(payload_bytes.get_string_from_utf8())
	if not payload_value is Dictionary:
		return _error("Signed catalog payload must be a JSON object.")
	var validation := validate_catalog(payload_value)
	if not bool(validation.get("ok", false)):
		return validation
	return {"ok": true, "error": "", "catalog": payload_value}


func validate_catalog(catalog: Variant) -> Dictionary:
	if not catalog is Dictionary:
		return _error("Catalog root must be an object.")
	if int(catalog.get("schema_version", -1)) != SCHEMA_VERSION:
		return _error("Unsupported catalog schema version.")
	var raw_packs: Variant = catalog.get("packs")
	if not raw_packs is Array:
		return _error("Catalog packs must be an array.")
	if raw_packs.size() > MAX_PACKS:
		return _error("Catalog contains too many packs.")

	var packs_by_id: Dictionary = {}
	for raw_pack in raw_packs:
		if not raw_pack is Dictionary:
			return _error("Each pack entry must be an object.")
		var pack: Dictionary = raw_pack
		var pack_id := str(pack.get("id", ""))
		if not _is_safe_id(pack_id):
			return _error("Pack ID is invalid.")
		if packs_by_id.has(pack_id):
			return _error("Duplicate pack ID: %s" % pack_id)
		var pack_result := _validate_pack(pack)
		if not bool(pack_result.get("ok", false)):
			return pack_result
		packs_by_id[pack_id] = pack

	for pack_id in packs_by_id:
		var dependencies: Array = packs_by_id[pack_id].get("dependencies", [])
		for dependency in dependencies:
			if not packs_by_id.has(str(dependency)):
				return _error("Pack %s has missing dependency %s." % [pack_id, dependency])

	var marks: Dictionary = {}
	for pack_id in packs_by_id:
		if _has_dependency_cycle(str(pack_id), packs_by_id, marks):
			return _error("Catalog contains a dependency cycle.")
	return {"ok": true, "error": "", "packs": packs_by_id}


func _validate_pack(pack: Dictionary) -> Dictionary:
	var pack_id := str(pack.get("id", ""))
	var version := str(pack.get("version", ""))
	if not _is_safe_version(version):
		return _error("Pack %s has an invalid version." % pack_id)
	if not ALLOWED_PACK_TYPES.has(str(pack.get("type", ""))):
		return _error("Pack %s has an unsupported type." % pack_id)
	var url := str(pack.get("url", ""))
	if not url.begins_with("https://") or url.length() > 2048:
		return _error("Pack %s must use an HTTPS URL." % pack_id)
	var download_size := int(pack.get("download_size", -1))
	if download_size < 1 or download_size > MAX_DOWNLOAD_BYTES:
		return _error("Pack %s has an invalid download size." % pack_id)
	if not _is_sha256(str(pack.get("sha256", ""))):
		return _error("Pack %s has an invalid SHA-256 digest." % pack_id)

	var dependencies: Variant = pack.get("dependencies", [])
	if not dependencies is Array:
		return _error("Pack %s dependencies must be an array." % pack_id)
	var seen_dependencies: Dictionary = {}
	for dependency in dependencies:
		var dependency_id := str(dependency)
		if not _is_safe_id(dependency_id) or seen_dependencies.has(dependency_id) or dependency_id == pack_id:
			return _error("Pack %s has invalid dependencies." % pack_id)
		seen_dependencies[dependency_id] = true

	var files: Variant = pack.get("files")
	if not files is Array or files.is_empty() or files.size() > MAX_FILES_PER_PACK:
		return _error("Pack %s has an invalid file list." % pack_id)
	var seen_paths: Dictionary = {}
	var unpacked_total: int = 0
	for raw_file in files:
		if not raw_file is Dictionary:
			return _error("Pack %s has an invalid file record." % pack_id)
		var file_record: Dictionary = raw_file
		var path := str(file_record.get("path", ""))
		if not is_safe_relative_path(path) or path.to_lower() == "installed_manifest.json":
			return _error("Pack %s contains an unsafe or reserved path." % pack_id)
		var normalized_path := path.to_lower()
		if seen_paths.has(normalized_path):
			return _error("Pack %s contains duplicate paths." % pack_id)
		seen_paths[normalized_path] = true
		var extension := path.get_extension().to_lower()
		if not ALLOWED_EXTENSIONS.has(extension):
			return _error("Pack %s contains a disallowed file type." % pack_id)
		var file_size := int(file_record.get("size", -1))
		if file_size < 0 or file_size > MAX_SINGLE_FILE_BYTES:
			return _error("Pack %s contains an invalid file size." % pack_id)
		unpacked_total += file_size
		if unpacked_total > MAX_TOTAL_UNPACKED_BYTES:
			return _error("Pack %s exceeds the unpacked size limit." % pack_id)
		if not _is_sha256(str(file_record.get("sha256", ""))):
			return _error("Pack %s contains an invalid file digest." % pack_id)

		var provenance_result := validate_asset_provenance(file_record)
		if not bool(provenance_result.get("ok", false)):
			return _error("Pack %s has invalid asset provenance for %s: %s" % [pack_id, path, str(provenance_result.get("error", "invalid metadata"))])
	return {"ok": true, "error": ""}


func is_safe_relative_path(path: String) -> bool:
	if path.is_empty() or path.length() > 240:
		return false
	if path.begins_with("/") or path.begins_with("\\") or path.contains(":") or path.contains("\\") or path.to_utf8_buffer().has(0):
		return false
	var segments := path.split("/", false)
	if segments.is_empty():
		return false
	for segment in segments:
		if segment.is_empty() or segment == "." or segment == "..":
			return false
		if segment.strip_edges() != segment:
			return false
	return true


func validate_asset_provenance(file_record: Variant) -> Dictionary:
	if not file_record is Dictionary:
		return _error("Asset provenance record must be an object.")
	for field in ["author", "license", "attribution"]:
		var text_value: Variant = file_record.get(field, null)
		if not text_value is String or str(text_value).strip_edges().is_empty():
			return _error("Missing or empty %s field." % field)
	for field in ["source_url", "license_url"]:
		if not _is_http_url(file_record.get(field, null)):
			return _error("Invalid %s; expected HTTP(S) URL without credentials." % field)
	for field in ["commercial_use", "redistribution_allowed"]:
		var permission: Variant = file_record.get(field, null)
		if typeof(permission) != TYPE_BOOL or not permission:
			return _error("Explicit permission %s must be true." % field)
	return {"ok": true, "error": ""}


func _is_http_url(value: Variant) -> bool:
	if not value is String:
		return false
	var url := str(value)
	if url.is_empty() or url.length() > 2048 or url.contains(" ") or url.contains("\\t") or url.contains("\\n"):
		return false
	var scheme_end := url.find("://")
	if scheme_end <= 0:
		return false
	var scheme := url.substr(0, scheme_end).to_lower()
	if scheme != "http" and scheme != "https":
		return false
	var authority := url.substr(scheme_end + 3)
	for delimiter in ["/", "?", "#"]:
		var delimiter_index := authority.find(delimiter)
		if delimiter_index >= 0:
			authority = authority.substr(0, delimiter_index)
	if authority.is_empty() or authority.contains("@") or authority.contains("\\"):
		return false
	return true


func _is_safe_id(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		var allowed := (code >= 48 and code <= 57) or (code >= 97 and code <= 122) or code == 95 or code == 45
		if not allowed:
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
	if value.length() != SHA256_HEX_LENGTH:
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		var is_digit := code >= 48 and code <= 57
		var is_lower_hex := code >= 97 and code <= 102
		var is_upper_hex := code >= 65 and code <= 70
		if not is_digit and not is_lower_hex and not is_upper_hex:
			return false
	return true


func _has_dependency_cycle(pack_id: String, packs_by_id: Dictionary, marks: Dictionary) -> bool:
	var mark := int(marks.get(pack_id, 0))
	if mark == 1:
		return true
	if mark == 2:
		return false
	marks[pack_id] = 1
	for dependency in packs_by_id[pack_id].get("dependencies", []):
		if _has_dependency_cycle(str(dependency), packs_by_id, marks):
			return true
	marks[pack_id] = 2
	return false


func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
