#!/usr/bin/env python3
"""Create deterministic, data-only AshenKingdoms content ZIPs and signed catalogs."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import tempfile
import zipfile
from typing import Any
from urllib.parse import urlparse

ALLOWED_EXTENSIONS = {
    ".glb", ".png", ".jpg", ".jpeg", ".webp", ".ktx2",
    ".ogg", ".wav", ".mp3", ".json",
}
MAX_FILES = 10_000
MAX_FILE_BYTES = 512 * 1024 * 1024
MAX_TOTAL_BYTES = 4 * 1024 * 1024 * 1024
MAX_ARCHIVE_BYTES = 2 * 1024 * 1024 * 1024
PACK_TYPES = {"character", "world", "equipment", "audio", "language"}
PACK_ID_RE = re.compile(r"^[a-z0-9_-]{1,64}$")
VERSION_RE = re.compile(r"^[A-Za-z0-9._-]{1,64}$")
PROVENANCE_FIELDS = (
    "author", "source_url", "license", "license_url", "attribution",
    "commercial_use", "redistribution_allowed",
)
PROVENANCE_TEXT_FIELDS = ("author", "license", "attribution")
PROVENANCE_URL_FIELDS = ("source_url", "license_url")


class PackageError(ValueError):
    """Raised when source content cannot safely be packaged."""


def is_safe_relative_path(value: str) -> bool:
    if not value or len(value) > 240 or "\x00" in value or "\\" in value or ":" in value:
        return False
    path = pathlib.PurePosixPath(value)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in value.split("/")):
        return False
    if any(part.strip() != part for part in path.parts):
        return False
    return True


def validate_pack_id(value: str) -> str:
    if not PACK_ID_RE.fullmatch(value):
        raise PackageError("Pack ID must contain only lowercase letters, digits, '_' or '-'.")
    return value


def validate_version(value: str) -> str:
    if not VERSION_RE.fullmatch(value) or value in {".", ".."}:
        raise PackageError("Version contains unsupported characters.")
    return value


def validate_package_url(value: str) -> str:
    if not value.startswith("https://") or len(value) > 2048:
        raise PackageError("Package URL must be an HTTPS URL.")
    return value


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def collect_files(source_dir: pathlib.Path) -> list[dict[str, Any]]:
    root = source_dir.resolve(strict=True)
    if not root.is_dir():
        raise PackageError("Source path must be a directory.")
    records: list[dict[str, Any]] = []
    seen: set[str] = set()
    total_size = 0
    for current, dirs, files in os.walk(root, followlinks=False):
        current_path = pathlib.Path(current)
        for directory in list(dirs):
            child = current_path / directory
            if child.is_symlink():
                raise PackageError(f"Symlinked directories are not allowed: {child.name}")
        dirs.sort()
        for filename in sorted(files):
            file_path = current_path / filename
            if file_path.is_symlink() or not file_path.is_file():
                raise PackageError(f"Symlinks and special files are not allowed: {filename}")
            relative = file_path.relative_to(root).as_posix()
            if not is_safe_relative_path(relative) or relative.casefold() == "installed_manifest.json":
                raise PackageError(f"Unsafe or reserved relative path: {relative}")
            if file_path.suffix.lower() not in ALLOWED_EXTENSIONS:
                raise PackageError(f"Disallowed content type: {relative}")
            normalized = relative.casefold()
            if normalized in seen:
                raise PackageError(f"Duplicate normalized path: {relative}")
            seen.add(normalized)
            size = file_path.stat().st_size
            if size > MAX_FILE_BYTES:
                raise PackageError(f"File exceeds size limit: {relative}")
            total_size += size
            if total_size > MAX_TOTAL_BYTES:
                raise PackageError("Package exceeds total unpacked size limit.")
            digest = sha256_file(file_path)
            records.append({"path": relative, "size": size, "sha256": digest})
            if len(records) > MAX_FILES:
                raise PackageError("Package contains too many files.")
    if not records:
        raise PackageError("Source directory contains no supported assets.")
    return records


def validate_provenance_manifest(
    manifest_path: pathlib.Path,
    source_dir: pathlib.Path,
    records: list[dict[str, Any]],
) -> dict[str, dict[str, Any]]:
    """Require explicit license/attribution permission for every file to be packaged."""
    manifest_path = pathlib.Path(manifest_path)
    source_root = pathlib.Path(source_dir).resolve(strict=True)
    if not manifest_path.is_file():
        raise PackageError(f"Asset provenance manifest does not exist: {manifest_path}")
    manifest_resolved = manifest_path.resolve(strict=True)
    try:
        manifest_resolved.relative_to(source_root)
    except ValueError:
        pass
    else:
        raise PackageError("The provenance manifest must be outside the package source directory.")

    try:
        raw_manifest = json.loads(manifest_resolved.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise PackageError(f"Cannot read asset provenance manifest: {exc}") from exc
    if not isinstance(raw_manifest, dict) or type(raw_manifest.get("schema_version")) is not int or raw_manifest.get("schema_version") != 1:
        raise PackageError("Asset provenance manifest schema_version must equal integer 1.")
    entries = raw_manifest.get("assets")
    if not isinstance(entries, list):
        raise PackageError("Asset provenance manifest must contain an assets array.")

    expected_paths = {str(record["path"]) for record in records}
    normalized_seen: set[str] = set()
    provenance_by_path: dict[str, dict[str, Any]] = {}
    for index, entry in enumerate(entries):
        if not isinstance(entry, dict):
            raise PackageError(f"assets[{index}] must be an object.")
        missing = [field for field in PROVENANCE_FIELDS if field not in entry]
        if missing:
            raise PackageError(f"assets[{index}] is missing required fields: {', '.join(missing)}.")
        raw_path = entry.get("path")
        if not isinstance(raw_path, str) or not is_safe_relative_path(raw_path):
            raise PackageError(f"assets[{index}].path is not a safe package-relative path.")
        path = raw_path
        normalized = path.casefold()
        if normalized in normalized_seen:
            raise PackageError(f"Duplicate case-insensitive provenance path: {path}")
        normalized_seen.add(normalized)
        if path not in expected_paths:
            raise PackageError(f"Provenance entry does not match a packaged file: {path}")

        metadata: dict[str, Any] = {"path": path}
        for field in PROVENANCE_TEXT_FIELDS:
            value = entry.get(field)
            if not isinstance(value, str) or not value.strip():
                raise PackageError(f"assets[{index}].{field} must be a non-empty string.")
            metadata[field] = value.strip()
        for field in PROVENANCE_URL_FIELDS:
            value = entry.get(field)
            if not isinstance(value, str) or len(value) > 2048:
                raise PackageError(f"assets[{index}].{field} must be a valid HTTP(S) URL.")
            parsed = urlparse(value)
            if parsed.scheme not in {"http", "https"} or not parsed.hostname or parsed.username or parsed.password:
                raise PackageError(f"assets[{index}].{field} must be a valid HTTP(S) URL without credentials.")
            metadata[field] = value
        for field in ("commercial_use", "redistribution_allowed"):
            if entry.get(field) is not True:
                raise PackageError(f"assets[{index}].{field} must be true before content can be packaged.")
            metadata[field] = True
        provenance_by_path[path] = metadata

    missing_paths = sorted(expected_paths - set(provenance_by_path))
    if missing_paths:
        raise PackageError("Packaged assets lack provenance/license records: " + ", ".join(missing_paths[:20]))
    return provenance_by_path


def create_archive(source_dir: pathlib.Path, output_zip: pathlib.Path, records: list[dict[str, Any]]) -> None:
    root = source_dir.resolve(strict=True)
    output_zip.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix="ashen-pack-", suffix=".zip", dir=output_zip.parent, delete=False) as temp:
        temporary_path = pathlib.Path(temp.name)
    try:
        with zipfile.ZipFile(temporary_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9, strict_timestamps=True) as archive:
            for record in records:
                relative = record["path"]
                info = zipfile.ZipInfo(relative, date_time=(1980, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.create_system = 3
                info.external_attr = 0o100644 << 16
                digest = hashlib.sha256()
                written_bytes = 0
                with archive.open(info, "w", force_zip64=True) as output:
                    with (root / relative).open("rb") as source:
                        for chunk in iter(lambda: source.read(1024 * 1024), b""):
                            output.write(chunk)
                            digest.update(chunk)
                            written_bytes += len(chunk)
                if written_bytes != int(record["size"]) or digest.hexdigest() != str(record["sha256"]):
                    raise PackageError(f"Source asset changed while packaging: {relative}")
        if temporary_path.stat().st_size > MAX_ARCHIVE_BYTES:
            raise PackageError("Compressed archive exceeds the download size limit.")
        os.replace(temporary_path, output_zip)
    finally:
        temporary_path.unlink(missing_ok=True)


def sign_payload(payload: bytes, private_key: pathlib.Path, signature_path: pathlib.Path) -> bytes:
    if not private_key.is_file():
        raise PackageError("Signing key is missing; refusing to create an unsigned catalog.")
    signature_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        result = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", str(private_key), "-out", str(signature_path)],
            input=payload,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except FileNotFoundError as exc:
        raise PackageError("OpenSSL is required to sign catalogs; no unsigned fallback is allowed.") from exc
    if result.returncode != 0 or not signature_path.is_file():
        raise PackageError("OpenSSL could not sign the catalog payload.")
    return signature_path.read_bytes()


def build_package(
    source_dir: pathlib.Path,
    asset_manifest_path: pathlib.Path,
    pack_id: str,
    version: str,
    pack_type: str,
    url: str,
    output_zip: pathlib.Path,
    output_envelope: pathlib.Path,
    private_key: pathlib.Path,
) -> dict[str, Any]:
    validate_pack_id(pack_id)
    validate_version(version)
    validate_package_url(url)
    if not pathlib.Path(private_key).is_file():
        raise PackageError("Signing key is missing; refusing to create an unsigned catalog.")
    if pack_type not in PACK_TYPES:
        raise PackageError("Unsupported pack type.")
    records = collect_files(pathlib.Path(source_dir))
    provenance = validate_provenance_manifest(pathlib.Path(asset_manifest_path), pathlib.Path(source_dir), records)
    for record in records:
        record.update(provenance[str(record["path"])])
    create_archive(pathlib.Path(source_dir), pathlib.Path(output_zip), records)
    archive_size = pathlib.Path(output_zip).stat().st_size
    archive_digest = sha256_file(pathlib.Path(output_zip))
    pack_record = {
        "id": pack_id,
        "name": pack_id.replace("_", " ").replace("-", " ").title(),
        "version": version,
        "type": pack_type,
        "url": url,
        "download_size": archive_size,
        "sha256": archive_digest,
        "files": records,
        "dependencies": [],
    }
    payload = json.dumps({"schema_version": 1, "packs": [pack_record]}, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    output_envelope = pathlib.Path(output_envelope)
    output_envelope.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="ashen-sign-") as temporary_dir:
        signature_path = pathlib.Path(temporary_dir) / "catalog.sig"
        signature = sign_payload(payload, pathlib.Path(private_key), signature_path)
        envelope = {
            "algorithm": "RSA-SHA256",
            "payload_base64": base64.b64encode(payload).decode("ascii"),
            "signature_base64": base64.b64encode(signature).decode("ascii"),
        }
        temporary_envelope = output_envelope.with_suffix(output_envelope.suffix + ".tmp")
        temporary_envelope.write_text(json.dumps(envelope, separators=(",", ":")) + "\n", encoding="utf-8")
        os.replace(temporary_envelope, output_envelope)
        public_key_path = output_envelope.with_suffix(".public.pem")
        public_result = subprocess.run(
            ["openssl", "pkey", "-in", str(private_key), "-pubout", "-out", str(public_key_path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if public_result.returncode != 0:
            output_envelope.unlink(missing_ok=True)
            raise PackageError("OpenSSL could not export the public verification key.")
    return {
        "pack_id": pack_id,
        "version": version,
        "archive": str(output_zip),
        "archive_size": archive_size,
        "catalog_envelope": str(output_envelope),
        "public_key": str(public_key_path),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=pathlib.Path)
    parser.add_argument(
        "--asset-manifest",
        required=True,
        type=pathlib.Path,
        help="External JSON provenance/license manifest with one record for every path under --source.",
    )
    parser.add_argument("--pack-id", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--type", required=True, choices=sorted(PACK_TYPES))
    parser.add_argument("--url", required=True, help="Final HTTPS URL where the ZIP will be hosted")
    parser.add_argument("--output-zip", required=True, type=pathlib.Path)
    parser.add_argument("--output-catalog", required=True, type=pathlib.Path)
    parser.add_argument("--private-key", required=True, type=pathlib.Path, help="External PEM RSA private key; never commit it")
    args = parser.parse_args()
    try:
        result = build_package(
            source_dir=args.source,
            asset_manifest_path=args.asset_manifest,
            pack_id=args.pack_id,
            version=args.version,
            pack_type=args.type,
            url=args.url,
            output_zip=args.output_zip,
            output_envelope=args.output_catalog,
            private_key=args.private_key,
        )
    except (PackageError, OSError) as exc:
        parser.exit(2, f"error: {exc}\n")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
