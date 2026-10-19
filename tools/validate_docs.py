#!/usr/bin/env python3
"""Check repository-local links in Markdown files.

External URLs and fragment-only links are intentionally skipped. Fenced code
blocks are ignored so example commands/snippets do not create false positives.
Uses only the Python standard library.
"""

from __future__ import annotations

import posixpath
import re
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
LINK_RE = re.compile(r"!?\[[^\]]*\]\(\s*(<[^>]+>|[^)\s]+)")
FENCE_OPEN_RE = re.compile(r"^ {0,3}(`{3,}|~{3,})")
MARKDOWN_SKIP_DIRS = {".git", ".godot", "build", "node_modules"}


def without_fenced_code(text: str) -> str:
    """Blank fenced code lines without changing line numbers."""
    output: list[str] = []
    fence_char = ""
    fence_length = 0

    for line in text.splitlines():
        if not fence_char:
            match = FENCE_OPEN_RE.match(line)
            if match:
                marker = match.group(1)
                fence_char = marker[0]
                fence_length = len(marker)
                output.append("")
                continue
            output.append(line)
            continue

        close_re = re.compile(rf"^ {{0,3}}{re.escape(fence_char)}{{{fence_length},}}\s*$")
        output.append("")
        if close_re.match(line):
            fence_char = ""
            fence_length = 0

    return "\n".join(output)


def markdown_files() -> list[Path]:
    files: list[Path] = []
    for path in ROOT.rglob("*.md"):
        relative_parts = path.relative_to(ROOT).parts
        if any(part in MARKDOWN_SKIP_DIRS for part in relative_parts):
            continue
        files.append(path)
    return sorted(files)


def local_target_exists(source: Path, raw_target: str) -> bool:
    target = raw_target.strip()
    if target.startswith("<") and target.endswith(">"):
        target = target[1:-1]

    parsed = urlsplit(target)
    if parsed.scheme or parsed.netloc:
        return True
    if not parsed.path:
        return True  # Fragment-only link.
    target_path = unquote(parsed.path)

    if target_path.startswith("/"):
        candidate = ROOT / target_path.lstrip("/")
    else:
        candidate = source.parent / target_path

    normalized = Path(posixpath.normpath(candidate.as_posix()))
    if normalized.is_file():
        return True
    if normalized.is_dir():
        return (normalized / "README.md").is_file() or (normalized / "index.md").is_file()
    return False


def main() -> int:
    broken: list[str] = []
    files = markdown_files()

    for source in files:
        text = without_fenced_code(source.read_text(encoding="utf-8"))
        for match in LINK_RE.finditer(text):
            target = match.group(1).strip()
            if target.startswith("<") and target.endswith(">"):
                target = target[1:-1]
            if not local_target_exists(source, target):
                line = text.count("\n", 0, match.start()) + 1
                relative_source = source.relative_to(ROOT).as_posix()
                broken.append(f"{relative_source}:{line}: missing local Markdown target: {target}")

    if broken:
        print("Broken local Markdown links:")
        for item in broken:
            print(f" - {item}")
        return 1

    print(f"Validated {len(files)} Markdown files: no broken local links found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
