#!/usr/bin/env bash
# End to end check of the relay contract: a local dry-run gateway receives events
# signed exactly like Forwarder.java signs them (same fields, org.json encoding,
# HMAC-SHA256 hex over the raw UTF-8 body in x-relay-signature, keyed with the
# per-sensor key HMAC(master, sensor_id) that aws-bootstrap.sh writes to relay.json).
#
#   scripts/e2e-relay.sh
#
# Touches nothing outside a temp dir. Exit 0 only if every check passes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
MASTER="e2e-secret-$RANDOM$RANDOM"
SENSOR_ID="chaparral"
PORT="$((18000 + RANDOM % 1000))"
BASE="http://127.0.0.1:$PORT"
GATEWAY_PID=""
FAILURES=0

cleanup() {
  [[ -n "$GATEWAY_PID" ]] && { kill "$GATEWAY_PID"; wait "$GATEWAY_PID"; } 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

(cd "$ROOT/gateway" && PORT="$PORT" RELAY_HMAC_SECRET="$MASTER" APNS_DRY_RUN=1 \
  APNS_TEAM_ID=T APNS_KEY_ID=K APNS_BUNDLE_ID=com.example.relay \
  EVIDENCE_FILE="$WORK/gateway.jsonl" \
  SUBSCRIPTIONS_FILE="$WORK/subscriptions.json" \
  COVERAGE_STATE_FILE="$WORK/coverage.json" \
  exec node src/server.js >"$WORK/gateway.log" 2>&1) &
GATEWAY_PID=$!
for _ in $(seq 50); do
  grep -q listening "$WORK/gateway.log" 2>/dev/null && break
  sleep 0.1
done
grep -q listening "$WORK/gateway.log" || { cat "$WORK/gateway.log"; echo "gateway did not start"; exit 1; }

hmac_hex() { printf '%s' "$2" | openssl dgst -sha256 -hmac "$1" -hex | awk '{print $NF}'; }
SENSOR_KEY="$(hmac_hex "$MASTER" "$SENSOR_ID")"
sign() { hmac_hex "$SENSOR_KEY" "$1"; }

# Prints the body Forwarder would send. Args: event_id, capture offset in ms
# (negative = captured in the past), seconds between quake origin and capture.
# org.json writes compact JSON, keeps UTF-8 as is and escapes "/" as "\/", so the
# bytes (and the HMAC) match the device.
forwarder_body() {
  python3 - "$1" "$2" "$3" "$SENSOR_ID" <<'PY'
import json, sys, time
from datetime import datetime, timezone
event_id, offset_ms, origin_age_s, sensor_id = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
captured = int(time.time() * 1000) + offset_ms
def instant(ms):  # java.time.Instant.toString, millisecond precision
    return datetime.fromtimestamp(ms / 1000, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.") + f"{ms % 1000:03d}Z"
event = {
    "event_id": event_id,
    "source": "android_earthquake_alert_candidate",
    "sensor_id": sensor_id,
    "captured_at": instant(captured),
    "expires_at": instant(captured + 3 * 60_000),  # RelayPolicy.ALERT_TTL_MS
    "title": "Alerta de sismo",
    "body": "Sismo M4.5 cerca de tu zona. Protéjase ahora.",
    "interruption_level": "time-sensitive",
    "magnitude": 4.45852,
    "distance_km": 18.9089,
    "time_occurred_s": captured // 1000 - origin_age_s,
}
sys.stdout.write(json.dumps(event, ensure_ascii=False, separators=(",", ":")).replace("/", "\\/"))
PY
}

# Prints "<status> <body>".
post() {
  local path="$1" body="$2" signature="$3"
  curl -s -o "$WORK/response" -w '%{http_code}' -X POST "$BASE$path" \
    -H 'content-type: application/json' -H "x-relay-signature: $signature" \
    --data-binary "$body"
  printf ' %s' "$(cat "$WORK/response")"
}

check() {
  local name="$1" actual="$2" expected_pattern="$3"
  if [[ "$actual" =~ $expected_pattern ]]; then
    echo "ok   $name"
  else
    echo "FAIL $name: got '$actual', want /$expected_pattern/"
    FAILURES=$((FAILURES + 1))
  fi
}

RUN="$(date +%s)"

# 17 s from origin to capture is what the first real Chaparral alert took.
body="$(forwarder_body "$SENSOR_ID:t$RUN:alert" 0 17)"
check "alert is accepted" "$(post /events "$body" "$(sign "$body")")" '^202 .*"accepted":true'
check "same alert again is a duplicate" "$(post /events "$body" "$(sign "$body")")" '^202 \{"duplicate":true\}$'

fresh="$(forwarder_body "$SENSOR_ID:t$((RUN + 1)):alert" 0 17)"
check "bad signature is 401" "$(post /events "$fresh" "$(sign "$fresh-tampered")")" '^401'
check "missing signature is 401" "$(post /events "$fresh" "")" '^401'
check "tampered body is 401" "$(post /events "${fresh/M4.5/M7.5}" "$(sign "$fresh")")" '^401'
check "master key is not a sensor key" "$(post /events "$fresh" "$(hmac_hex "$MASTER" "$fresh")")" '^401'
check "another sensor's key is 401" \
  "$(post /events "$fresh" "$(hmac_hex "$(hmac_hex "$MASTER" quibdo)" "$fresh")")" '^401'

expired="$(forwarder_body "$SENSOR_ID:t$((RUN + 2)):alert" -181000 17)"
check "expired alert is rejected" "$(post /events "$expired" "$(sign "$expired")")" '^400 .*expired'

check "fresh alert after rejections is accepted" "$(post /events "$fresh" "$(sign "$fresh")")" '^202 .*"accepted":true'

late="$(forwarder_body "$SENSOR_ID:t$((RUN + 3)):alert" 0 150)"
check "late alert is still accepted" "$(post /events "$late" "$(sign "$late")")" '^202 .*"accepted":true'

canary="$(forwarder_body "$SENSOR_ID:canary:$RUN" 0 0 | sed 's/}$/,"canary":true}/')"
check "canary is acknowledged" "$(post /events "$canary" "$(sign "$canary")")" '^202 \{"canary":true\}$'

beat="{\"sensor_id\":\"$SENSOR_ID\",\"sent_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
check "listener heartbeat is 204" "$(post /heartbeat "$beat" "$(sign "$beat")")" '^204'
# Listener fresh and canary seen, but no watcher report yet: not covered.
check "/status shows heartbeat and canary, and stays uncovered without aea_ok" \
  "$(curl -s "$BASE/status" | python3 -c 'import json,sys; s=[x for x in json.load(sys.stdin)["sensors"] if x["id"]==sys.argv[1]][0]; print(s["stale"], s["last_canary_ok_at"] is not None, s["covered"])' "$SENSOR_ID")" \
  '^False True False$'

check "gateway still running" "$(kill -0 "$GATEWAY_PID" && echo alive)" '^alive$'
check "evidence has the three accepted alerts" "$(grep -c NO_RECIPIENTS "$WORK/gateway.jsonl")" '^3$'
check "late alert was rewritten by the server" \
  "$(grep "t$((RUN + 3)):alert" "$WORK/gateway.jsonl" | grep -c 'Aviso de sismo atrasado')" '^1$'

if (( FAILURES > 0 )); then
  echo "$FAILURES check(s) failed"
  exit 1
fi
echo "all relay checks passed"
