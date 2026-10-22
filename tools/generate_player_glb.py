#!/usr/bin/env python3
"""Generate a player GLB with the Meshy Image-to-3D API.

The API key is read only from MESHY_API_KEY. Never place it in project files,
Godot resources, command-line arguments, or source control.
"""

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import os
import struct
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

API_BASE = "https://api.meshy.ai/openapi/v1"
REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = REPO_ROOT / "assets" / "characters" / "player" / "player.glb"
MAX_IMAGE_BYTES = 20 * 1024 * 1024
MAX_API_RESPONSE_BYTES = 4 * 1024 * 1024
MAX_MODEL_BYTES = 300 * 1024 * 1024
MAX_GLTF_JSON_BYTES = 32 * 1024 * 1024
GLB_JSON_CHUNK_TYPE = 0x4E4F534A
GLB_BIN_CHUNK_TYPE = 0x004E4942
SUPPORTED_MIME_TYPES = {"image/jpeg", "image/png", "image/webp"}


class MeshyError(RuntimeError):
    """Raised for actionable Meshy API or downloaded asset failures."""


def _read_image_reference(image_url: str | None, image_file: Path | None) -> str:
    if image_url:
        if image_url.lower().startswith("data:"):
            metadata, separator, encoded = image_url.partition(",")
            mime_type = metadata[5:].split(";", 1)[0].lower() if metadata.lower().startswith("data:") else ""
            if not separator or metadata.lower() != f"data:{mime_type};base64" or mime_type not in SUPPORTED_MIME_TYPES:
                raise MeshyError("--image-url data URI must be base64 JPG, PNG, or WEBP.")
            max_encoded_length = 4 * ((MAX_IMAGE_BYTES + 2) // 3)
            if not encoded or len(encoded) > max_encoded_length:
                raise MeshyError("Reference image data URI exceeds the 20 MiB safety limit.")
            try:
                decoded_image = base64.b64decode(encoded, validate=True)
            except (ValueError, base64.binascii.Error) as exc:
                raise MeshyError("--image-url data URI contains invalid base64.") from exc
            if not decoded_image or len(decoded_image) > MAX_IMAGE_BYTES:
                raise MeshyError("Reference image must be non-empty and no larger than 20 MiB.")
            return image_url

        parsed = urlparse(image_url)
        if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
            raise MeshyError("--image-url must be a public HTTPS URL without embedded credentials or a supported data URI.")
        return image_url

    if image_file is None:
        raise MeshyError("Provide --image-url or --image-file.")
    if not image_file.is_file():
        raise MeshyError(f"Reference image does not exist: {image_file}")

    size = image_file.stat().st_size
    if size <= 0 or size > MAX_IMAGE_BYTES:
        raise MeshyError("Reference image must be non-empty and no larger than 20 MiB.")

    mime_type, _ = mimetypes.guess_type(str(image_file))
    if mime_type not in SUPPORTED_MIME_TYPES:
        raise MeshyError("Reference image must be JPG, PNG, or WEBP.")
    encoded = base64.b64encode(image_file.read_bytes()).decode("ascii")
    return f"data:{mime_type};base64,{encoded}"


def _request_json(
    url: str,
    method: str,
    api_key: str,
    payload: dict[str, Any] | None = None,
    timeout: int = 120,
) -> tuple[dict[str, Any], dict[str, str]]:
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Accept": "application/json",
        "User-Agent": "AshenKingdoms-AssetPipeline/1.0",
    }
    data = None
    if payload is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(payload).encode("utf-8")

    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read(MAX_API_RESPONSE_BYTES + 1)
            if len(raw) > MAX_API_RESPONSE_BYTES:
                raise MeshyError("Meshy API response exceeds the 4 MiB safety limit.")
            decoded = json.loads(raw.decode("utf-8"))
            if not isinstance(decoded, dict):
                raise MeshyError("Meshy returned an unexpected JSON response.")
            return decoded, {key.lower(): value for key, value in response.headers.items()}
    except urllib.error.HTTPError as exc:
        # Do not print request headers or the API key.
        detail = exc.read(8192).decode("utf-8", errors="replace")
        if exc.code == 401:
            message = "Meshy rejected the API key (401). Check MESHY_API_KEY."
        elif exc.code == 402:
            message = "Meshy reports insufficient credits (402). No further requests were sent."
        elif exc.code == 429:
            message = "Meshy rate limit reached (429). Wait before retrying."
        else:
            message = f"Meshy API HTTP error {exc.code}."
        raise MeshyError(f"{message}\n{detail}") from exc
    except urllib.error.URLError as exc:
        raise MeshyError(f"Network request failed: {exc.reason}") from exc
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise MeshyError("Meshy returned invalid JSON.") from exc


