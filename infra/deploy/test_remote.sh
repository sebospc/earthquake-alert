#!/usr/bin/env bash
# Offline check of remote.sh: temp dirs, stubbed systemctl/curl/npm/sudo/adb.
# Gateway: a good build lands with its DEPLOY line, a build that cannot prove coverage rolls
# back (and the rollback is verified), a tampered build or an empty map or a recent alert
# never touches the live gateway. APK: a full run against an adb that writes long output,
# which is where `cmd | grep -q` under pipefail used to fail (QA-91).
#
#   bash infra/deploy/test_remote.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin" "$WORK/bundle"
# /status answer comes from $WORK/status; no file = gateway unreachable. With
# $FAKE_COVER_OLD_ONLY the receptors are covered only while the old gateway is live.
cat > "$WORK/bin/curl" <<'EOF'
#!/bin/sh
if [ -n "$FAKE_COVER_OLD_ONLY" ]; then
  if [ "$(cat "$GATEWAY_DIR/src/server.js")" = "old gateway" ]; then covered=true; else covered=false; fi
  printf '{"sensors":[{"id":"chaparral","covered":%s},{"id":"quibdo","covered":true}]}' "$covered"
  exit 0
fi
[ -f "$FAKE_STATUS" ] && cat "$FAKE_STATUS"
EOF
# sudo -u aea -H <adb> ... -> <adb> ...
printf '#!/bin/sh\nshift 3\nexec "$@"\n' > "$WORK/bin/sudo"
printf '#!/bin/sh\necho "$@" >> "$FAKE_SYSTEMCTL_LOG"\n' > "$WORK/bin/systemctl"
printf '#!/bin/sh\nmkdir -p node_modules\n' > "$WORK/bin/npm"
chmod +x "$WORK/bin/"*

(cd "$ROOT/gateway" && tar -czf "$WORK/bundle/gateway.tar.gz" src public package.json package-lock.json \
  && find src public package.json package-lock.json -type f | sort | xargs sha256sum > "$WORK/bundle/gateway.manifest")

export PATH="$WORK/bin:$PATH"
export GATEWAY_DIR="$WORK/opt/earthquake-gateway" GATEWAY_DATA="$WORK/data" GATEWAY_USER="$(id -un)"
export SENSOR_MAP="$WORK/sensors.map" COVERED_TIMEOUT_S=0
export FAKE_STATUS="$WORK/status" FAKE_SYSTEMCTL_LOG="$WORK/systemctl.log"
printf 'emulator-5554 chaparral 1 2 key1\nemulator-5556 quibdo 3 4 key2\n' > "$SENSOR_MAP"
mkdir -p "$GATEWAY_DATA"

