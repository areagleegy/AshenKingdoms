#!/usr/bin/env bash
set -euo pipefail
mode="${1:-}"
case "$mode" in
  web)
    mkdir -p build/test-lab/web
    godot --headless --path . --export-release "Web" build/test-lab/web/index.html
    test -s build/test-lab/web/index.html
    ;;
  android)
    mkdir -p build/test-lab/android
    godot --headless --path . --export-debug "Android" build/test-lab/android/AshenKingdoms.apk
    test -s build/test-lab/android/AshenKingdoms.apk
    ;;
  *)
    echo "Usage: $0 web|android" >&2
    exit 2
    ;;
esac
