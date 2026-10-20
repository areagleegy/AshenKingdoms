#!/usr/bin/env python3
"""Deterministic, offline inventory of media assets and literal Godot resource paths.

This tool reports what it can safely inspect; it does not download, generate,
rewrite, delete, listen to, render, or legally approve assets.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
import wave
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path
from urllib.parse import unquote, urlsplit

MEDIA_TYPES = {
    ".glb": "3d_model",
    ".gltf": "3d_model",
    ".obj": "3d_model",
    ".dae": "3d_model",
    ".png": "image",
    ".jpg": "image",
    ".jpeg": "image",
    ".webp": "image",
    ".svg": "image",
    ".wav": "audio",
    ".ogg": "audio",
    ".mp3": "audio",
    ".flac": "audio",
    ".mp4": "video",
    ".webm": "video",
}
MANIFEST_FIELDS = (
    "author", "source_url", "license", "license_url", "attribution",
    "commercial_use", "redistribution_allowed",
)
RESOURCE_SOURCE_SUFFIXES = {
    ".gd", ".tscn", ".tres", ".godot", ".gdshader", ".shader", ".cs",
    ".theme", ".cfg",
}
IGNORED_DIRECTORY_NAMES = {
    ".git", ".godot", "__pycache__", ".venv", "venv", "node_modules",
    ".pytest_cache", "dist", "build",
}
RESOURCE_PATTERN_TEXT = r"""res://([^"'(),;\s\]\}]+)"""
OPTIONAL_RESOURCE_PATHS = {
    "assets/characters/player/player.glb":
        "documented optional external player model; procedural fallback exists",
}
GLB_JSON_CHUNK = 0x4E4F534A
MAX_GLB_JSON_BYTES = 32 * 1024 * 1024


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_manifest(root: Path) -> tuple[dict[str, dict], list[str]]:
    manifest_path = root / "assets" / "asset_manifest.json"
    if not manifest_path.is_file():
        return {}, ["manifest not found: assets/asset_manifest.json"]
    try:
        data = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        return {}, [f"manifest could not be parsed: {exc}"]
    if not isinstance(data, dict) or not isinstance(data.get("assets"), list):
        return {}, ["manifest root must be an object with an assets array"]
    entries: dict[str, dict] = {}
    errors: list[str] = []
    for index, item in enumerate(data["assets"]):
        if not isinstance(item, dict) or not isinstance(item.get("path"), str):
            errors.append(f"manifest assets[{index}] has no string path")
            continue
        manifest_path_value = Path(item["path"]).as_posix()
        if manifest_path_value in entries:
            errors.append(f"duplicate manifest path: {manifest_path_value}")
        else:
            entries[manifest_path_value] = item
    return entries, errors


def _inspect_gltf_uris(path: Path, document: object) -> dict:
    result = {"external_uris": [], "missing_uris": [], "remote_or_absolute_uris": []}
    if not isinstance(document, dict):
        result["inspection_errors"] = ["glTF JSON root is not an object"]
        return result
    for section in ("buffers", "images"):
        entries = document.get(section, [])
        if not isinstance(entries, list):
            result.setdefault("inspection_errors", []).append(
                f"glTF {section} must be an array"
            )
            continue
        for index, entry in enumerate(entries):
            if not isinstance(entry, dict) or not isinstance(entry.get("uri"), str):
                continue  # Embedded GLB bufferView images/buffers need no external URI.
            uri = entry["uri"]
            ref = {"section": section, "index": index, "uri": uri}
            result["external_uris"].append(ref)
            if uri.startswith("data:"):
                ref["status"] = "embedded_data_uri"
                continue
            parsed = urlsplit(uri)
            if parsed.scheme or uri.startswith("//") or Path(unquote(parsed.path)).is_absolute():
                ref["status"] = "remote_or_absolute_not_fetched"
                result["remote_or_absolute_uris"].append(ref)
                continue
            relative = unquote(parsed.path)
            target = (path.parent / relative).resolve()
            try:
                target.relative_to(path.parent.resolve())
            except ValueError:
                ref["status"] = "path_escapes_asset_directory"
                result["missing_uris"].append(ref)
                continue
            if target.is_file():
                ref["status"] = "found"
            else:
                ref["status"] = "missing"
                result["missing_uris"].append(ref)
    return result


