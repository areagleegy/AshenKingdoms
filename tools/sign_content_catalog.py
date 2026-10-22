#!/usr/bin/env python3
"""Validate and sign a complete multi-pack AshenKingdoms catalog."""

from __future__ import annotations

import argparse
import base64
import json
import pathlib
import re
import subprocess
import tempfile
from typing import Any
from urllib.parse import urlparse

try:
    from tools.package_content import (
        ALLOWED_EXTENSIONS,
        CATALOG_SCHEMA_VERSION,
        MAX_ARCHIVE_BYTES,
        MAX_FILE_BYTES,
        MAX_FILES,
        MAX_TOTAL_BYTES,
        PACK_TYPES,
        PackageError,
        is_safe_relative_path,
        sign_payload,
        validate_pack_id,
        validate_package_url,
        validate_version,
    )
except ModuleNotFoundError:
    from package_content import (
        ALLOWED_EXTENSIONS,
        MAX_ARCHIVE_BYTES,
        MAX_FILE_BYTES,
        MAX_FILES,
        MAX_TOTAL_BYTES,
        PACK_TYPES,
        PackageError,
        is_safe_relative_path,
        sign_payload,
        validate_pack_id,
        validate_package_url,
        validate_version,
    )

SHA256_RE = re.compile(r"^[0-9a-fA-F]{64}$")
MAX_PACKS = 500


def validate_catalog(catalog: Any) -> dict[str, Any]:
    if not isinstance(catalog, dict) or catalog.get("schema_version") != CATALOG_SCHEMA_VERSION:
        raise PackageError(f"Catalog root/schema_version must equal {CATALOG_SCHEMA_VERSION}.")
    packs = catalog.get("packs")
    if not isinstance(packs, list) or len(packs) > MAX_PACKS:
        raise PackageError("Catalog packs must be a bounded array.")
    by_id: dict[str, dict[str, Any]] = {}
    for pack in packs:
        if not isinstance(pack, dict):
            raise PackageError("Every pack record must be an object.")
        pack_id = validate_pack_id(str(pack.get("id", "")))
        if pack_id in by_id:
            raise PackageError(f"Duplicate pack ID: {pack_id}")
        validate_version(str(pack.get("version", "")))
        validate_package_url(str(pack.get("url", "")))
        if pack.get("type") not in PACK_TYPES:
            raise PackageError(f"Unsupported pack type for {pack_id}.")
        size = pack.get("download_size")
        if not isinstance(size, int) or isinstance(size, bool) or size < 1 or size > MAX_ARCHIVE_BYTES:
            raise PackageError(f"Invalid download size for {pack_id}.")
        if not SHA256_RE.fullmatch(str(pack.get("sha256", ""))):
            raise PackageError(f"Invalid archive SHA-256 for {pack_id}.")
        files = pack.get("files")
        if not isinstance(files, list) or not files or len(files) > MAX_FILES:
            raise PackageError(f"Invalid file list for {pack_id}.")
        seen_paths: set[str] = set()
        unpacked_size = 0
        for record in files:
            if not isinstance(record, dict):
                raise PackageError(f"Invalid file record in {pack_id}.")
            path = str(record.get("path", ""))
            if not is_safe_relative_path(path) or path.casefold() == "installed_manifest.json":
                raise PackageError(f"Unsafe or reserved path in {pack_id}: {path}")
            if pathlib.PurePosixPath(path).suffix.lower() not in ALLOWED_EXTENSIONS:
                raise PackageError(f"Disallowed asset type in {pack_id}: {path}")
            normalized = path.casefold()
            if normalized in seen_paths:
                raise PackageError(f"Duplicate normalized asset path in {pack_id}: {path}")
            seen_paths.add(normalized)
            file_size = record.get("size")
            if not isinstance(file_size, int) or isinstance(file_size, bool) or file_size < 0 or file_size > MAX_FILE_BYTES:
                raise PackageError(f"Invalid asset size in {pack_id}: {path}")
            if not SHA256_RE.fullmatch(str(record.get("sha256", ""))):
                raise PackageError(f"Invalid asset digest in {pack_id}: {path}")

            for field in ("author", "license", "attribution"):
                value = record.get(field)
                if not isinstance(value, str) or not value.strip():
                    raise PackageError(f"Missing or invalid {field} provenance in {pack_id}: {path}")
            for field in ("source_url", "license_url"):
                value = record.get(field)
                if not isinstance(value, str) or len(value) > 2048:
                    raise PackageError(f"Missing or invalid {field} in {pack_id}: {path}")
                parsed_url = urlparse(value)
                if (
                    parsed_url.scheme not in {"http", "https"}
                    or not parsed_url.hostname
                    or parsed_url.username
                    or parsed_url.password
                ):
                    raise PackageError(f"{field} must be an HTTP(S) URL without embedded credentials: {path}")
            for field in ("commercial_use", "redistribution_allowed"):
                if record.get(field) is not True:
                    raise PackageError(f"{field} permission must be explicitly true in {pack_id}: {path}")

            unpacked_size += file_size
            if unpacked_size > MAX_TOTAL_BYTES:
                raise PackageError(f"Unpacked package size limit exceeded: {pack_id}")
        dependencies = pack.get("dependencies", [])
        if not isinstance(dependencies, list):
            raise PackageError(f"Dependencies must be an array in {pack_id}.")
        if len(set(map(str, dependencies))) != len(dependencies):
            raise PackageError(f"Duplicate dependencies in {pack_id}.")
        for dependency in dependencies:
            validate_pack_id(str(dependency))
            if str(dependency) == pack_id:
                raise PackageError(f"Self-dependency in {pack_id}.")
        by_id[pack_id] = pack

    for pack_id, pack in by_id.items():
        for dependency in pack.get("dependencies", []):
            if dependency not in by_id:
                raise PackageError(f"Missing dependency {dependency} referenced by {pack_id}.")

    marks: dict[str, int] = {}

    def visit(pack_id: str) -> None:
        if marks.get(pack_id) == 1:
            raise PackageError("Catalog contains a dependency cycle.")
        if marks.get(pack_id) == 2:
            return
        marks[pack_id] = 1
        for dependency in by_id[pack_id].get("dependencies", []):
            visit(dependency)
        marks[pack_id] = 2

    for pack_id in by_id:
        visit(pack_id)
    return catalog


