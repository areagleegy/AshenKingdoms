#!/usr/bin/env bash
set -euo pipefail

GODOT_VERSION=4.6
GODOT_RELEASE=4.6-stable
GODOT_ZIP_SHA512="0c1bc5e8dca8f892a9a5fd0628b742f399fbd520e5f0051ecac021c0aa4ea5a8f0d237c8ed6b767b2afda7f7a4b32001118f1b04a82e335a5e35b947a1217940"
INSTALL_DIR="$HOME/.local/bin"
CACHE_DIR="$HOME/.cache/ashenkingdoms-godot"

mkdir -p "$INSTALL_DIR" "$CACHE_DIR"

if [[ ! -x "$INSTALL_DIR/godot" ]] || ! "$INSTALL_DIR/godot" --version 2>/dev/null | grep -q "^4\.6\."; then
  curl --fail --location --silent --show-error "https://github.com/godotengine/godot/releases/download/4.6-stable/Godot_v4.6-stable_linux.x86_64.zip" --output "$CACHE_DIR/godot.zip"
  if ! printf '%s  %s\n' "$GODOT_ZIP_SHA512" "$CACHE_DIR/godot.zip" | sha512sum --check --status; then
    echo "Godot archive checksum mismatch; refusing to install." >&2
    rm -f "$CACHE_DIR/godot.zip"
    exit 1
  fi
  rm -rf "$CACHE_DIR/editor"
  mkdir -p "$CACHE_DIR/editor"
  unzip -oq "$CACHE_DIR/godot.zip" -d "$CACHE_DIR/editor"
  GODOT_BINARY="$CACHE_DIR/editor/Godot_v4.6-stable_linux.x86_64"
  if [[ ! -s "$GODOT_BINARY" ]]; then
    echo "Godot archive did not contain the expected executable." >&2
    exit 1
  fi
  install -m 0755 "$GODOT_BINARY" "$INSTALL_DIR/godot"
fi

echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
export PATH="$INSTALL_DIR:$PATH"
godot --version