def _inspect_glb(path: Path) -> dict:
    result: dict = {"format": "glb", "inspection_level": "container_and_json_chunk"}
    try:
        size = path.stat().st_size
        with path.open("rb") as stream:
            header = stream.read(12)
            if len(header) != 12:
                raise ValueError("file shorter than GLB header")
            magic, version, declared_length = struct.unpack("<4sII", header)
            if magic != b"glTF":
                raise ValueError("invalid GLB magic; expected glTF")
            result.update(
                glb_version=version,
                declared_length_bytes=declared_length,
                actual_length_bytes=size,
            )
            if version != 2:
                result.setdefault("inspection_errors", []).append(
                    f"GLB version {version} is not version 2"
                )
            if declared_length != size:
                result.setdefault("inspection_errors", []).append(
                    "GLB declared length differs from actual file size"
                )
            json_document = None
            offset = 12
            limit = min(size, declared_length)
            while offset + 8 <= limit:
                stream.seek(offset)
                chunk_header = stream.read(8)
                if len(chunk_header) != 8:
                    break
                chunk_length, chunk_type = struct.unpack("<II", chunk_header)
                chunk_start = offset + 8
                chunk_end = chunk_start + chunk_length
                if chunk_end > limit:
                    result.setdefault("inspection_errors", []).append(
                        "GLB chunk extends beyond declared/file length"
                    )
                    break
                if chunk_type == GLB_JSON_CHUNK:
                    if chunk_length > MAX_GLB_JSON_BYTES:
                        result.setdefault("inspection_errors", []).append(
                            "GLB JSON chunk exceeds safe inspection limit"
                        )
                        break
                    stream.seek(chunk_start)
                    raw_json = stream.read(chunk_length).decode("utf-8", errors="strict")
                    json_document = json.loads(raw_json.rstrip(" \t\r\n\x00"))
                    break
                offset = chunk_end
            if json_document is None:
                result.setdefault("inspection_errors", []).append(
                    "GLB JSON chunk not found or not inspected"
                )
            else:
                result.update(_inspect_gltf_uris(path, json_document))
    except (OSError, ValueError, UnicodeError, json.JSONDecodeError, struct.error) as exc:
        result.setdefault("inspection_errors", []).append(
            f"GLB inspection failed: {type(exc).__name__}: {exc}"
        )
    return result


def _inspect_gltf(path: Path) -> dict:
    result: dict = {"format": "gltf", "inspection_level": "JSON_and_external_URIs"}
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
        result.update(_inspect_gltf_uris(path, document))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        result["inspection_errors"] = [
            f"glTF inspection failed: {type(exc).__name__}: {exc}"
        ]
    return result


def inspect_media(path: Path) -> dict:
    suffix = path.suffix.lower()
    result: dict = {
        "category": MEDIA_TYPES.get(suffix, "unknown"),
        "inspection_level": "format_not_decoded",
    }
    try:
        if suffix == ".glb":
            result.update(_inspect_glb(path))
        elif suffix == ".gltf":
            result.update(_inspect_gltf(path))
        elif suffix == ".wav":
            result["inspection_level"] = "WAV_header"
            with wave.open(str(path), "rb") as stream:
                frames = stream.getnframes()
                rate = stream.getframerate()
                result.update(
                    channels=stream.getnchannels(),
                    sample_width_bytes=stream.getsampwidth(),
                    sample_rate_hz=rate,
                    frame_count=frames,
                    duration_seconds=(frames / rate if rate else None),
                    compression_type=stream.getcomptype(),
                )
        elif suffix == ".png":
            result["inspection_level"] = "PNG_signature_and_IHDR_header"
            with path.open("rb") as stream:
                header = stream.read(24)
            if len(header) < 24 or not header.startswith(b"\x89PNG\r\n\x1a\n"):
                raise ValueError("invalid or truncated PNG header")
            result["width_px"], result["height_px"] = struct.unpack(">II", header[16:24])
        elif suffix == ".svg":
            result["inspection_level"] = "SVG_XML_root"
            root = ET.parse(path).getroot()
            if root.tag.rsplit("}", 1)[-1].lower() != "svg":
                raise ValueError("XML root is not svg")
            result["svg_root_valid"] = True
        elif suffix == ".jpg" or suffix == ".jpeg":
            result["inspection_level"] = "JPEG_signature_only"
            with path.open("rb") as stream:
                header = stream.read(3)
            if header != b"\xff\xd8\xff":
                raise ValueError("invalid JPEG signature")
        elif suffix == ".webp":
            result["inspection_level"] = "WebP_container_header"
            with path.open("rb") as stream:
                header = stream.read(12)
            if len(header) != 12 or header[:4] != b"RIFF" or header[8:12] != b"WEBP":
                raise ValueError("invalid WebP container header")
            result["riff_declared_length_bytes"] = struct.unpack("<I", header[4:8])[0] + 8
        elif suffix == ".ogg":
            result["inspection_level"] = "Ogg_page_signature_only"
            with path.open("rb") as stream:
                if stream.read(4) != b"OggS":
                    raise ValueError("invalid Ogg page signature")
        elif suffix == ".flac":
            result["inspection_level"] = "FLAC_signature_only"
            with path.open("rb") as stream:
                if stream.read(4) != b"fLaC":
                    raise ValueError("invalid FLAC signature")
        elif suffix == ".mp3":
            result["inspection_level"] = "MP3_signature_or_frame_prefix"
            with path.open("rb") as stream:
                header = stream.read(3)
            if not (header == b"ID3" or (len(header) >= 2 and header[0] == 0xFF and header[1] & 0xE0 == 0xE0)):
                raise ValueError("MP3 signature/frame prefix not detected")
        elif suffix == ".mp4":
            result["inspection_level"] = "MP4_ftyp_header"
            with path.open("rb") as stream:
                header = stream.read(12)
            if len(header) < 8 or header[4:8] != b"ftyp":
                raise ValueError("MP4 ftyp box not detected")
        elif suffix == ".webm":
            result["inspection_level"] = "WebM_EBML_header"
            with path.open("rb") as stream:
                header = stream.read(4)
            if header != b"\x1aE\xdf\xa3":
                raise ValueError("WebM EBML header not detected")
        else:
            result["inspection_level"] = "extension_only"
    except (OSError, ValueError, wave.Error, EOFError, struct.error, ET.ParseError) as exc:
        result["inspection_errors"] = [
            f"media inspection failed: {type(exc).__name__}: {exc}"
        ]
    return result


