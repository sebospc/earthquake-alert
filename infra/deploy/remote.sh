#!/usr/bin/env bash
# Runs on the receptor host, as root, from SSM Run Command. The workflow already checked the
# bundle's sha256; this script installs one piece and proves it landed, or fails loudly.
#
#   remote.sh gateway <bundle_dir> <commit>
#   remote.sh tools   <bundle_dir>
#   remote.sh apk     <bundle_dir> <sensor_id> [--key-switch]
#
# Never runs aws-bootstrap.sh: without EMULATOR_COUNT it would boot extra emulators, and its
# `listener` mode maps serials by argument position and rewrites the whole sensor map.
set -euo pipefail

# Overridable only so test_remote.sh can run it in a temp dir.
GATEWAY_DIR=${GATEWAY_DIR:-/opt/earthquake-gateway}
GATEWAY_DATA=${GATEWAY_DATA:-/var/lib/earthquake-gateway}
GATEWAY_USER=${GATEWAY_USER:-gateway}
TOOLS_DIR=${TOOLS_DIR:-/opt/earthquake-tools}
SENSOR_MAP=${SENSOR_MAP:-/etc/earthquake-sensors.map}
EMULATOR_USER=${EMULATOR_USER:-aea}
ADB=${ADB:-/opt/android-sdk/platform-tools/adb}
PACKAGE=com.earthquakes.relay
EVIDENCE_BACKUP_DIR=${EVIDENCE_BACKUP_DIR:-/var/lib/aea-cw/evidence-backup}
COVERED_TIMEOUT_S=${COVERED_TIMEOUT_S:-420}  # two 5-min heartbeats plus margin
ALERT_QUIET_S=${ALERT_QUIET_S:-600}
EVIDENCE_READ="test ! -e files/notification-evidence.jsonl || cat files/notification-evidence.jsonl"

die() { echo "DEPLOY_FAILED: $*" >&2; exit 1; }
aea_adb() { sudo -u "$EMULATOR_USER" -H "$ADB" "$@"; }
map_ids() { awk 'NF >= 2 {print $2}' "$SENSOR_MAP"; }
# Never `cmd | grep -q`: under pipefail grep's early exit gives the writer SIGPIPE (141), so a
# match reads as a failure (QA-91). Capture first, then match the variable.
contains() { [[ $1 == *"$2"* ]]; }

# A gateway restart or an APK install in the minutes after an alert can cut its delivery.
# Postpone instead: the job fails loudly and is rerun later.
refuse_during_alert() {
  python3 - "$GATEWAY_DATA/gateway-evidence.jsonl" "$ALERT_QUIET_S" <<'PY' || die "DEPLOY_POSTPONED: alert dispatched in the last ${ALERT_QUIET_S}s"
import collections, datetime, json, sys
ALERT_TYPES = {"WEB_PUSH_DISPATCH", "NO_RECIPIENTS", "NO_ACTIVE_RECIPIENTS", "DISPATCH_FAILED_ALL"}
now = datetime.datetime.now(datetime.timezone.utc)
try:
    with open(sys.argv[1]) as evidence:
        lines = collections.deque(evidence, maxlen=5000)
except FileNotFoundError:
    sys.exit(0)
for line in lines:
    try:
        record = json.loads(line)
        at = datetime.datetime.fromisoformat(record["at"].replace("Z", "+00:00"))
    except (ValueError, KeyError, TypeError):
        continue
    if record.get("type") in ALERT_TYPES and (now - at).total_seconds() < float(sys.argv[2]):
        sys.exit(1)
PY
}
map_field() { awk -v id="$1" -v n="$2" '$2 == id {print $n}' "$SENSOR_MAP"; }

status_covered() {
  curl -fsS -m 10 http://127.0.0.1:8787/status | python3 -c '
import json, sys
covered = {s["id"] for s in json.load(sys.stdin)["sensors"] if s["covered"]}
missing = [i for i in sys.argv[1:] if i not in covered]
print(" ".join(missing))
sys.exit(1 if missing else 0)' "$@"
}

