# Optional Content Packs Implementation Plan

> **Document status:** Historical implementation plan, not a live checklist. The repository now contains initial catalog validation, packaging/signing tools, a content manager, and smoke tests. Some checkboxes below record the original test-first plan and may not have been backfilled after implementation. Use `content/README.md`, `docs/PROJECT_STATUS_AR.md`, and `docs/TEST_PLAN.md` for current behavior and remaining acceptance work.

> **For agentic workers:** Execute this plan task-by-task and keep each step independently reviewable. Tasks use checkbox syntax. Use test-driven development: write the failing test first, demonstrate failure, implement the smallest fix, and rerun all relevant checks.

**Goal:** Deliver an Android-first optional content-pack system for AshenKingdoms that keeps the core game playable offline, lets players download/verify/install/update/delete data-only packs, and loads installed assets on demand.

**Architecture:** Keep gameplay code and executable logic inside the APK. An autoload `ContentManager` coordinates a signed catalog, HTTPS downloads into temporary files, digest and archive validation, safe atomic installation under the app's private `user://` storage, dependency-aware deletion, and a lightweight in-game library. Use data-only ZIP packs containing GLB/glTF, audio, textures, and JSON; reject scripts, native code, unsafe paths, unlisted files, and oversized archives. If production signing configuration or a reachable content catalog is absent, fail closed with a clear UI state and keep offline base gameplay working.

**Tech Stack:** Godot 4.6 / GDScript, Godot `HTTPRequest`, `Crypto` / `HashingContext`, `ZIPReader`, `GLTFDocument` / `GLTFState`, existing custom SceneTree smoke-test harness, GitHub Actions. No runtime third-party dependency by default.

**Spec:** `docs/superpowers/specs/2026-10-19-optional-content-packs-design.md`

## Global Constraints

- Godot version remains 4.6 and renderer remains Compatibility unless device measurements justify a separate decision.
- Core gameplay must start and be playable without a network connection or any optional pack.
- No remotely downloaded GDScript, DLL, native library, or other executable code.
- HTTPS only; production catalog signature verification must fail closed when the public key or valid signature is unavailable.
- SHA-256, advertised sizes, archive entry count, per-file size, total uncompressed size, and expansion ratio must be bounded before installation.
- Archive paths must remain inside the selected temporary pack root; reject absolute paths, traversal segments, duplicate normalized paths, and unsupported extensions.
- Download and extraction use temporary files and atomic promotion; failed updates must not replace a good installed version.
- Store packs in private app storage; do not request broad external-storage permissions.
- No fake endpoint, fake package, or claim of verified Android hardware behavior.
- Preserve the exact existing export preset names `Android` and `Web`.
- Keep private signing keys and Android signing credentials out of Git.

## Review Focus

- Missing, malformed, stale, or unsigned catalog → show an actionable error, not a crash or unverified fallback.
- Corrupted or truncated package, altered SHA-256, or wrong advertised size → do not install or overwrite a previous valid version.
- ZIP traversal, absolute path, duplicate paths, excessive entries, or expansion bomb → abort safely without writing outside staging.
- Interrupted download, HTTP error, no network, or low storage → retain the prior installed pack and clean up or safely resume partial files.
- Pack dependency is missing/in use → block unsafe activation/deletion and explain which pack is required.
- Save references an unavailable content ID → preserve the save and allow base game startup with a prompt to install the missing pack.

---

## File Map

- Create `scripts/content/content_catalog.gd`: signed-envelope parsing, schema checks, and catalog lookups.
- Create `scripts/content/content_package_installer.gd`: digest checks, bounded ZIP validation, safe extraction, atomic install/rollback, and manifest validation.
- Create `scripts/content/content_manager.gd`: autoload API, catalog state, user-triggered downloads, install/update/remove, dependencies, progress and status signals.
- Create `scripts/content/content_asset_loader.gd`: load approved local GLB/glTF and audio/data assets by installed pack ID, never by arbitrary URL.
- Create `scripts/ui/content_library.gd` and `scenes/ui/ContentLibrary.tscn`: pack library UI and progress/error states.
- Create `content/catalog.example.json` and `content/README.md`: schema/example and publisher instructions; no fake production download URL.
- Create `tools/package_content.py`: deterministic bounded data-only ZIP creator and SHA-256 manifest generator; signing key provided externally at invocation time and never checked in.
- Create `tests/content_system_smoke_test.gd` and content test fixtures under `tests/fixtures/content/`.
- Modify `project.godot`: register `ContentManager` autoload and opt-in configuration settings.
- Modify `scenes/boot/Main.tscn` and/or current HUD/navigation entry points only as needed to expose the Content Library without disturbing the playable start loop.
- Modify `.github/workflows/validate.yml`: run the new content smoke suite and package-tool tests.
- Modify `docs/TEST_PLAN.md`, `docs/TECHNICAL_ARCHITECTURE.md`, and `README.md`: describe the system, deployment requirements and verified test coverage.

