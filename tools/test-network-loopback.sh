#!/usr/bin/env bash
set -euo pipefail

export GODOT_SILENCE_ROOT_WARNING=1
export ASHEN_TEST_TRANSPORT="${1:-enet}"
if [[ "$ASHEN_TEST_TRANSPORT" != "enet" && "$ASHEN_TEST_TRANSPORT" != "websocket" ]]; then
  echo "Usage: $0 [enet|websocket]" >&2
  exit 2
fi
export ASHEN_TEST_PORT="$((40000 + RANDOM % 20000))"

server_log="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ashen-network-server-$ASHEN_TEST_TRANSPORT.log"
server_pid=""

cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

if [[ "$ASHEN_TEST_TRANSPORT" == "websocket" ]]; then
  echo "[network-loopback] starting WebSocket host on TCP port $ASHEN_TEST_PORT"
  godot --headless --path . -- --server --server-transport=websocket --server-port="$ASHEN_TEST_PORT" >"$server_log" 2>&1 &
else
  echo "[network-loopback] starting ENet host on UDP port $ASHEN_TEST_PORT"
  godot --headless --path . -- --server --server-port="$ASHEN_TEST_PORT" >"$server_log" 2>&1 &
fi
server_pid=$!

server_ready=0
for _ in $(seq 1 40); do
  if ! kill -0 "$server_pid" >/dev/null 2>&1; then
    echo "Host process exited before binding its $ASHEN_TEST_TRANSPORT port."
    cat "$server_log"
    exit 1
  fi
  if [[ "$ASHEN_TEST_TRANSPORT" == "websocket" ]]; then
    port_listening="$(ss -ltn)"
  else
    port_listening="$(ss -lun)"
  fi
  if grep -Eq "[:.]$ASHEN_TEST_PORT[[:space:]]" <<<"$port_listening"; then
    server_ready=1
    break
  fi
  sleep 0.25
done

if [[ "$server_ready" -ne 1 ]]; then
  echo "Host did not bind its $ASHEN_TEST_TRANSPORT port in time."
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

echo "[network-loopback] $ASHEN_TEST_TRANSPORT host/client integration passed"
