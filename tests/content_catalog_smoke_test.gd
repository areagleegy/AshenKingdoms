extends SceneTree

const CATALOG_SCRIPT_PATH := "res://scripts/content/content_catalog.gd"
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
			DirAccess.remove_absolute(ProjectSettings.globalize_path(archive_path))

	var content_manager: Node = root.get_node_or_null("ContentManager")
	_check(content_manager != null, "content manager autoload exists")
	if content_manager != null:
		_check(str(content_manager.call("get_catalog_state")) == "not_configured", "base game starts with content downloads disabled when no service is configured")
		_test_content_manager_progress(content_manager)
		var manager_source_file := FileAccess.open("res://scripts/content/content_manager.gd", FileAccess.READ)
		_check(manager_source_file != null, "content manager source is readable for catalog failure regression checks")
		if manager_source_file != null:
			var manager_source := manager_source_file.get_as_text()
			manager_source_file.close()
			_check(manager_source.contains("var previous_ids: Array = _catalog.keys()"), "catalog failure snapshots the previous pack IDs before clearing")
			_check(manager_source.contains("for pack_id in previous_ids:"), "catalog failure emits unavailable state for the previous pack IDs")
	_finish()


func _test_content_manager_progress(content_manager: Node) -> void:
	var request_a := HTTPRequest.new()
	var request_b := HTTPRequest.new()
	var events: Array = []
	var capture_progress := func(pack_id: String, downloaded_bytes: int, total_bytes: int) -> void:
		events.append([pack_id, downloaded_bytes, total_bytes])
	content_manager.download_progress.connect(capture_progress)
	content_manager.set("_downloads", {
		"progress_a": {"request": request_a, "record": {"download_size": 100}},
		"progress_b": {"request": request_b, "record": {"download_size": 200}}
	})
	content_manager.set("_next_progress_msec", 0)
	content_manager.call("_process", 0.0)
	_check(events.size() == 2, "progress is emitted for each active download")
	content_manager.call("_process", 0.0)
	_check(events.size() == 2, "progress signal emission is throttled between 500 ms intervals")
	content_manager.download_progress.disconnect(capture_progress)

	var mutation_events: Array = []
	var clear_downloads_during_signal := func(pack_id: String, downloaded_bytes: int, total_bytes: int) -> void:
		mutation_events.append(pack_id)
		content_manager.set("_downloads", {})
	content_manager.download_progress.connect(clear_downloads_during_signal)
	content_manager.set("_downloads", {
		"cancel_first": {"request": request_a, "record": {"download_size": 100}},
		"cancel_second": {"request": request_b, "record": {"download_size": 200}}
	})
	content_manager.set("_next_progress_msec", 0)
	content_manager.call("_process", 0.0)
	_check(mutation_events.size() == 1, "progress listeners can cancel downloads while iterating a snapshot")
	content_manager.download_progress.disconnect(clear_downloads_during_signal)
	content_manager.set("_downloads", {})
	request_a.free()
	request_b.free()


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
