#!/usr/bin/env bash
set -euo pipefail

export GODOT_SILENCE_ROOT_WARNING=1
export ASHEN_TEST_PORT="$((40000 + RANDOM % 20000))"
export ASHEN_STRESS_CLIENTS=8
server_log="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ashen-network-stress-server.log"
client_log_dir="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ashen-network-stress-clients"
mkdir -p "$client_log_dir"
server_pid=""
client_pids=()

cleanup() {
  for pid in "${client_pids[@]:-}"; do
    kill "$pid" >/dev/null 2>&1 || true
  done
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

echo "[network-stress] starting host on UDP port $ASHEN_TEST_PORT"
godot --headless --path . -- --server --server-port="$ASHEN_TEST_PORT" >"$server_log" 2>&1 &
server_pid=$!

server_ready=0
for _ in $(seq 1 60); do
  if ! kill -0 "$server_pid" >/dev/null 2>&1; then
    echo "Host exited before binding its UDP port."
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

for client in $(seq 1 "$ASHEN_STRESS_CLIENTS"); do
  (
    export ASHEN_TEST_CLIENT_ID="$client"
    timeout 30s godot --headless --path . --script res://tests/network_stress_client_test.gd
  ) >"$client_log_dir/client-$client.log" 2>&1 &
  client_pids+=("$!")
done

status=0
for index in "${!client_pids[@]}"; do
  pid="${client_pids[$index]}"
  if ! wait "$pid"; then
    status=1
    echo "[network-stress] client $((index + 1)) failed:"
    cat "$client_log_dir/client-$((index + 1)).log"
  else
    cat "$client_log_dir/client-$((index + 1)).log"
  fi
done

if [[ "$status" -ne 0 ]]; then
  echo "[network-stress] host log follows:"
  cat "$server_log"
  exit "$status"
fi

echo "[network-stress] all $ASHEN_STRESS_CLIENTS clients survived RPC bursts"