## Task 1: Define and test the content catalog contract

**Files:**
- Create: `scripts/content/content_catalog.gd`
- Create: `content/catalog.example.json`
- Create: `content/README.md`
- Test: `tests/content_system_smoke_test.gd`

**Interfaces:**
- `ContentCatalog.parse_signed_envelope(raw_json: String, public_key_pem: String) -> Dictionary`: returns `{ "ok": bool, "error": String, "catalog": Dictionary }`.
- `ContentCatalog.validate_payload(catalog: Dictionary) -> Dictionary`: validates schema, bounds, unique pack IDs, allowed kinds/extensions, package HTTPS URLs, dependency references, and non-negative sizes.
- Signed envelope signs the exact decoded payload bytes; do not sign/re-serialize a Dictionary, which risks canonicalization differences. Production public key is configured explicitly; absence is a hard failure for remote catalogs.

- [ ] Step 1: Add smoke tests for valid signed catalog, malformed JSON, missing fields, invalid signature, duplicate IDs, HTTP/non-HTTPS URLs, negative sizes, unsafe file names, and missing/circular dependencies.
- [ ] Step 2: Run `godot --headless --path . --script res://tests/content_system_smoke_test.gd` and verify the new tests fail for missing implementation.
- [ ] Step 3: Implement the catalog parser and strict schema/size limits; use Godot Crypto/HashingContext APIs rather than home-grown cryptography. Generate ephemeral test keys in test setup only; never commit a test private key as a production credential.
- [ ] Step 4: Run the focused smoke test and verify all catalog cases pass.
- [ ] Step 5: Review the example schema to ensure it contains no fake operational endpoint and clearly documents the required publisher fields.

## Task 2: Implement safe package verification and atomic installation

**Files:**
- Create: `scripts/content/content_package_installer.gd`
- Test: `tests/content_system_smoke_test.gd`
- Test fixtures: `tests/fixtures/content/`

**Interfaces:**
- `verify_archive(archive_path: String, expected_sha256: String, expected_bytes: int, pack_record: Dictionary) -> Dictionary`
- `install_archive(archive_path: String, pack_record: Dictionary) -> Dictionary`
- `remove_installed_pack(pack_id: String) -> Dictionary`
- Use private paths rooted at `user://content/staging/` and `user://content/installed/<pack_id>/<version>/`; no caller-supplied destination paths.

- [ ] Step 1: Add tests for digest mismatch, size mismatch, corrupt ZIP, unsupported extensions, unlisted files, `../`, absolute paths, duplicate normalized names, excessive file count, oversized files, and failed promotion preserving the previous install.
- [ ] Step 2: Run the suite and confirm failing tests precede implementation.
- [ ] Step 3: Implement bounded ZIP entry enumeration and per-file extraction only after path normalization and allowlist checks. Enforce limits for compressed bytes, total uncompressed bytes, entry count, per-entry bytes, and expansion ratio. Verify each listed file digest before promotion.
- [ ] Step 4: Install to a fresh staging directory; write the final registry/manifest; atomically promote only after all files validate. On error, delete staging and retain the existing valid version.
- [ ] Step 5: Test deletion against app-private paths and ensure no path provided by a manifest is used as an unconstrained deletion target.
- [ ] Step 6: Rerun the entire smoke suite and validate no files outside the temporary content root are touched.

## Task 3: Implement downloads and persistent pack state

**Files:**
- Create: `scripts/content/content_manager.gd`
- Modify: `project.godot`
- Test: `tests/content_system_smoke_test.gd`