def scan_media(root: Path, manifest_entries: dict[str, dict]) -> list[dict]:
    rows: list[dict] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.is_symlink():
            continue
        relative_parts = path.relative_to(root).parts
        if any(part in IGNORED_DIRECTORY_NAMES for part in relative_parts):
            continue
        suffix = path.suffix.lower()
        if suffix not in MEDIA_TYPES:
            continue
        relative = path.relative_to(root).as_posix()
        manifest_entry = manifest_entries.get(relative)
        if not relative.startswith("assets/"):
            manifest_status = "outside_assets_manifest_scope"
        elif manifest_entry is None:
            manifest_status = "missing"
        else:
            complete = all(
                isinstance(manifest_entry.get(field), str) and bool(manifest_entry[field].strip())
                for field in ("author", "source_url", "license", "license_url", "attribution")
            ) and manifest_entry.get("commercial_use") is True and manifest_entry.get("redistribution_allowed") is True
            manifest_status = "present_fields_complete" if complete else "present_fields_incomplete"
        try:
            size = path.stat().st_size
            digest = sha256_file(path)
        except OSError as exc:
            rows.append({
                "path": relative,
                "extension": suffix,
                "category": MEDIA_TYPES[suffix],
                "sha256": None,
                "size_bytes": None,
                "manifest_status": manifest_status,
                "inspection_errors": [f"file could not be read: {exc}"],
            })
            continue
        media_metadata = inspect_media(path)
        rows.append({
            "path": relative,
            "extension": suffix,
            "category": MEDIA_TYPES[suffix],
            "size_bytes": size,
            "sha256": digest,
            "manifest_status": manifest_status,
            "inspection": media_metadata,
        })
    hash_groups: dict[str, list[dict]] = defaultdict(list)
    for row in rows:
        if row.get("sha256"):
            hash_groups[row["sha256"]].append(row)
    for digest, group in hash_groups.items():
        if len(group) > 1:
            for row in group:
                row["duplicate_count_for_hash"] = len(group)
                row["duplicate_paths"] = sorted(item["path"] for item in group if item["path"] != row["path"])
        else:
            row["duplicate_count_for_hash"] = 1
    return rows


