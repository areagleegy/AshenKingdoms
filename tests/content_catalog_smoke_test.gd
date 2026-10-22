extends SceneTree

const CATALOG_SCRIPT_PATH := "res://scripts/content/content_catalog.gd"
const CONTENT_MANAGER_SCRIPT_PATH := "res://scripts/content/content_manager.gd"
var _failures := 0
var _catalog_script: Script
var _catalog: RefCounted


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_catalog_script = load(CATALOG_SCRIPT_PATH) as Script
	_check(_catalog_script != null, "content catalog script exists and loads")
	if _catalog_script == null:
		_finish()
		return
	_catalog = _catalog_script.new() as RefCounted
	_check(_catalog != null, "content catalog can be instantiated")
	if _catalog == null:
		_finish()
		return

	var valid_catalog := {
		"schema_version": 1,
		"packs": [{
			"id": "ashen_outskirts",
			"version": "1.0.0",
			"type": "world",
			"url": "https://content.example.invalid/packs/ashen_outskirts.zip",
			"download_size": 128,
			"sha256": "a".repeat(64),
			"files": [{
				"path": "world.glb",
				"size": 64,
				"sha256": "b".repeat(64)
			}],
			"dependencies": []
		}]
	}
	var valid_result: Dictionary = _catalog.call("validate_catalog", valid_catalog)
	_check(bool(valid_result.get("ok", false)), "valid catalog is accepted")
	_check(not bool(_catalog.call("parse_signed_envelope", "{}", "").get("ok", true)), "remote catalog fails closed when no public key is configured")
	var private_key: CryptoKey = Crypto.new().generate_rsa(2048)
	var payload_text := JSON.stringify(valid_catalog)
	var payload_bytes := payload_text.to_utf8_buffer()
	var signature := Crypto.new().sign(HashingContext.HASH_SHA256, _sha256_bytes(payload_bytes), private_key)
	var signed_envelope := JSON.stringify({
		"algorithm": "RSA-SHA256",
		"payload_base64": Marshalls.raw_to_base64(payload_bytes),
		"signature_base64": Marshalls.raw_to_base64(signature)
	})
	var signed_result: Dictionary = _catalog.call("parse_signed_envelope", signed_envelope, private_key.save_to_string(true))
	_check(bool(signed_result.get("ok", false)), "catalog with a valid RSA-SHA256 signature is accepted")
	var tampered_value: Dictionary = JSON.parse_string(signed_envelope)
	tampered_value["signature_base64"] = Marshalls.raw_to_base64(_sha256_bytes(payload_bytes))
	var tampered_envelope := JSON.stringify(tampered_value)
	_check(not bool(_catalog.call("parse_signed_envelope", tampered_envelope, private_key.save_to_string(true)).get("ok", true)), "tampered signed catalog is rejected")

	var duplicate_catalog: Dictionary = valid_catalog.duplicate(true)
	duplicate_catalog["packs"].append((valid_catalog["packs"][0] as Dictionary).duplicate(true))
	_check(not bool(_catalog.call("validate_catalog", duplicate_catalog).get("ok", true)), "duplicate pack IDs are rejected")

	var insecure_catalog: Dictionary = valid_catalog.duplicate(true)
	insecure_catalog["packs"][0]["url"] = "http://content.example.invalid/packs/world.zip"
	_check(not bool(_catalog.call("validate_catalog", insecure_catalog).get("ok", true)), "non-HTTPS package URLs are rejected")

	var traversal_catalog: Dictionary = valid_catalog.duplicate(true)
	traversal_catalog["packs"][0]["files"][0]["path"] = "../outside.cfg"
	_check(not bool(_catalog.call("validate_catalog", traversal_catalog).get("ok", true)), "path traversal in file manifest is rejected")

	var executable_catalog: Dictionary = valid_catalog.duplicate(true)
	executable_catalog["packs"][0]["files"][0]["path"] = "scripts/remote.gd"
	_check(not bool(_catalog.call("validate_catalog", executable_catalog).get("ok", true)), "executable scripts are rejected as pack content")

	var oversized_catalog: Dictionary = valid_catalog.duplicate(true)
	oversized_catalog["packs"][0]["download_size"] = 999999999999
	_check(not bool(_catalog.call("validate_catalog", oversized_catalog).get("ok", true)), "unbounded download sizes are rejected")

	var bad_digest_catalog: Dictionary = valid_catalog.duplicate(true)
	bad_digest_catalog["packs"][0]["sha256"] = "not-a-sha256"
	_check(not bool(_catalog.call("validate_catalog", bad_digest_catalog).get("ok", true)), "malformed SHA-256 digests are rejected")

	var missing_dependency_catalog: Dictionary = valid_catalog.duplicate(true)
	missing_dependency_catalog["packs"][0]["dependencies"] = ["missing_pack"]
	_check(not bool(_catalog.call("validate_catalog", missing_dependency_catalog).get("ok", true)), "missing dependencies are rejected")

	var cyclic_catalog: Dictionary = valid_catalog.duplicate(true)
	var second_pack: Dictionary = (valid_catalog["packs"][0] as Dictionary).duplicate(true)
	second_pack["id"] = "second_pack"
	second_pack["dependencies"] = ["ashen_outskirts"]
	cyclic_catalog["packs"][0]["dependencies"] = ["second_pack"]
	cyclic_catalog["packs"].append(second_pack)
	_check(not bool(_catalog.call("validate_catalog", cyclic_catalog).get("ok", true)), "cyclic dependencies are rejected")

	_check(not bool(_catalog.call("is_safe_relative_path", "../escape.txt")), "parent traversal is rejected by path helper")
	_check(not bool(_catalog.call("is_safe_relative_path", "/absolute/path.txt")), "absolute paths are rejected by path helper")
	_check(bool(_catalog.call("is_safe_relative_path", "characters/hero.glb")), "nested relative asset path is accepted")
	_check(not bool(_catalog.call("is_safe_relative_path", "characters//hero.glb")), "empty path segments are rejected")
	_check(not bool(_catalog.call("is_safe_relative_path", "characters/hero.glb/")), "trailing path separators are rejected")
	_check(not bool(_catalog.call("is_safe_relative_path", "characters/hero.glb.")), "trailing-dot filenames are rejected for cross-platform safety")
	_check(not bool(_catalog.call("is_safe_relative_path", "characters/CON.png")), "Windows reserved device filenames are rejected even with an extension")
	_check(not bool(_catalog.call("is_safe_relative_path", "characters/AUX.json")), "Windows auxiliary device filenames are rejected")
	_check(not bool(_catalog.call("is_safe_relative_path", "characters/bad?.glb")), "Windows-invalid filename characters are rejected")
	_check(not bool(_catalog.call("is_safe_relative_path", "characters/" + String.chr(1) + "bad.glb")), "control characters are rejected from asset paths")

	var installer_script: Script = load("res://scripts/content/content_package_installer.gd") as Script
	_check(installer_script != null, "content package installer script exists and loads")
	if installer_script != null:
		var installer: RefCounted = installer_script.new()
		_check(not bool(installer.call("verify_archive", "user://missing-content-pack.zip", valid_catalog["packs"][0]).get("ok", true)), "missing package archives are rejected")
		_check(not bool(installer.call("remove_installed_pack", "../outside", "1.0.0").get("ok", true)), "unsafe package IDs cannot delete files")
		var archive_path := "user://content_catalog_smoke.zip"
		var asset_bytes := "test-glb-data".to_utf8_buffer()
		var writer := ZIPPacker.new()
		var zip_error := writer.open(archive_path)
		_check(zip_error == OK, "test ZIP archive can be created")
		if zip_error == OK:
			writer.start_file("world.glb")
			writer.write_file(asset_bytes)
			writer.close_file()
			writer.close()
			var archive_file := FileAccess.open(archive_path, FileAccess.READ)
			var archive_size := archive_file.get_length() if archive_file != null else 0
			if archive_file != null:
				archive_file.close()
			var test_pack := {
				"id": "content_smoke_pack",
				"version": "1.0.0",
				"download_size": archive_size,
				"sha256": FileAccess.get_sha256(archive_path),
				"files": [{
					"path": "world.glb",
					"size": asset_bytes.size(),
					"sha256": _sha256_bytes(asset_bytes).hex_encode()
				}]
			}
			var verified: Dictionary = installer.call("verify_archive", archive_path, test_pack)
			_check(bool(verified.get("ok", false)), "valid ZIP package and per-file digests are accepted")
			var installed: Dictionary = installer.call("install_archive", archive_path, test_pack)
			_check(bool(installed.get("ok", false)), "verified package installs into private content storage")
			if bool(installed.get("ok", false)):
				_check(FileAccess.file_exists(str(installed["installed_path"]).path_join("world.glb")), "installed package asset exists")
				installer.call("remove_installed_pack", "content_smoke_pack", "1.0.0")
			var tampered_pack: Dictionary = test_pack.duplicate(true)
			tampered_pack["sha256"] = "f".repeat(64)
			_check(not bool(installer.call("verify_archive", archive_path, tampered_pack).get("ok", true)), "package archive digest mismatch is rejected")

			# Case-only path collisions work on Linux but can alias to one file on
			# case-insensitive Windows/macOS file systems; reject them before install.
			var collision_archive := "user://content_catalog_case_collision.zip"
			var collision_writer := ZIPPacker.new()
			var collision_open_error := collision_writer.open(collision_archive)
			_check(collision_open_error == OK, "case-collision ZIP archive can be created")
			if collision_open_error == OK:
				collision_writer.start_file("world.glb")
				collision_writer.write_file(asset_bytes)
				collision_writer.close_file()
				collision_writer.start_file("WORLD.glb")
				collision_writer.write_file(asset_bytes)
				collision_writer.close_file()
				collision_writer.close()
				var collision_file := FileAccess.open(collision_archive, FileAccess.READ)
				var collision_size := collision_file.get_length() if collision_file != null else 0
				if collision_file != null:
					collision_file.close()
				var collision_pack := test_pack.duplicate(true)
				collision_pack["download_size"] = collision_size
				collision_pack["sha256"] = FileAccess.get_sha256(collision_archive)
				collision_pack["files"] = [
					{"path": "world.glb", "size": asset_bytes.size(), "sha256": _sha256_bytes(asset_bytes).hex_encode()},
					{"path": "WORLD.glb", "size": asset_bytes.size(), "sha256": _sha256_bytes(asset_bytes).hex_encode()}
				]
				_check(
					not bool(installer.call("verify_archive", collision_archive, collision_pack).get("ok", true)),
					"installer rejects case-insensitive path collisions before extraction"
				)
				DirAccess.remove_absolute(ProjectSettings.globalize_path(collision_archive))

			DirAccess.remove_absolute(ProjectSettings.globalize_path(archive_path))

	var content_manager: Node = root.get_node_or_null("ContentManager")
	_check(content_manager != null, "content manager autoload exists")
	if content_manager != null:
		_check(str(content_manager.call("get_catalog_state")) == "not_configured", "base game starts with content downloads disabled when no service is configured")

		var unavailable_states: Array[Dictionary] = []
		content_manager.pack_state_changed.connect(
			func(pack_id: String, state: String, details: Dictionary) -> void:
				unavailable_states.append({"id": pack_id, "state": state, "details": details})
		)
		content_manager.set("_catalog", {"stale_pack": {"id": "stale_pack"}})
		content_manager.call("_fail_catalog", "Expected smoke-test catalog failure.")
		_check(content_manager.call("get_catalog").is_empty(), "catalog failure clears the active catalog")
		_check(
			unavailable_states.size() == 1
			and str(unavailable_states[0].get("id", "")) == "stale_pack"
			and str(unavailable_states[0].get("state", "")) == "unavailable",
			"catalog failure marks previously listed packs unavailable before discarding their IDs"
		)

	_test_oversized_registry_is_rejected()
	_finish()


