#!/usr/bin/env python3
"""Validate that every game asset has explicit source and license metadata.

Uses only the Python standard library. It never downloads, generates, or uploads assets.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from urllib.parse import urlparse

ASSET_EXTENSIONS = {
    ".glb", ".gltf", ".obj", ".dae",
    ".png", ".jpg", ".jpeg", ".webp", ".svg",
    ".wav", ".ogg", ".mp3", ".flac",
    ".mp4", ".webm",
}
REQUIRED_ENTRY_FIELDS = (
    "path", "author", "source_url", "license", "license_url",
    "attribution", "commercial_use", "redistribution_allowed",
)


def is_http_url(value: object) -> bool:
    if not isinstance(value, str) or not value or len(value) > 2048:
        return False
    if any(character.isspace() for character in value) or "\\" in value:
        return False
    try:
        parsed = urlparse(value)
        hostname = parsed.hostname
        # Accessing .port also validates malformed port values.
        _ = parsed.port
    except ValueError:
        return False
    return (
        parsed.scheme in {"http", "https"}
        and bool(hostname)
        and not parsed.username
        and not parsed.password
    )


def scan_assets(assets_root: Path, project_root: Path) -> set[str]:
    found: set[str] = set()
    ignored_parts = {".git", ".godot", "__pycache__"}
    if not assets_root.exists():
        return found
    for path in assets_root.rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(project_root).as_posix()
        if any(part in ignored_parts for part in path.relative_to(project_root).parts):
            continue
        if path.suffix.lower() in ASSET_EXTENSIONS:
            found.add(relative)
    return found


def validate(project_root: Path) -> list[str]:
    errors: list[str] = []
    manifest_path = project_root / "assets" / "asset_manifest.json"
    assets_root = project_root / "assets"

    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return [f"Manifest not found: {manifest_path.relative_to(project_root)}"]
    except (OSError, json.JSONDecodeError) as exc:
        return [f"Cannot read asset manifest: {exc}"]

    if not isinstance(manifest, dict):
        return ["Manifest root must be a JSON object."]
    if manifest.get("schema_version") != 1:
        errors.append("schema_version must equal 1.")

    policy = manifest.get("policy")
    if not isinstance(policy, dict):
        errors.append("policy must be an object.")
    else:
        for key in (
            "require_verified_license",
            "require_commercial_permission",
            "require_redistribution_permission",
        ):
            if policy.get(key) is not True:
                errors.append(f"policy.{key} must be true for this project.")
        if policy.get("offline_first") is not True:
            errors.append("policy.offline_first must be true for this project.")
        if policy.get("paid_generation_apis_allowed") is not False:
            errors.append("policy.paid_generation_apis_allowed must be false for this project.")

    entries = manifest.get("assets")
    if not isinstance(entries, list):
        errors.append("assets must be an array.")
        entries = []

    seen_paths: set[str] = set()
    for index, entry in enumerate(entries):
        prefix = f"assets[{index}]"
        if not isinstance(entry, dict):
            errors.append(f"{prefix} must be an object.")
            continue

        missing = [field for field in REQUIRED_ENTRY_FIELDS if field not in entry]
        if missing:
            errors.append(f"{prefix} is missing fields: {', '.join(missing)}.")
            continue

        asset_path_value = entry.get("path")
        if not isinstance(asset_path_value, str) or not asset_path_value.strip():
            errors.append(f"{prefix}.path must be a non-empty path.")
            continue

        relative_path = Path(asset_path_value)
        normalized = relative_path.as_posix()
        if relative_path.is_absolute() or ".." in relative_path.parts or not normalized.startswith("assets/"):
            errors.append(f"{prefix}.path must stay inside assets/: {asset_path_value}")
            continue
        if normalized in seen_paths:
            errors.append(f"Duplicate manifest path: {normalized}")
        seen_paths.add(normalized)

        target = (project_root / relative_path).resolve()
        try:
            target.relative_to(assets_root.resolve())
        except ValueError:
            errors.append(f"{prefix}.path resolves outside assets/: {normalized}")
            continue

        if not target.is_file():
            errors.append(f"Asset file does not exist: {normalized}")
        elif target.suffix.lower() not in ASSET_EXTENSIONS:
            errors.append(f"Unsupported runtime asset extension: {normalized}")

        for field in ("author", "license", "attribution"):
            if not isinstance(entry.get(field), str) or not entry[field].strip():
                errors.append(f"{prefix}.{field} must be a non-empty string.")
        for field in ("source_url", "license_url"):
            if not is_http_url(entry.get(field)):
                errors.append(f"{prefix}.{field} must be a valid http(s) URL.")
        for field in ("commercial_use", "redistribution_allowed"):
            if entry.get(field) is not True:
                errors.append(f"{prefix}.{field} must be true; do not include this asset otherwise.")

    actual_paths = scan_assets(assets_root, project_root)
    missing_metadata = sorted(actual_paths - seen_paths)
    stale_entries = sorted(seen_paths - actual_paths)

    for path in missing_metadata:
        errors.append(f"Asset has no manifest entry: {path}")
    for path in stale_entries:
        errors.append(f"Manifest entry is not a recognized existing asset: {path}")

    if not errors:
        print(
            f"Asset manifest OK: {len(actual_paths)} runtime asset(s) checked; "
            "license metadata is present for each asset."
        )
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Check offline game assets and required license metadata."
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="Project root (defaults to the repository root).",
    )
    args = parser.parse_args()
    project_root = args.root.resolve()
    errors = validate(project_root)
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        print(f"Asset manifest validation failed: {len(errors)} issue(s).", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
