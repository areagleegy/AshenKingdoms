#!/usr/bin/env bash
# AshenKingdoms local QA runner. Mirrors the validation workflow's executable checks.
# Usage: bash tools/run_local_qa.sh
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
LOG_DIR="${ASHEN_QA_LOG_DIR:-${TMPDIR:-/tmp}/ashen-kingdoms-qa-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$LOG_DIR"
FAILURES=0
SKIPS=0
export GODOT_SILENCE_ROOT_WARNING=1

echo "AshenKingdoms Local QA"
echo "Project: $ROOT"
echo "Logs:    $LOG_DIR"
echo

run() {
  local name="$1" logfile="$2"; shift 2
  echo "▶ $name"
  if "$@" 2>&1 | tee "$LOG_DIR/$logfile"; then
    echo "  PASS"
  else
    local code=$?
    echo "  FAIL (exit $code; see $LOG_DIR/$logfile)"
    FAILURES=$((FAILURES + 1))
  fi
  echo
}

skip() {
  echo "  SKIP: $1"
  SKIPS=$((SKIPS + 1))
}

required=(python3)
for command_name in "${required[@]}"; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "ERROR: required command '$command_name' not found."
    exit 2
  fi
done

run "Diagnostics classifier unit tests" diagnostics-unit-tests.log \
  python3 -m unittest discover -s tools -p 'test_ai_test_diagnostics.py' -v
run "Diagnostic benchmark" diagnostic-benchmark.log \
  python3 tools/diagnostic_benchmark.py --corpus tools/diagnostic_cases.json \
  --output "$LOG_DIR/diagnostic-benchmark.json" --summary "$LOG_DIR/summary.md"
run "Validate Markdown links" validate-docs.log python3 tools/validate_docs.py
run "Validate asset licenses and manifest" validate-assets.log python3 tools/validate_free_assets.py
run "Compile and inspect player asset generator" player-generator.log bash -c \
  'python3 -m py_compile tools/generate_player_glb.py tools/validate_free_assets.py && python3 tools/generate_player_glb.py --help >/dev/null'

if command -v godot >/dev/null 2>&1; then
  run "Godot version" godot-version.log godot --version
  run "Import and parse project" godot-import.log godot --headless --path . --editor --quit

  for pair in \
    "Load all scripts and scenes|resource-smoke.log|res://tests/script_load_smoke_test.gd" \
    "Gameplay smoke tests|gameplay-smoke.log|res://tests/gameplay_smoke_test.gd" \
    "Gameplay regression tests|gameplay-regression.log|res://tests/gameplay_regression_test.gd" \
    "Player character smoke tests|player-character.log|res://tests/player_character_smoke_test.gd" \
    "Content catalog smoke tests|content-catalog.log|res://tests/content_catalog_smoke_test.gd" \
    "Save system security regression tests|save-security.log|res://tests/save_system_security_test.gd" \
    "Network RPC security regression tests|network-rpc-security.log|res://tests/network_rpc_security_test.gd"; do
    IFS='|' read -r name logfile test_path <<< "$pair"
    if [[ -f "${test_path#res://}" ]]; then
      run "$name" "$logfile" godot --headless --path . --script "$test_path"
    else
      echo "  FAIL: required CI test is missing: $test_path"
      FAILURES=$((FAILURES + 1))
    fi
  done

  if [[ -f tests/network_combat_smoke_test.tscn ]]; then
    run "Network combat smoke test (45s limit)" network-combat.log \
      timeout 45s godot --headless --path . res://tests/network_combat_smoke_test.tscn
  else
    echo "  FAIL: missing tests/network_combat_smoke_test.tscn"
    FAILURES=$((FAILURES + 1))
  fi

  if [[ -x tools/test-network-loopback.sh || -f tools/test-network-loopback.sh ]]; then
    run "Local ENet host/client integration" network-loopback.log bash tools/test-network-loopback.sh
  else
    echo "  FAIL: missing tools/test-network-loopback.sh"
    FAILURES=$((FAILURES + 1))
  fi
else
  skip "Godot executable not found in PATH; all Godot tests were skipped."
fi

run "Python content package and signature tests" python-tests.log \
  python3 -m unittest tools.test_package_content tools.test_sign_content_catalog -v

if command -v gdlint >/dev/null 2>&1; then
  run "GDScript lint (no repository lint config assumed)" gdlint.log gdlint scripts/ scenes/ tests/
else
  skip "gdlint is optional and is not part of the current CI workflow; install gdtoolkit to enable it."
fi

echo "========================================"
echo "Failures: $FAILURES"
echo "Skipped optional checks: $SKIPS"
echo "Logs: $LOG_DIR"
if (( FAILURES > 0 )); then
  exit 1
fi
echo "All checks that could run completed successfully."
