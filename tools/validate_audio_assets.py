#!/usr/bin/env python3
"""Inspect WAV files, verify detailed manifest metadata, and emit SHA-256 evidence."""
from __future__ import annotations

import hashlib
import json
import math
import struct
import sys
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "assets" / "asset_manifest.json"
AUDIO_ROOT = ROOT / "assets" / "audio"
FIELDS = (
    "codec", "duration_seconds", "sample_rate_hz", "channels",
    "bit_depth", "file_size_bytes", "sha256", "peak_fraction", "rms_fraction",
)


def inspect_wav(path: Path) -> dict[str, object]:
    raw = path.read_bytes()
    with wave.open(str(path), "rb") as stream:
        channels = stream.getnchannels()
        sample_rate = stream.getframerate()
        sample_width = stream.getsampwidth()
        frame_count = stream.getnframes()
        compression = stream.getcomptype()
        frames = stream.readframes(frame_count)
    if compression != "NONE" or sample_width != 2:
        raise ValueError(f"Expected uncompressed PCM16: {path.relative_to(ROOT)}")
    sample_count = len(frames) // 2
    samples = struct.unpack("<" + "h" * sample_count, frames) if sample_count else ()
    peak = max((abs(sample) for sample in samples), default=0)
    rms = math.sqrt(sum(sample * sample for sample in samples) / max(sample_count, 1))
    duration = frame_count / sample_rate if sample_rate else 0.0
    return {
        "codec": "WAV PCM signed 16-bit",
        "duration_seconds": round(duration, 3),
        "sample_rate_hz": sample_rate,
        "channels": channels,
        "bit_depth": sample_width * 8,
        "file_size_bytes": len(raw),
        "sha256": hashlib.sha256(raw).hexdigest(),
        "peak_fraction": round(peak / 32768.0, 5),
        "rms_fraction": round(rms / 32768.0, 5),
        "_duration": duration,
        "_peak": peak / 32768.0,
    }


def main() -> int:
    try:
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"ERROR: cannot read asset manifest: {exc}", file=sys.stderr)
        return 1
    entries = {
        item.get("path"): item
        for item in manifest.get("assets", [])
        if isinstance(item, dict) and isinstance(item.get("path"), str)
    }
    paths = sorted(AUDIO_ROOT.rglob("*.wav"))
    errors: list[str] = []
    reports: list[dict[str, object]] = []
    for path in paths:
        relative = path.relative_to(ROOT).as_posix()
        entry = entries.get(relative)
        if entry is None:
            errors.append(f"{relative}: missing asset manifest entry")
            continue
        try:
            actual = inspect_wav(path)
        except (OSError, wave.Error, ValueError, struct.error) as exc:
            errors.append(f"{relative}: cannot inspect WAV: {exc}")
            continue
        if not 0.05 <= float(actual["_duration"]) <= 10.0:
            errors.append(f"{relative}: duration is outside 0.05–10 seconds")
        if actual["sample_rate_hz"] != 22050:
            errors.append(f"{relative}: expected 22050 Hz")
        if actual["channels"] != 1 or actual["bit_depth"] != 16:
            errors.append(f"{relative}: expected mono PCM16")
        if float(actual["_peak"]) >= 0.99999:
            errors.append(f"{relative}: digital clipping at or near full scale")
        for field in FIELDS:
            if field not in entry:
                errors.append(f"{relative}: manifest is missing {field}")
                continue
            expected, got = entry[field], actual[field]
            if field in {"duration_seconds", "peak_fraction", "rms_fraction"}:
                try:
                    same = abs(float(expected) - float(got)) <= 0.00002
                except (TypeError, ValueError):
                    same = False
            else:
                same = expected == got
            if not same:
                errors.append(f"{relative}: manifest mismatch for {field}: {expected!r} != {got!r}")
        reports.append({"path": relative, **{key: actual[key] for key in FIELDS}})
    if not paths:
        errors.append("No WAV files were found under assets/audio/.")
    print(json.dumps({"wav_count": len(paths), "files": reports}, ensure_ascii=False, indent=2))
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        print(f"Audio asset validation failed: {len(errors)} issue(s).", file=sys.stderr)
        return 1
    print(f"Audio asset validation passed: {len(paths)} WAV file(s), metadata and SHA-256 verified.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