def scan_resource_references(root: Path) -> list[dict]:
    import re
    pattern = re.compile(RESOURCE_PATTERN_TEXT)
    references: list[dict] = []
    for source in sorted(root.rglob("*")):
        if not source.is_file() or source.is_symlink() or source.suffix.lower() not in RESOURCE_SOURCE_SUFFIXES:
            continue
        relative_parts = source.relative_to(root).parts
        if any(part in IGNORED_DIRECTORY_NAMES for part in relative_parts):
            continue
        try:
            lines = source.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for line_number, line in enumerate(lines, 1):
            for match in pattern.finditer(line):
                raw_path = match.group(1).rstrip(".,;]})")
                if not raw_path:
                    continue
                # Subresources such as res://scene.tscn::ExternalResource are one file.
                path_text = raw_path.split("::", 1)[0]
                if not path_text:
                    continue
                target = root / path_text
                if target.is_file() or target.is_dir():
                    continue
                normalized = path_text.replace("\\", "/")
                if normalized in OPTIONAL_RESOURCE_PATHS:
                    classification = "known_optional"
                    rationale = OPTIONAL_RESOURCE_PATHS[normalized]
                else:
                    classification = "missing_reference_candidate"
                    rationale = (
                        "heuristic only: confirm the source line and runtime path; "
                        "dynamic path construction may not be fully represented"
                    )
                references.append({
                    "source_file": source.relative_to(root).as_posix(),
                    "line": line_number,
                    "resource_path": normalized,
                    "classification": classification,
                    "rationale": rationale,
                })
    # A source file may contain the same literal more than once; preserve source lines
    # but drop identical duplicate records for deterministic output.
    unique = {
        (item["source_file"], item["line"], item["resource_path"], item["classification"]): item
        for item in references
    }
    return [unique[key] for key in sorted(unique)]


def build_report(root: Path) -> dict:
    root = root.resolve()
    manifest_entries, manifest_errors = load_manifest(root)
    media_rows = scan_media(root, manifest_entries)
    refs = scan_resource_references(root)
    by_category: dict[str, int] = defaultdict(int)
    by_manifest: dict[str, int] = defaultdict(int)
    for row in media_rows:
        by_category[row["category"]] += 1
        by_manifest[row["manifest_status"]] += 1
    duplicates = [
        {"sha256": digest, "paths": sorted(row["path"] for row in group)}
        for digest, group in _group_by_hash(media_rows).items()
        if len(group) > 1
    ]
    missing_manifest = sorted(
        row["path"] for row in media_rows
        if row["path"].startswith("assets/") and row["manifest_status"] == "missing"
    )
    incomplete_manifest = sorted(
        row["path"] for row in media_rows
        if row["path"].startswith("assets/") and row["manifest_status"] == "present_fields_incomplete"
    )
    return {
        "report_schema_version": 1,
        "scope": "static, offline repository inventory; no assets were downloaded or modified",
        "repository_root": ".",
        "media_file_count": len(media_rows),
        "media_by_category": dict(sorted(by_category.items())),
        "media_by_manifest_status": dict(sorted(by_manifest.items())),
        "manifest_parse_errors": manifest_errors,
        "missing_manifest_entries": missing_manifest,
        "incomplete_manifest_entries": incomplete_manifest,
        "duplicate_file_groups": duplicates,
        "resource_reference_candidate_count": len(refs),
        "resource_reference_candidates": refs,
        "media_files": media_rows,
        "limits": [
            "SHA-256 and byte sizes are calculated for readable files; they do not establish ownership or license rights.",
            "The manifest records claims and permissions; a human must verify the source URL and full license text.",
            "GLB inspection validates the container header and reads its JSON chunk only; it does not render meshes, validate skeletons, inspect materials visually, or certify model quality.",
            "glTF inspection checks referenced buffer/image URIs without fetching remote content; remote and absolute URIs are reported and never downloaded.",
            "WAV technical header metadata is read with the Python standard library; OGG/MP3/FLAC checks are signatures only and do not measure perceived loudness or listening quality.",
            "PNG checks cover signature and dimensions, not complete decoding or CRC verification; JPEG and WebP checks are container/header checks only; SVG XML parsing does not establish safe rendering in Godot.",
            "MP4/WebM checks are header-only; this tool does not decode video, play audio, render a scene, or test an Android device.",
            "Literal res:// scanning is heuristic. Missing-reference candidates may arise from dynamic paths or test fixtures and are warnings, not confirmed defects.",
            "The documented optional player path is classified separately from unexpected missing-reference candidates.",
        ],
    }


def _group_by_hash(rows: list[dict]) -> dict[str, list[dict]]:
    groups: dict[str, list[dict]] = defaultdict(list)
    for row in rows:
        digest = row.get("sha256")
        if digest:
            groups[digest].append(row)
    return groups