def _download_glb(url: str, output: Path, force: bool) -> None:
    parsed = urlparse(url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise MeshyError("The returned model URL must be HTTPS without embedded credentials.")
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists() and not force:
        raise MeshyError(f"Output already exists: {output}. Use --force to replace it.")

    partial = output.with_suffix(output.suffix + ".part")
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "AshenKingdoms-AssetPipeline/1.0"},
    )
    total = 0
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            # urllib follows redirects; reject a final HTTP URL to prevent a TLS downgrade.
            final_url = urlparse(response.geturl())
            if final_url.scheme != "https" or not final_url.hostname or final_url.username or final_url.password:
                raise MeshyError("The final model download URL must remain HTTPS without URL credentials.")
            with partial.open("wb") as target:
                while True:
                    chunk = response.read(1024 * 1024)
                    if not chunk:
                        break
                    total += len(chunk)
                    if total > MAX_MODEL_BYTES:
                        raise MeshyError("Downloaded model exceeds the 300 MiB safety limit.")
                    target.write(chunk)

        _validate_glb_container(partial)
        # os.replace performs the final atomic promotion. Keep any previous good
        # output intact unless the validated replacement can actually be committed.
        os.replace(partial, output)
    except Exception:
        try:
            partial.unlink(missing_ok=True)
        except OSError:
            pass
        raise


def _validate_glb_container(path: Path) -> None:
    """Validate GLB 2.0 framing, chunk bounds, and the mandatory glTF JSON document."""
    try:
        actual_size = path.stat().st_size
    except OSError as exc:
        raise MeshyError("Downloaded GLB could not be inspected.") from exc
    if actual_size < 20 or actual_size > MAX_MODEL_BYTES:
        raise MeshyError("Downloaded GLB size is outside the valid safety bounds.")

    try:
        with path.open("rb") as model_file:
            header = model_file.read(12)
            if len(header) != 12:
                raise MeshyError("Downloaded GLB has a truncated header.")
            magic, version, declared_length = struct.unpack("<4sII", header)
            if magic != b"glTF":
                raise MeshyError("Downloaded file is not a binary glTF (GLB) model.")
            if version != 2:
                raise MeshyError("Downloaded GLB must use binary glTF version 2.")
            if declared_length != actual_size:
                raise MeshyError("GLB declared length does not match the downloaded file size.")

            offset = 12
            chunk_index = 0
            saw_json = False
            saw_binary = False
            while offset < declared_length:
                remaining = declared_length - offset
                if remaining < 8:
                    raise MeshyError("GLB contains a truncated chunk header.")
                chunk_header = model_file.read(8)
                if len(chunk_header) != 8:
                    raise MeshyError("GLB contains a truncated chunk header.")
                chunk_length, chunk_type = struct.unpack("<II", chunk_header)
                offset += 8

                if chunk_length % 4 != 0:
                    raise MeshyError("GLB chunk lengths must be aligned to four bytes.")
                if chunk_length > declared_length - offset:
                    raise MeshyError("GLB chunk extends beyond the declared container length.")
                if chunk_index == 0 and chunk_type != GLB_JSON_CHUNK_TYPE:
                    raise MeshyError("The first GLB chunk must contain the glTF JSON document.")

                if chunk_type == GLB_JSON_CHUNK_TYPE:
                    if saw_json or chunk_index != 0:
                        raise MeshyError("GLB must contain exactly one JSON chunk, first in the container.")
                    if chunk_length == 0 or chunk_length > MAX_GLTF_JSON_BYTES:
                        raise MeshyError("GLB JSON chunk is empty or exceeds the JSON safety limit.")
                    json_bytes = model_file.read(chunk_length)
                    if len(json_bytes) != chunk_length:
                        raise MeshyError("GLB JSON chunk is truncated.")
                    try:
                        document = json.loads(json_bytes.decode("utf-8"))
                    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                        raise MeshyError("GLB JSON chunk is not valid UTF-8 JSON.") from exc
                    if not isinstance(document, dict):
                        raise MeshyError("GLB JSON document must be an object.")
                    asset = document.get("asset")
                    if not isinstance(asset, dict) or asset.get("version") != "2.0":
                        raise MeshyError("GLB JSON document must declare asset.version '2.0'.")
                    saw_json = True
                else:
                    if not saw_json:
                        raise MeshyError("GLB contains data before the mandatory JSON chunk.")
                    if chunk_type == GLB_BIN_CHUNK_TYPE:
                        if saw_binary:
                            raise MeshyError("GLB may contain at most one BIN chunk.")
                        if chunk_index != 1:
                            raise MeshyError("The optional GLB BIN chunk must appear second.")
                        saw_binary = True
                    # Read in bounded blocks instead of seeking: seeking beyond EOF
                    # can hide a truncated BIN/extension chunk.
                    remaining_chunk_bytes = chunk_length
                    while remaining_chunk_bytes:
                        block = model_file.read(min(1024 * 1024, remaining_chunk_bytes))
                        if not block:
                            raise MeshyError("GLB chunk data is truncated.")
                        remaining_chunk_bytes -= len(block)

                offset += chunk_length
                chunk_index += 1

            if offset != declared_length or not saw_json:
                raise MeshyError("GLB chunk layout does not fill the declared container.")
    except OSError as exc:
        raise MeshyError("Downloaded GLB could not be read completely.") from exc


