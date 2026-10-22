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
from urllib.parse import urlsplit
from typing import Any

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
HOST_LABEL_RE = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$")


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
    if not isinstance(value, str) or not value or len(value) > 2048:
        raise PackageError("Package URL must be a valid HTTPS URL.")
    if any(ord(character) <= 32 or ord(character) == 127 for character in value) or "\\" in value:
        raise PackageError("Package URL contains whitespace or an invalid separator.")
    try:
        parsed = urlsplit(value)
        port = parsed.port
    except ValueError as exc:
        raise PackageError("Package URL has an invalid host or port.") from exc
    if (
        parsed.scheme.lower() != "https"
        or not parsed.hostname
        or parsed.username is not None
        or parsed.password is not None
        or parsed.fragment
        or parsed.netloc.endswith(":")
    ):
        raise PackageError("Package URL must use HTTPS with a valid host and no credentials or fragment.")
    hostname = parsed.hostname
    if len(hostname) > 253 or ":" in hostname:
        raise PackageError("Package URL host is invalid.")
    labels = hostname.split(".")
    if any(not HOST_LABEL_RE.fullmatch(label) for label in labels):
        raise PackageError("Package URL host contains an invalid DNS label.")
    if port is not None and not 1 <= port <= 65535:
        raise PackageError("Package URL port is outside the valid range.")
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
                with archive.open(info, "w", force_zip64=True) as output:
                    with (root / relative).open("rb") as source:
                        shutil.copyfileobj(source, output, length=1024 * 1024)
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
