#!/usr/bin/env bash
set -euo pipefail

export GODOT_SILENCE_ROOT_WARNING=1
export ASHEN_TEST_PORT="$((40000 + RANDOM % 20000))"
export ASHEN_TEST_COMBAT=1

server_log="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ashen-network-server.log"
client_log="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ashen-network-client.log"
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
timeout 35s godot --headless --path . --script res://tests/network_client_smoke_test.gd >"$client_log" 2>&1
client_status=$?
set -e

cat "$client_log"
if [[ "$client_status" -ne 0 ]]; then
  echo "Client integration test failed (exit $client_status); host log follows:"
  cat "$server_log"
  exit "$client_status"
fi

for rejection in non_finite min_interval rate_window; do
  if ! grep -Fq "[combat-input] rejected=${rejection} peer=" "$server_log"; then
    echo "Missing expected server-side input rejection diagnostic: ${rejection}"
    echo "--- host log ---"
    cat "$server_log"
    echo "--- client log ---"
    cat "$client_log"
    exit 1
  fi
  echo "[PASS] server rejected input for guard: ${rejection}"
done

server_health="$(sed -n 's/.*\[combat-server\] enemy_health slot=1 health=\([0-9][0-9]*\.[0-9][0-9]\).*/\1/p' "$server_log" | head -n 1)"
client_health="$(sed -n 's/.*\[combat-client\] enemy_health slot=1 health=\([0-9][0-9]*\.[0-9][0-9]\).*/\1/p' "$client_log" | head -n 1)"
if [[ -z "$server_health" || -z "$client_health" ]]; then
  echo "Could not extract the first authoritative/client enemy-health observations."
  echo "--- host log ---"
  cat "$server_log"
  echo "--- client log ---"
  cat "$client_log"
  exit 1
fi
if [[ "$server_health" != "$client_health" ]]; then
  echo "Server/client enemy-health mismatch: server=$server_health client=$client_health"
  echo "--- host log ---"
  cat "$server_log"
  exit 1
fi

echo "[PASS] server and client observed identical enemy health: $server_health"
echo "[network-loopback] host/client integration passed"