**Interfaces:**
- Autoload signal `catalog_updated(catalog: Dictionary)`.
- Signal `pack_state_changed(pack_id: String, state: String, details: Dictionary)`.
- Signal `download_progress(pack_id: String, downloaded_bytes: int, total_bytes: int)`.
- Methods: `refresh_catalog() -> void`, `download_pack(pack_id: String) -> Error`, `cancel_download(pack_id: String) -> void`, `install_local_archive(pack_id: String, archive_path: String) -> Dictionary`, `delete_pack(pack_id: String) -> Dictionary`, `is_pack_installed(pack_id: String) -> bool`, `get_installed_pack_path(pack_id: String) -> String`.
- Persist registry atomically in private `user://content/registry.json`. Reconcile it at startup against on-disk install manifests rather than blindly trusting registry data.

- [ ] Step 1: Add tests for offline startup, absent catalog URL, invalid configuration, invalid package ID, unknown pack, stale registry, missing installed files, and dependency-aware deletion.
- [ ] Step 2: Implement startup reconciliation and an explicit “catalog not configured/offline” state; core game remains playable.
- [ ] Step 3: Add HTTPS catalog/package requests via `HTTPRequest`. Downloads go to temporary files; apply fixed timeout/progress settings, bounded redirect count, response-code validation, and optional Range-based resume only when server supports it. Do not trust response headers as integrity evidence.
- [ ] Step 4: Connect completed downloads to Task 1 catalog validation and Task 2 verification/installation. Emit clear state transitions and errors; prevent duplicate concurrent downloads for the same pack.
- [ ] Step 5: Add storage-space preflight and fail before download when expected temporary + installed + extraction capacity is unavailable.
- [ ] Step 6: Test success/failure paths with local fixtures or injected transfer completion data; run a separate controlled HTTP integration probe where the environment permits it. Never claim Internet integration passed without an actual reachable test.
- [ ] Step 7: Run all smoke tests and inspect the state file recovery path after an interrupted install.

## Task 4: Load installed assets without loading the world library into memory

**Files:**
- Create: `scripts/content/content_asset_loader.gd`
- Test: `tests/content_system_smoke_test.gd`
- Fixtures: `tests/fixtures/content/`

**Interfaces:**
- `load_gltf(pack_id: String, relative_path: String) -> Dictionary` returns `{ "ok": bool, "error": String, "node": Node }`.
- `load_audio_stream(pack_id: String, relative_path: String) -> Dictionary` returns `{ "ok": bool, "error": String, "stream": Resource }`.
- Resolve paths only through the manager's verified installed manifest; reject traversal and any path absent from that manifest.
- For GLB/glTF, use `GLTFDocument` / `GLTFState` at runtime with the installed directory as base path so referenced assets resolve correctly.

- [ ] Step 1: Add test for loading a tiny known-valid GLB fixture, missing pack, missing asset, disallowed extension, traversal, and missing external texture.
- [ ] Step 2: Verify new tests fail for missing loader.
- [ ] Step 3: Implement checked runtime loading, error returns instead of unhandled errors, and bounded resource lifetimes. Do not preload all packs or retain temporary resources after their scenes are disposed.
- [ ] Step 4: Run tests and verify a loaded test scene can be attached/detached safely.
- [ ] Step 5: Record that device-specific load-time and memory measurements remain an Android-device acceptance item.

## Task 5: Add the in-game content library

**Files:**
- Create: `scripts/ui/content_library.gd`
- Create: `scenes/ui/ContentLibrary.tscn`
- Modify: current HUD/navigation entry point and `scenes/boot/Main.tscn` only as needed.
- Test: UI state transitions in `tests/content_system_smoke_test.gd` or an isolated UI test script.

**Required UI:**
- Display name, category, version, download size, installed size where known, dependency requirements, and pack state.
- Explicit Download / Cancel / Retry / Delete controls.
- Progress and useful errors for offline, HTTP failure, integrity failure, insufficient storage, and missing dependencies.
- Optional “Wi-Fi only” preference; do not auto-download and do not require sign-in.
- When a save references a missing content ID, preserve the save and show the missing pack rather than crashing or silently discarding data.

- [ ] Step 1: Define UI state tests with mocked ContentManager responses; test every state and ensure no control implies success prematurely.
- [ ] Step 2: Build the UI scene and wire controls exclusively to public ContentManager APIs.
- [ ] Step 3: Verify core start, pause, inventory, dialogue, and save/load still work if the library is never opened.
- [ ] Step 4: Check readability and touch target sizes in the current mobile viewport; avoid adding large background graphics to the base APK.