func _test_oversized_registry_is_rejected() -> void:
	const REGISTRY_PATH := "user://content/registry.json"
	var had_original := FileAccess.file_exists(REGISTRY_PATH)
	var original_contents := ""
	if had_original:
		var original_file := FileAccess.open(REGISTRY_PATH, FileAccess.READ)
		if original_file == null:
			_check(false, "existing content registry can be preserved before test")
			return
		original_contents = original_file.get_as_text()
		original_file.close()

	var content_root := ProjectSettings.globalize_path("user://content")
	if DirAccess.make_dir_recursive_absolute(content_root) != OK:
		_check(false, "content registry test directory can be prepared")
		return
	var fixture := FileAccess.open(REGISTRY_PATH, FileAccess.WRITE)
	if fixture == null:
		_check(false, "oversized registry fixture can be created")
		_restore_registry_fixture(had_original, original_contents, REGISTRY_PATH)
		return
	fixture.store_string("x".repeat(1024 * 1024 + 1))
	fixture.flush()
	var write_error: Error = fixture.get_error()
	fixture.close()
	_check(write_error == OK, "oversized registry fixture is fully written")

	var manager_script := load(CONTENT_MANAGER_SCRIPT_PATH) as Script
	_check(manager_script != null, "content manager source loads for isolated registry test")
	if manager_script != null:
		var isolated_manager := manager_script.new() as Node
		isolated_manager.call("_load_registry")
		var installed_value = isolated_manager.call("get_installed_packs")
		_check(
			installed_value is Dictionary and installed_value.is_empty(),
			"content manager rejects a registry larger than the configured read limit"
		)
		isolated_manager.free()

	_restore_registry_fixture(had_original, original_contents, REGISTRY_PATH)


func _restore_registry_fixture(had_original: bool, original_contents: String, path: String) -> void:
	if not had_original:
		if FileAccess.file_exists(path):
			var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			_check(remove_error == OK, "temporary oversized registry fixture is removed")
		else:
			_check(true, "temporary oversized registry fixture is absent")
		return
	var output := FileAccess.open(path, FileAccess.WRITE)
	if output == null:
		_check(false, "original content registry can be restored")
		return
	output.store_string(original_contents)
	output.flush()
	var write_error: Error = output.get_error()
	output.close()
	_check(write_error == OK, "original content registry is restored")


func _sha256_bytes(bytes: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish()


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		push_error("[FAIL] %s" % description)


func _finish() -> void:
	print("[content] failures: %d" % _failures)
	quit(1 if _failures > 0 else 0)
