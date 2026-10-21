#!/usr/bin/env bash
set -euo pipefail

export GODOT_SILENCE_ROOT_WARNING=1
export ASHEN_TEST_PORT="$((40000 + RANDOM % 20000))"
server_log="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ashen-network-reconnect-server.log"
server_pid=""
cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

godot --headless --path . -- --server --server-port="$ASHEN_TEST_PORT" >"$server_log" 2>&1 &
server_pid=$!
server_ready=0
for _ in $(seq 1 60); do
  if ! kill -0 "$server_pid" >/dev/null 2>&1; then
    cat "$server_log"
    exit 1
  fi
  if ss -lun | grep -Eq "[:.]$ASHEN_TEST_PORT[[:space:]]"; then
    server_ready=1
    break
  fi
  sleep 0.25
done
if [[ "$server_ready" -ne 1 ]]; then
  echo "Host did not bind its UDP port in time."
  cat "$server_log"
  exit 1
fi

set +e
timeout 35s godot --headless --path . --script res://tests/network_reconnect_client_test.gd
status=$?
set -e
if [[ "$status" -ne 0 ]]; then
  echo "Reconnect test failed; host log follows:"
  cat "$server_log"
  exit "$status"
fi
echo "[network-reconnect] disconnect/reconnect integration passed"