## Task 6: Add packaging tools, CI coverage, and operational docs

**Files:**
- Create: `tools/package_content.py`
- Modify: `.github/workflows/validate.yml`
- Modify: `README.md`, `docs/TECHNICAL_ARCHITECTURE.md`, `docs/TEST_PLAN.md`
- Create: `tests/test_package_content.py` if package tooling can be tested without extra heavy dependencies.

**Interfaces:**
- Packaging tool accepts source directory, pack ID, version, pack type, output path, and an externally provided signing key file/environment reference. It must fail if the key is absent and must never print secret material. Output is a reproducible data-only ZIP, per-file manifest and signed catalog payload/envelope.
- Use Python standard library only unless a justified dependency is approved.

- [ ] Step 1: Add Python unit tests for accepted data assets and rejected scripts/binaries/traversal/duplicate paths; test that absent signing credentials fail closed.
- [ ] Step 2: Run `python -m unittest tests.test_package_content -v` and confirm red for unimplemented behavior.
- [ ] Step 3: Implement deterministic ZIP metadata where practical, per-file SHA-256, bounds/allowlist checks, and external-key signing. Never generate or commit a production private key in CI.
- [ ] Step 4: Add CI steps for Python tests and Godot content smoke tests; keep Godot 4.6 and existing gameplay test commands unchanged.
- [ ] Step 5: Update docs with publisher workflow, trusted public-key rotation procedure, catalog deployment, pack versioning, troubleshooting and Android on-device acceptance tests.
- [ ] Step 6: Run all CI-equivalent commands and check existing Android/Web export configuration is unchanged unless a tested fix is necessary.

## Task 7: End-to-end acceptance and release boundary

**Files:**
- Modify tests/docs as needed; avoid unrelated game refactors.

- [ ] Step 1: Validate clean/offline launch, catalog unavailable, a verified pack install, a corrupted pack rejection, update rollback, dependency block, deletion and reinstall.
- [ ] Step 2: Run the existing gameplay smoke test and the content smoke suite with Godot 4.6 headless.
- [ ] Step 3: Run Python package-tool tests, import/parse, and Android/Web export workflows through GitHub Actions; inspect generated logs and artifacts.
- [ ] Step 4: Measure actual APK size, package download/uncompressed size, loading time and peak memory on at least one low-end Android device and one representative device. Record exact device/build details.
- [ ] Step 5: Confirm remote catalog signing key, HTTPS hosting and actual package artifacts are configured before enabling production downloads. Without these external deployment inputs, ship the UI in a safe “content service unavailable/not configured” state instead of claiming end-to-end live delivery.
- [ ] Step 6: Open a pull request from a feature branch, review the diff and passing CI, and do not merge to `main` without explicit release approval.

## Documentation References

- Godot 4.6 runtime file loading: https://docs.godotengine.org/en/4.6/tutorials/io/runtime_file_loading_and_saving.html
- Godot HTTPRequest: https://docs.godotengine.org/en/4.6/classes/class_httprequest.html
- Godot Crypto: https://docs.godotengine.org/en/4.6/classes/class_crypto.html
- Godot ProjectSettings / runtime resource packs: https://docs.godotengine.org/en/4.6/classes/class_projectsettings.html

---

## Self-review

- **Spec coverage:** Offline base game, signed catalog, data-only packages, safe storage, downloads/cancellation/retries, dependency-aware install/removal, UI, save compatibility, CI, Android measurements, and publication requirements each map to a task.
- **Step scan:** Each task begins with test-first behavior where appropriate and includes observable commands/results; publication and hardware tests are explicitly separate from headless tests.
- **Type/interface consistency:** ContentCatalog validates envelopes, ContentManager orchestrates, ContentPackageInstaller owns filesystem extraction, ContentAssetLoader resolves installed-manifest paths, and UI consumes only ContentManager signals/APIs.
- **Review focus coverage:** Malformed/unsigned catalog → Task 1; corrupt or path-escaping ZIP → Task 2; interrupted transfer and stale state → Task 3; path traversal and missing GLB dependencies → Task 4; missing packs and UI state → Task 5; unsafe package input/signing key handling → Task 6; online end-to-end and device performance → Task 7.
- **Proportion/scope:** This is one coherent subsystem with multiple dependent deliverables. Production hosting and trusted signing configuration are release prerequisites, not assumed as already existing.
