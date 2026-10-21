#!/usr/bin/env bash
set -euo pipefail

export GODOT_SILENCE_ROOT_WARNING=1
export ASHEN_TEST_PORT="$((40000 + RANDOM % 20000))"

server_log="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ashen-network-server.log"
server_pid=""

cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

echo "[network-loopback] starting host on UDP port $ASHEN_TEST_PORT"
godot --headless --path . -- --server --server-port="$ASHEN_TEST_PORT" >"$server_log" 2>&1 &
server_pid=$!

server_ready=0
for _ in $(seq 1 40); do
  if ! kill -0 "$server_pid" >/dev/null 2>&1; then
    echo "Host process exited before binding its UDP port."
    cat "$server_log"
    exit 1
  fi
  if command -v ss >/dev/null 2>&1; then
    if ss -lun | grep -Eq "[:.]$ASHEN_TEST_PORT[[:space:]]"; then server_ready=1; break; fi
  elif command -v lsof >/dev/null 2>&1; then
    if lsof -nP -iUDP:"$ASHEN_TEST_PORT" >/dev/null 2>&1; then server_ready=1; break; fi
  elif command -v netstat >/dev/null 2>&1; then
    if netstat -an 2>/dev/null | grep -Eq "[:.]$ASHEN_TEST_PORT[[:space:]]"; then server_ready=1; break; fi
  else
    echo "No UDP inspection utility found; proceeding to the real client connection test."
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
timeout 20s godot --headless --path . --script res://tests/network_client_smoke_test.gd
client_status=$?
set -e

if [[ "$client_status" -ne 0 ]]; then
  echo "Client integration test failed (exit $client_status); host log follows:"
  cat "$server_log"
  exit "$client_status"
fi

echo "[network-loopback] host/client integration passed"