def generate(args: argparse.Namespace) -> Path:
    api_key = os.environ.get("MESHY_API_KEY", "").strip()
    if not api_key:
        raise MeshyError(
            "MESHY_API_KEY is not set. Create/use an authorized API key in Meshy, "
            "then export it in your local terminal. Do not paste it into chat or commit it."
        )

    image_reference = _read_image_reference(args.image_url, args.image_file)
    payload: dict[str, Any] = {
        "image_url": image_reference,
        "ai_model": args.ai_model,
        "should_texture": True,
        "enable_pbr": False,
        "should_remesh": True,
        "target_polycount": args.target_polycount,
        "pose_mode": "a-pose",
        "target_formats": ["glb"],
        "auto_size": True,
        "origin_at": "bottom",
    }

    print("Creating Meshy Image-to-3D task; this may consume account credits.")
    created, _ = _request_json(
        f"{API_BASE}/image-to-3d",
        "POST",
        api_key,
        payload,
        timeout=120,
    )
    task_id = created.get("result") or created.get("id")
    if not isinstance(task_id, str) or not task_id:
        raise MeshyError(f"Task creation response did not include an ID: {created}")
    print(f"Task created: {task_id}")

    deadline = time.monotonic() + args.timeout_minutes * 60
    last_status = ""
    while time.monotonic() < deadline:
        task, response_headers = _request_json(
            f"{API_BASE}/image-to-3d/{task_id}",
            "GET",
            api_key,
            timeout=60,
        )
        status = str(task.get("status", "")).upper()
        progress = task.get("progress")
        if status != last_status:
            suffix = f" ({progress}%)" if isinstance(progress, (int, float)) else ""
            print(f"Status: {status or 'UNKNOWN'}{suffix}")
            last_status = status

        if status == "SUCCEEDED":
            model_urls = task.get("model_urls")
            model_url = model_urls.get("glb") if isinstance(model_urls, dict) else None
            if not isinstance(model_url, str) or not model_url:
                raise MeshyError("Task succeeded but the response has no GLB download URL.")
            _download_glb(model_url, args.output, args.force)
            print(f"GLB saved and validated: {args.output}")
            print("Next: import the project in Godot, run Ashen Asset Bridge, and validate the model.")
            return args.output

        if status in {"FAILED", "CANCELED", "CANCELLED", "EXPIRED"}:
            error = task.get("task_error", {})
            reason = error.get("message", "No error details supplied.") if isinstance(error, dict) else str(error)
            raise MeshyError(f"Generation ended with status {status}: {reason}")

        retry_after = response_headers.get("retry-after", "")
        try:
            delay = max(2, min(int(float(retry_after)), 30)) if retry_after else args.poll_seconds
        except ValueError:
            delay = args.poll_seconds
        time.sleep(max(2, min(delay, 30)))

    raise MeshyError(
        f"Polling timed out after {args.timeout_minutes} minutes. Task ID: {task_id}. "
        "The task may still be running; check it in Meshy before creating another task."
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate assets/characters/player/player.glb from a reference image using Meshy."
    )
    image_group = parser.add_mutually_exclusive_group(required=True)
    image_group.add_argument("--image-url", help="Public HTTPS image URL or supported base64 JPG/PNG/WEBP data URI.")
    image_group.add_argument("--image-file", type=Path, help="Local JPG, PNG, or WEBP image.")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT, help="Output GLB path.")
    parser.add_argument(
        "--ai-model",
        choices=("meshy-6-lite", "meshy-6", "meshy-7.1", "latest"),
        default="meshy-7.1",
        help="Meshy model. API availability and credit cost depend on your plan.",
    )
    parser.add_argument(
        "--target-polycount",
        type=int,
        default=20000,
        help="Target face count when remeshing (100-300000; actual result may vary).",
    )
    parser.add_argument("--timeout-minutes", type=int, default=45, help="Maximum polling duration.")
    parser.add_argument("--poll-seconds", type=int, default=5, help="Seconds between task checks.")
    parser.add_argument("--force", action="store_true", help="Replace an existing output GLB.")
    parser.add_argument(
        "--confirm-credits",
        action="store_true",
        help="Required acknowledgement that the generation request may consume Meshy credits.",
    )
    args = parser.parse_args()
    if not 100 <= args.target_polycount <= 300000:
        parser.error("--target-polycount must be between 100 and 300000.")
    if not 1 <= args.timeout_minutes <= 180:
        parser.error("--timeout-minutes must be between 1 and 180.")
    if not 2 <= args.poll_seconds <= 30:
        parser.error("--poll-seconds must be between 2 and 30.")
    if not args.confirm_credits:
        parser.error(
            "Generation is not started by default. Review your Meshy credit balance, then add --confirm-credits."
        )
    if args.output.suffix.lower() != ".glb":
        parser.error("--output must end with .glb.")
    return args


def main() -> int:
    try:
        args = parse_args()
        generate(args)
        return 0
    except MeshyError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("\nCanceled locally. A submitted remote task may continue; check Meshy before retrying.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