def sign_catalog(input_path: pathlib.Path, output_path: pathlib.Path, private_key: pathlib.Path) -> dict[str, str]:
    if not private_key.is_file():
        raise PackageError("Signing key is missing; refusing to create an unsigned catalog.")
    raw = json.loads(input_path.read_text(encoding="utf-8"))
    catalog = validate_catalog(raw)
    payload = json.dumps(catalog, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="ashen-catalog-") as temporary_dir:
        signature = sign_payload(payload, private_key, pathlib.Path(temporary_dir) / "catalog.sig")
        envelope = {
            "algorithm": "RSA-SHA256",
            "payload_base64": base64.b64encode(payload).decode("ascii"),
            "signature_base64": base64.b64encode(signature).decode("ascii"),
        }
        temporary_output = output_path.with_suffix(output_path.suffix + ".tmp")
        temporary_output.write_text(json.dumps(envelope, separators=(",", ":")) + "\n", encoding="utf-8")
        temporary_output.replace(output_path)
    public_key_path = output_path.with_suffix(".public.pem")
    result = subprocess.run(
        ["openssl", "pkey", "-in", str(private_key), "-pubout", "-out", str(public_key_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        output_path.unlink(missing_ok=True)
        raise PackageError("OpenSSL could not export the public verification key.")
    return {"catalog_envelope": str(output_path), "public_key": str(public_key_path)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-catalog", required=True, type=pathlib.Path, help="Unsigned JSON object with schema_version and all pack records")
    parser.add_argument("--output-catalog", required=True, type=pathlib.Path)
    parser.add_argument("--private-key", required=True, type=pathlib.Path, help="External RSA PEM private key; never commit it")
    args = parser.parse_args()
    try:
        result = sign_catalog(args.input_catalog, args.output_catalog, args.private_key)
    except (PackageError, OSError, json.JSONDecodeError) as exc:
        parser.exit(2, f"error: {exc}\n")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