fresh_live_gateway() {
  rm -rf "$GATEWAY_DIR" "$GATEWAY_DIR.prev"
  mkdir -p "$GATEWAY_DIR/src"
  echo "old gateway" > "$GATEWAY_DIR/src/server.js"
  : > "$GATEWAY_DATA/gateway-evidence.jsonl"
  : > "$FAKE_SYSTEMCTL_LOG"
}
covered() { printf '{"sensors":[{"id":"chaparral","covered":%s},{"id":"quibdo","covered":true}]}' "$1" > "$FAKE_STATUS"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

fresh_live_gateway
covered true
output=$(bash "$HERE/remote.sh" gateway "$WORK/bundle" abc123) || fail "good build did not deploy"
grep -q "^DEPLOY_OK gateway abc123 covered: chaparral quibdo" <<<"$output" || fail "no DEPLOY_OK: $output"
cmp -s "$ROOT/gateway/src/server.js" "$GATEWAY_DIR/src/server.js" || fail "new server.js did not land"
grep -q '"type":"DEPLOY".*"commit":"abc123"' "$GATEWAY_DATA/gateway-evidence.jsonl" || fail "no DEPLOY line"
grep -q "restart earthquake-gateway.service" "$FAKE_SYSTEMCTL_LOG" || fail "gateway not restarted"
echo "PASS good build lands, with DEPLOY line and restart"

fresh_live_gateway
output=$(FAKE_COVER_OLD_ONLY=1 bash "$HERE/remote.sh" gateway "$WORK/bundle" bad456 2>&1) && fail "uncovered deploy reported success"
[[ $(cat "$GATEWAY_DIR/src/server.js") == "old gateway" ]] || fail "not rolled back"
grep -q '"by":"ci-rollback"' "$GATEWAY_DATA/gateway-evidence.jsonl" || fail "rollback restart needs its own ci-rollback DEPLOY line"
[[ $(grep -c "restart earthquake-gateway.service" "$FAKE_SYSTEMCTL_LOG") == 2 ]] || fail "rollback did not restart the old gateway"
grep -q "DEPLOY_FAILED: gateway bad456 rolled back" <<<"$output" && ! grep -q ROLLBACK_FAILED <<<"$output" \
  || fail "a verified rollback must say rolled back, not ROLLBACK_FAILED: $output"
echo "PASS a build that cannot prove coverage rolls back, and the rollback is verified"

fresh_live_gateway
covered false
output=$(bash "$HERE/remote.sh" gateway "$WORK/bundle" bad457 2>&1) && fail "uncovered deploy reported success"
grep -q "^ROLLBACK_FAILED" <<<"$output" || fail "old gateway uncovered too must print ROLLBACK_FAILED: $output"
echo "PASS a rollback that cannot prove coverage either says ROLLBACK_FAILED"

fresh_live_gateway
rm -f "$FAKE_STATUS"
if bash "$HERE/remote.sh" gateway "$WORK/bundle" down789 2>/dev/null; then fail "unreachable /status reported success"; fi
[[ $(cat "$GATEWAY_DIR/src/server.js") == "old gateway" ]] || fail "not rolled back with /status down"
echo "PASS /status unreachable after restart rolls back"

fresh_live_gateway
covered true
printf '{"type":"WEB_PUSH_DISPATCH","at":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" > "$GATEWAY_DATA/gateway-evidence.jsonl"
output=$(bash "$HERE/remote.sh" gateway "$WORK/bundle" during-alert 2>&1) && fail "deployed during an alert"
grep -q DEPLOY_POSTPONED <<<"$output" || fail "no DEPLOY_POSTPONED: $output"
[[ $(cat "$GATEWAY_DIR/src/server.js") == "old gateway" && ! -s "$FAKE_SYSTEMCTL_LOG" ]] || fail "alert guard touched the live gateway"
printf '{"type":"WEB_PUSH_DISPATCH","at":"2020-01-01T00:00:00.000Z"}\n' > "$GATEWAY_DATA/gateway-evidence.jsonl"
bash "$HERE/remote.sh" gateway "$WORK/bundle" after-alert >/dev/null || fail "an old alert must not block the deploy"
echo "PASS a gateway deploy within 10 min of an alert is postponed, an old alert does not block"

fresh_live_gateway
cp "$SENSOR_MAP" "$WORK/map.bak"; : > "$SENSOR_MAP"
if bash "$HERE/remote.sh" gateway "$WORK/bundle" nomap 2>/dev/null; then fail "empty map deployed"; fi
[[ $(cat "$GATEWAY_DIR/src/server.js") == "old gateway" ]] || fail "empty map touched the live gateway"
cp "$WORK/map.bak" "$SENSOR_MAP"
echo "PASS an empty sensor map never deploys (nothing could prove coverage)"

fresh_live_gateway
covered true
sed -i.bak '1s/^./0/' "$WORK/bundle/gateway.manifest"
if bash "$HERE/remote.sh" gateway "$WORK/bundle" evil 2>/dev/null; then fail "tampered build deployed"; fi
[[ $(cat "$GATEWAY_DIR/src/server.js") == "old gateway" && ! -s "$FAKE_SYSTEMCTL_LOG" ]] || fail "tampered build touched the live gateway"
echo "PASS a build that does not match its manifest never touches the live gateway"

# APK on quibdo, key switch. The fake adb writes 2 MB after every match, the shape that made
# `cmd | grep -q` fail with SIGPIPE under pipefail.
fresh_live_gateway
: > "$WORK/bundle/listener.apk"
echo '{"type":"OLD"}' > "$WORK/device-evidence.jsonl"
cat > "$WORK/bin/fake-adb" <<'EOF'
#!/bin/bash
shift 2  # -s <serial>
long_tail() { head -c 2000000 /dev/zero | tr '\0' 'x'; echo; }
case "$*" in
  "shell getprop sys.boot_completed") echo 1 ;;
  "shell cut -d. -f1 /proc/uptime") echo 1000 ;;
  "exec-out run-as com.earthquakes.relay sh -c "*) cat "$FAKE_DEVICE_EVIDENCE" ;;
  uninstall*) echo Success; long_tail ;;
  "install -r -g "*) [[ $4 == *.apk ]] || { echo "Failure [not an .apk]"; exit 1; }; echo Success; long_tail ;;
  "shell dumpsys package com.earthquakes.relay") echo "android.permission.ACCESS_FINE_LOCATION: granted=true"; long_tail ;;
  "exec-in run-as "*) cat > "$FAKE_RELAY_JSON" ;;
  "shell cmd notification allow_listener "*) : ;;
  "shell dumpsys activity services com.earthquakes.relay") echo "ServiceRecord{ com.earthquakes.relay/.GpsKeeperService }"; long_tail ;;
  *) echo "fake adb: unexpected $*" >&2; exit 9 ;;