def render_markdown(report: dict) -> str:
    lines = [
        "# تقرير الجرد الجنائي الآلي للأصول",
        "",
        "> تقرير ساكن وغير متصل بالشبكة. لا يثبت الترخيص القانوني ولا جودة العرض أو الصوت على الجهاز.",
        "",
        "## ملخص",
        "",
        f"- عدد ملفات الوسائط المعروفة: **{report['media_file_count']}**",
        f"- مجموعات الملفات ذات البصمة المكررة: **{len(report['duplicate_file_groups'])}**",
        f"- أصول داخل assets بلا إدخال manifest: **{len(report['missing_manifest_entries'])}**",
        f"- إدخالات manifest ببيانات ناقصة: **{len(report['incomplete_manifest_entries'])}**",
        f"- مرشحات المراجع المفقودة وفق المسح النصي: **{report['resource_reference_candidate_count']}** (تحتاج تحققًا بشريًا)",
        "",
        "### أنواع الوسائط",
        "",
        "| النوع | العدد |",
        "|---|---:|",
    ]
    for key, value in report["media_by_category"].items():
        lines.append(f"| {key} | {value} |")
    lines += [
        "",
        "## ملفات الوسائط",
        "",
        "| المسار | النوع | الحجم بالبايت | SHA-256 | حالة manifest | مستوى الفحص |",
        "|---|---|---:|---|---|---|",
    ]
    for row in report["media_files"]:
        inspection = row.get("inspection", {})
        digest = row.get("sha256") or "تعذر الحساب"
        level = inspection.get("inspection_level", "تعذر الفحص")
        lines.append(
            f"| `{row['path']}` | {row['category']} | {row.get('size_bytes', '')} | "
            f"`{digest}` | {row['manifest_status']} | {level} |"
        )
    lines += ["", "## مرشحات المراجع المفقودة", ""]
    if not report["resource_reference_candidates"]:
        lines.append("لم يعثر المسح النصي على مرشحات مراجع مفقودة.")
    else:
        lines += [
            "| المصدر | السطر | المسار | التصنيف |",
            "|---|---:|---|---|",
        ]
        for item in report["resource_reference_candidates"]:
            lines.append(
                f"| `{item['source_file']}` | {item['line']} | "
                f"`res://{item['resource_path']}` | {item['classification']} |"
            )
    lines += ["", "## قيود التقرير", ""]
    lines.extend(f"- {item}" for item in report["limits"])
    lines += [
        "",
        "## تفسير القرار",
        "",
        "- يجب تشغيل `tools/validate_free_assets.py` كفحص مانع؛ أي أصل جديد داخل `assets/` بلا بيانات مطلوبة يجب أن يفشل CI.",
        "- لا تُعد مرشحات `res://` عيوبًا مؤكدة حتى تُراجع في Godot أو في سياق الكود.",
        "- لا تُعتمد أي رخصة اعتمادًا على هذا التقرير وحده.",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Build a deterministic, offline media and Godot resource-path inventory."
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="Repository root (defaults to the parent directory of this script).",
    )
    parser.add_argument(
        "--json-output",
        type=Path,
        default=Path("asset-audit-report.json"),
        help="Path for the JSON report (generated locally; not committed automatically).",
    )
    parser.add_argument(
        "--markdown-output",
        type=Path,
        default=Path("asset-audit-report.md"),
        help="Path for the Markdown report (generated locally; not committed automatically).",
    )
    args = parser.parse_args()
    try:
        report = build_report(args.root)
        json_path = args.json_output
        markdown_path = args.markdown_output
        json_path.parent.mkdir(parents=True, exist_ok=True)
        markdown_path.parent.mkdir(parents=True, exist_ok=True)
        json_path.write_text(
            json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        markdown_path.write_text(render_markdown(report), encoding="utf-8")
    except OSError as exc:
        print(f"ERROR: asset audit failed: {exc}", file=sys.stderr)
        return 2
    print(
        f"Asset audit generated: {report['media_file_count']} media file(s), "
        f"{len(report['duplicate_file_groups'])} duplicate group(s), "
        f"{len(report['missing_manifest_entries'])} missing manifest entry/entries, "
        f"{report['resource_reference_candidate_count']} resource reference candidate(s)."
    )
    print(f"JSON: {args.json_output}")
    print(f"Markdown: {args.markdown_output}")
    # Heuristic warnings are intentionally non-fatal. The separate license validator
    # is the CI gate for invalid manifests and media entries without metadata.
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
