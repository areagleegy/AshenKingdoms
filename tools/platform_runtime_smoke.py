#!/usr/bin/env python3
"""Run an exported Godot executable and fail on startup/runtime errors."""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path
from typing import Sequence


class SmokeTestError(RuntimeError):
    """Raised when an exported game fails the runtime smoke contract."""


_RUNTIME_ERROR = re.compile(
    r"(?im)^\s*(?:SCRIPT ERROR:|ERROR:|\[FAIL\])"
)
_ENGINE_BANNER = re.compile(r"Godot Engine v\d+\.\d+")


def check_runtime_output(output: str, exit_code: int) -> None:
    """Require a clean exit, an identifiable Godot runtime, and no error lines."""
    if exit_code != 0:
        raise SmokeTestError(f"process exited with status {exit_code}")
    if not _ENGINE_BANNER.search(output):
        raise SmokeTestError("no Godot Engine version banner was observed")
    match = _RUNTIME_ERROR.search(output)
    if match:
        line_number = output[:match.start()].count("\n") + 1
        line = output.splitlines()[line_number - 1].strip()
        raise SmokeTestError(f"runtime error at output line {line_number}: {line}")


def run_smoke(
    command: Sequence[str],
    *,
    timeout_seconds: float = 30.0,
    log_path: Path | None = None,
) -> str:
    """Execute a command with a timeout and enforce the runtime-output contract."""
    if not command:
        raise SmokeTestError("no executable command was supplied")
    if timeout_seconds <= 0:
        raise SmokeTestError("timeout must be greater than zero")

    try:
        completed = subprocess.run(
            list(command),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout_seconds,
            check=False,
        )
        output = completed.stdout or ""
        if log_path is not None:
            log_path.parent.mkdir(parents=True, exist_ok=True)
            log_path.write_text(output, encoding="utf-8")
        if output:
            print(output, end="" if output.endswith("\n") else "\n")
        check_runtime_output(output, completed.returncode)
        return output
    except subprocess.TimeoutExpired as exc:
        captured = exc.stdout or ""
        if isinstance(captured, bytes):
            captured = captured.decode("utf-8", errors="replace")
        if log_path is not None:
            log_path.parent.mkdir(parents=True, exist_ok=True)
            log_path.write_text(captured, encoding="utf-8")
        if captured:
            print(captured, end="" if captured.endswith("\n") else "\n")
        raise SmokeTestError(
            f"process exceeded its {timeout_seconds:g}-second timeout"
        ) from exc


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("--log", type=Path)
    parser.add_argument(
        "command",
        nargs=argparse.REMAINDER,
        help="command to execute; place it after --",
    )
    args = parser.parse_args()
    command = list(args.command)
    if command and command[0] == "--":
        command.pop(0)
    try:
        run_smoke(command, timeout_seconds=args.timeout, log_path=args.log)
    except SmokeTestError as exc:
        print(f"[FAIL] {exc}", file=sys.stderr)
        return 1
    print("[PASS] exported runtime started and exited cleanly")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