wait_covered() {
  (($# > 0)) || { echo "no receptor to check: empty sensor map" >&2; return 1; }
  local deadline=$((SECONDS + COVERED_TIMEOUT_S)) missing
  until missing=$(status_covered "$@" 2>/dev/null); do
    ((SECONDS < deadline)) || { echo "not covered after ${COVERED_TIMEOUT_S}s: ${missing:-/status unreachable}" >&2; return 1; }
    sleep 10
  done
  echo "covered after $((SECONDS - deadline + COVERED_TIMEOUT_S))s: $*"
}

# Seconds before the restart, exactly like the bootstrap: the certifier only excuses a
# gateway restart that has a DEPLOY right in front of it.
write_deploy_line() {
  local evidence_file="$GATEWAY_DATA/gateway-evidence.jsonl"
  printf '{"type":"DEPLOY","at":"%s","version":"%s","commit":"%s","by":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" "$(sha256sum "$GATEWAY_DIR/src/server.js" | cut -c1-12)" \
    "$1" "$2" >> "$evidence_file"
  chown "$GATEWAY_USER:" "$evidence_file"
  chmod 600 "$evidence_file"
}

deploy_gateway() {
  local bundle=$1 commit=$2 staging="$GATEWAY_DIR.new" previous="$GATEWAY_DIR.prev"
  local receptor_ids
  receptor_ids=($(map_ids))  # sensor ids never hold spaces
  ((${#receptor_ids[@]} > 0)) || die "empty sensor map: nothing could prove coverage"
  refuse_during_alert
  rm -rf "$staging"
  mkdir -p "$staging"
  tar -xzf "$bundle/gateway.tar.gz" -C "$staging"
  install -m 644 "$bundle/gateway.manifest" "$staging/.manifest"
  (cd "$staging" && sha256sum -c --quiet .manifest) || die "extracted gateway does not match the build"
  # Built beside the live copy: a failed npm ci must not touch the running gateway.
  (cd "$staging" && npm ci --omit=dev --no-audit --no-fund >/dev/null) || die "npm ci failed, live gateway untouched"

  rm -rf "$previous"
  mv "$GATEWAY_DIR" "$previous"
  mv "$staging" "$GATEWAY_DIR"
  write_deploy_line "$commit" ci
  systemctl restart earthquake-gateway.service

  if (cd "$GATEWAY_DIR" && sha256sum -c --quiet .manifest) && wait_covered "${receptor_ids[@]}"; then
    echo "DEPLOY_OK gateway $commit covered: ${receptor_ids[*]}"
    return 0
  fi
  # A gateway that cannot prove coverage goes back to the one that could.
  mv "$GATEWAY_DIR" "$GATEWAY_DIR.failed"
  mv "$previous" "$GATEWAY_DIR"
  rm -rf "$GATEWAY_DIR.failed"
  write_deploy_line "rollback-from-$commit" ci-rollback
  systemctl restart earthquake-gateway.service
  wait_covered "${receptor_ids[@]}" || { echo "ROLLBACK_FAILED: previous gateway is not covered either" >&2; exit 1; }
  die "gateway $commit rolled back: checksum or coverage check failed"
}

deploy_tools() {
  local bundle=$1 staging
  staging=$(mktemp -d)
  tar -xzf "$bundle/tools.tar.gz" -C "$staging"
  (cd "$staging" && sha256sum -c --quiet "$bundle/tools.manifest") || die "tools do not match the build"
  install -m 755 "$staging"/scripts/lab.py "$staging"/scripts/sensor-health.py "$staging"/scripts/aea-geofix.py "$TOOLS_DIR/"
  # The probe updates only once install.sh put the agent in place (first time: by hand, approved).
  if [[ -f "$TOOLS_DIR/aea-cw-probe.py" ]]; then
    install -m 755 "$staging"/infra/cloudwatch/aea-cw-probe.py "$TOOLS_DIR/"
  fi
  local name
  for name in lab.py sensor-health.py aea-geofix.py; do
    cmp -s "$staging/scripts/$name" "$TOOLS_DIR/$name" || die "$name did not land"
  done
  rm -rf "$staging"
  # sensor-health is a timer: its next run picks the new file. aea-geofix is long-running.
  systemctl restart aea-geofix.service
  systemctl is-active --quiet aea-geofix.service || die "aea-geofix not running after restart"
  echo "DEPLOY_OK tools"
}

# One receptor. --key-switch is the one-time move from the Mac debug key to the CI key:
# install -r would fail on the signature, so it is uninstall + install, and the grants,
# relay.json and the notification listener access are redone here, not by hand.
# A receptor without the app yet (new host) is a fresh install: nothing to back up, no
# listener that could be mid-alert, and relay.json is written like after a key switch.
deploy_apk() {
  local bundle=$1 sensor_id=$2 key_switch=${3:-}
  local serial sensor_secret readable_apk backup
  serial=$(map_field "$sensor_id" 1)
  sensor_secret=$(map_field "$sensor_id" 5)
  [[ -n $serial && -n $sensor_secret ]] || die "$sensor_id is not in $SENSOR_MAP"
  refuse_during_alert
  [[ $(aea_adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r') == 1 ]] \
    || die "$serial ($sensor_id) is not booted"
  local uptime_before
  uptime_before=$(aea_adb -s "$serial" shell cut -d. -f1 /proc/uptime | tr -d '\r')
  # `pm list packages` answers empty with exit 0 when the app is absent; an adb failure is
  # an error, never mistaken for "not installed" (that would skip the alert check).
  local packages fresh=""
  packages=$(aea_adb -s "$serial" shell pm list packages "$PACKAGE") || die "$sensor_id: cannot list packages"
  # Whole line: com.earthquakes.relay.<anything> must not count as installed.
  [[ $'\n'${packages//$'\r'/}$'\n' == *$'\n'"package:$PACKAGE"$'\n'* ]] || fresh=1

  # The on-device evidence dies with an uninstall: keep a copy first, every time.
  install -d -o "$EMULATOR_USER" -m 0750 "$EVIDENCE_BACKUP_DIR"
  backup="$EVIDENCE_BACKUP_DIR/$sensor_id-$(date -u +%Y%m%dT%H%M%SZ).jsonl"
  if [[ -n $fresh ]]; then
    : > "$backup"
    echo "fresh install on $sensor_id: no app yet, nothing to back up"
  else
    # No file yet is an empty backup. A failed read stops the deploy: it is also the read
    # the alert check below needs, and unreadable must mean postpone.
    aea_adb -s "$serial" exec-out run-as "$PACKAGE" sh -c "$EVIDENCE_READ" > "$backup" \
      || die "DEPLOY_POSTPONED: could not read $sensor_id evidence, not touching the app"
  fi
  echo "evidence backup: $backup ($(wc -c < "$backup") bytes)"
  # The install kills the listener: one still retrying an alert the gateway has not seen
  # would lose it. Same rule as sensor-health's eew_posts(): an eew_* NOTIFICATION_POSTED
  # captured in the last ALERT_QUIET_S.
  python3 - "$backup" "$ALERT_QUIET_S" <<'PY' || die "DEPLOY_POSTPONED: $sensor_id listener captured an eew alert in the last ${ALERT_QUIET_S}s"
import json, sys, time
now = time.time()
for line in open(sys.argv[1], errors="replace"):
    try:
        record = json.loads(line)
    except ValueError:
        continue
    if (isinstance(record, dict) and record.get("event_type") == "NOTIFICATION_POSTED"
            and str(record.get("channel_id") or "").startswith("eew_")
            and now - record.get("captured_at_ms", 0) / 1000 < float(sys.argv[2])):
        sys.exit(1)
PY

  # The listener sends a canary as soon as it connects: anything after this instant is ours.
  local deployed_at
  deployed_at=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
  # The emulator user has to read the apk, and adb wants the .apk name.
  readable_apk="$(mktemp -d)/listener.apk"
  install -m 644 "$bundle/listener.apk" "$readable_apk"
  chmod 755 "$(dirname "$readable_apk")"
  local adb_output
  if [[ $key_switch == --key-switch ]]; then
    adb_output=$(aea_adb -s "$serial" uninstall "$PACKAGE" 2>&1 || true)
    contains "$adb_output" Success || die "$sensor_id: uninstall failed: $adb_output"
  fi
  # -g grants the runtime permissions: GpsKeeperService needs location (QA-84).
  adb_output=$(aea_adb -s "$serial" install -r -g "$readable_apk" 2>&1 || true)
  rm -rf "$(dirname "$readable_apk")"
  contains "$adb_output" Success || die "$sensor_id: install failed: $adb_output"
  adb_output=$(aea_adb -s "$serial" shell dumpsys package "$PACKAGE" || true)
  contains "$adb_output" "android.permission.ACCESS_FINE_LOCATION: granted=true" \
    || die "$sensor_id: ACCESS_FINE_LOCATION not granted"
  if [[ $key_switch == --key-switch || -n $fresh ]]; then
    printf '{"gateway_url":"http://10.0.2.2:8787/events","hmac_secret":"%s","sensor_id":"%s"}' \
      "$sensor_secret" "$sensor_id" \
      | aea_adb -s "$serial" exec-in run-as "$PACKAGE" sh -c 'mkdir -p files && cat > files/relay.json'
  fi
  aea_adb -s "$serial" shell cmd notification allow_listener "$PACKAGE/.CaptureService"

  # Verify: same boot, GpsKeeper up (it follows relay.json on the next heartbeat, <= 5 min),
  # a fresh canary accepted, and the receptor covered.
  local deadline=$((SECONDS + COVERED_TIMEOUT_S))
  until adb_output=$(aea_adb -s "$serial" shell dumpsys activity services "$PACKAGE" || true)
        contains "$adb_output" GpsKeeper; do
    ((SECONDS < deadline)) || die "$sensor_id: GpsKeeper not running"
    sleep 15
  done
  local uptime_after
  uptime_after=$(aea_adb -s "$serial" shell cut -d. -f1 /proc/uptime | tr -d '\r')
  ((uptime_after >= uptime_before)) || die "$sensor_id rebooted during the deploy"
  # Only what this deploy wrote: older GPS_KEEPER_FAILED lines are history, not this install.
  local skip_bytes=$(( $(wc -c < "$backup") + 1 ))
  [[ $key_switch == --key-switch || -n $fresh ]] && skip_bytes=1
  local evidence_after
  evidence_after=$(aea_adb -s "$serial" exec-out run-as "$PACKAGE" sh -c "$EVIDENCE_READ") \
    || die "$sensor_id: could not read the evidence after the install"
  contains "$(tail -c +"$skip_bytes" <<<"$evidence_after")" GPS_KEEPER_FAILED \
    && die "$sensor_id: GPS_KEEPER_FAILED in evidence"
  # Not sensor-health: it may reboot a receptor, and an APK deploy must not.
  until curl -fsS -m 10 http://127.0.0.1:8787/status | python3 -c '
import json, sys
s = [x for x in json.load(sys.stdin)["sensors"] if x["id"] == sys.argv[1]][0]
sys.exit(0 if s["covered"] and (s["last_canary_ok_at"] or "") >= sys.argv[2] else 1)' "$sensor_id" "$deployed_at"; do
    ((SECONDS < deadline)) || die "$sensor_id: no canary OK after the deploy, or not covered"
    sleep 15
  done
  echo "DEPLOY_OK apk $sensor_id"
}

case ${1:-} in
  gateway) deploy_gateway "$2" "$3" ;;
  tools) deploy_tools "$2" ;;
  apk) deploy_apk "$2" "$3" "${4:-}" ;;
  *) die "usage: $0 gateway|tools|apk ..." ;;
esac