esac
EOF
chmod +x "$WORK/bin/fake-adb"
printf '{"sensors":[{"id":"quibdo","covered":true,"last_canary_ok_at":"2999-01-01T00:00:00.000Z"}]}' > "$FAKE_STATUS"
output=$(ADB="$WORK/bin/fake-adb" EMULATOR_USER="$(id -un)" EVIDENCE_BACKUP_DIR="$WORK/backup" \
  FAKE_DEVICE_EVIDENCE="$WORK/device-evidence.jsonl" FAKE_RELAY_JSON="$WORK/relay.json" \
  COVERED_TIMEOUT_S=5 bash "$HERE/remote.sh" apk "$WORK/bundle" quibdo --key-switch 2>&1) \
  || fail "apk deploy failed against long adb output: $output"
grep -q "^DEPLOY_OK apk quibdo" <<<"$output" || fail "no DEPLOY_OK apk: $output"
grep -q '"sensor_id":"quibdo"' "$WORK/relay.json" && grep -q '"hmac_secret":"key2"' "$WORK/relay.json" \
  || fail "relay.json not rewritten from the map"
grep -q OLD "$WORK"/backup/quibdo-*.jsonl || fail "evidence not backed up before the uninstall"
echo "PASS apk key switch end to end, with long adb output (QA-91)"

echo '{"type":"GPS_KEEPER_FAILED"}' >> "$WORK/device-evidence.jsonl"
output=$(ADB="$WORK/bin/fake-adb" EMULATOR_USER="$(id -un)" EVIDENCE_BACKUP_DIR="$WORK/backup" \
  FAKE_DEVICE_EVIDENCE="$WORK/device-evidence.jsonl" FAKE_RELAY_JSON="$WORK/relay.json" \
  COVERED_TIMEOUT_S=5 bash "$HERE/remote.sh" apk "$WORK/bundle" quibdo --key-switch 2>&1) \
  && fail "GPS_KEEPER_FAILED in the new evidence was missed"
grep -q "GPS_KEEPER_FAILED in evidence" <<<"$output" || fail "wrong failure: $output"
echo "PASS GPS_KEEPER_FAILED after a key switch fails the deploy"

# The listener's own evidence: a recent eew post postpones before anything is touched, an old
# one does not, and an unreadable evidence file postpones too.
recent_ms=$(( $(date +%s) * 1000 - 60000 ))
printf '{"event_type":"NOTIFICATION_POSTED","channel_id":"eew_alerts","captured_at_ms":%s}\n' "$recent_ms" > "$WORK/device-evidence.jsonl"
: > "$WORK/relay.json"
apk_run() {
  ADB="$WORK/bin/fake-adb" EMULATOR_USER="$(id -un)" EVIDENCE_BACKUP_DIR="$WORK/backup" \
    FAKE_DEVICE_EVIDENCE="$WORK/device-evidence.jsonl" FAKE_RELAY_JSON="$WORK/relay.json" \
    COVERED_TIMEOUT_S=5 bash "$HERE/remote.sh" apk "$WORK/bundle" quibdo --key-switch 2>&1
}
output=$(apk_run) && fail "apk deployed right after an eew alert on the receptor"
grep -q "DEPLOY_POSTPONED: quibdo listener captured an eew alert" <<<"$output" || fail "wrong failure: $output"
[[ ! -s "$WORK/relay.json" ]] || fail "postponed deploy touched the app"
echo "PASS apk postponed after a recent eew post on the listener, app untouched"

printf '{"event_type":"NOTIFICATION_POSTED","channel_id":"eew_alerts","captured_at_ms":%s}\n' "$((recent_ms - 3600000))" > "$WORK/device-evidence.jsonl"
printf '{"event_type":"NOTIFICATION_POSTED","channel_id":"other","captured_at_ms":%s}\n' "$recent_ms" >> "$WORK/device-evidence.jsonl"
output=$(apk_run) || fail "an old eew post or a non-eew post must not block: $output"
echo "PASS an old eew post or a recent non-eew post does not block"

rm "$WORK/device-evidence.jsonl"  # the fake adb's cat fails: unreadable
: > "$WORK/relay.json"
output=$(apk_run) && fail "apk deployed with unreadable listener evidence"
grep -q "DEPLOY_POSTPONED: could not read quibdo evidence" <<<"$output" && [[ ! -s "$WORK/relay.json" ]] \
  || fail "unreadable evidence must postpone before touching the app: $output"
echo "PASS unreadable listener evidence postpones"
