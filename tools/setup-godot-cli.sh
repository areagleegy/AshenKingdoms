#!/usr/bin/env bash
set -euo pipefail

GODOT_VERSION=4.6
GODOT_RELEASE=4.6-stable
INSTALL_DIR="$HOME/.local/bin"
CACHE_DIR="$HOME/.cache/ashenkingdoms-godot"

mkdir -p "$INSTALL_DIR" "$CACHE_DIR"

if [[ ! -x "$INSTALL_DIR/godot" ]] || ! "$INSTALL_DIR/godot" --version 2>/dev/null | grep -q "^4\.6\."; then
  curl --fail --location --silent --show-error "https://github.com/godotengine/godot/releases/download/4.6-stable/Godot_v4.6-stable_linux.x86_64.zip" --output "$CACHE_DIR/godot.zip"
  unzip -oq "$CACHE_DIR/godot.zip" -d "$CACHE_DIR/editor"
  install -m 0755 "$CACHE_DIR/editor/Godot_v4.6-stable_linux.x86_64" "$INSTALL_DIR/godot"
fi

echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
export PATH="$INSTALL_DIR:$PATH"
godot --version
