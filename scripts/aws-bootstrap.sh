#!/usr/bin/env bash
# Bootstrap one EC2 (Ubuntu 24.04) as a sensor host: one headless AEA emulator per 2 vCPUs
# plus the relay gateway. The instance must be launched with
#   --cpu-options NestedVirtualization=enabled
# Idempotent: every step checks before acting, so it is safe to run again.
#
#   sudo VAPID_SUBJECT=mailto:you@example.com [GATEWAY_DOMAIN=alerts.example.com] \
#        [NTFY_TOPIC=your-topic] ./aws-bootstrap.sh
#
# NTFY_TOPIC: where the host tells the operator that the gateway stopped answering. A dead
# gateway cannot warn the users itself.
#
# Copy the whole project first: the gateway is installed from ../gateway.
# Second step, only after signing in to Google by hand on every AVD (that needs a person):
#
#   sudo ./aws-bootstrap.sh listener path/to/android-listener-debug.apk emulator-5554=chaparral emulator-5556=quibdo
#
# installs the listener on each emulator and pushes it its relay.json. Later runs can name
# only the sensor (`... listener <apk> quibdo`): its emulator comes from the sensor map, and
# the other sensors stay as they are. Must be a debug APK: run-as only works on debuggable apps.
set -euo pipefail

SDK_ROOT=/opt/android-sdk
CMDLINE_TOOLS_ZIP=commandlinetools-linux-13114758_latest.zip
SYSTEM_IMAGE="system-images;android-35;google_apis_playstore;x86_64"
EMULATOR_USER=aea
GATEWAY_USER=gateway
GATEWAY_DIR=/opt/earthquake-gateway
GATEWAY_DATA=/var/lib/earthquake-gateway
GATEWAY_ENV=/etc/earthquake-gateway.env
SCRIPTS_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATEWAY_SRC="$(cd "$SCRIPTS_SRC/../gateway" && pwd)"
TOOLS_DIR=/opt/earthquake-tools
SENSOR_MAP=/etc/earthquake-sensors.map

die() { echo "error: $*" >&2; exit 1; }


# adb and the emulator console only trust the user that started the emulator (its adbkey
# and console token live in that home). As root the device shows up "unauthorized".
# stdin is /dev/null: `adb shell` reads whatever stdin it inherits, and inside a read loop that
# is the loop's own input, so it ate the other targets and only the first got installed.
aea_adb() {
  sudo -u "$EMULATOR_USER" -H "$SDK_ROOT/platform-tools/adb" "$@" </dev/null
}

# Only for the one call that pipes data in on purpose.
aea_adb_with_input() {
  sudo -u "$EMULATOR_USER" -H "$SDK_ROOT/platform-tools/adb" "$@"
}

# The adb server is shared (the scrcpy tunnel used for the Google sign-in, any operator), so
# it is restarted only when it is visibly someone else's: our devices show up unauthorized.
# Then once, never on every run. Offline is normal while booting and a restart does not help.
restart_foreign_adb_server() {
  if aea_adb devices | grep -qE "^emulator-[0-9]+[[:space:]]+unauthorized"; then
    aea_adb kill-server
    aea_adb start-server
    sleep 5
  fi
}

# Prints "<serial> <sensor_id>" per argument, or dies. A bare sensor_id takes its emulator
# from the map; picking by position once installed on the wrong emulator and dropped the
# other sensor. A new pairing has to be explicit, and may not steal a mapped serial or id.
resolve_listener_targets() {
  local map=$1; shift
  local arg serial sensor_id mapped
  for arg in "$@"; do
    if [[ $arg == *=* ]]; then
      serial=${arg%%=*}
      sensor_id=${arg#*=}
      [[ $serial =~ ^emulator-[0-9]+$ && -n $sensor_id ]] || die "bad target $arg (want emulator-NNNN=sensor_id)"
      mapped=$(awk -v s="$serial" '$1 == s {print $2}' "$map" 2>/dev/null || true)
      [[ -z $mapped || $mapped == "$sensor_id" ]] \
        || die "$serial is $mapped in $map; remove that line first to reassign it"
      mapped=$(awk -v id="$sensor_id" '$2 == id {print $1}' "$map" 2>/dev/null || true)
      [[ -z $mapped || $mapped == "$serial" ]] \
        || die "$sensor_id is on $mapped in $map; remove that line first to move it"
    else
      sensor_id=$arg
      serial=$(awk -v id="$sensor_id" '$2 == id {print $1}' "$map" 2>/dev/null || true)
      [[ -n $serial ]] || die "$sensor_id is not in $map: name its emulator, emulator-NNNN=$sensor_id"
    fi
    echo "$serial $sensor_id"
  done
}

# The map with the given lines added or replaced; every other sensor is kept as it was.
merge_sensor_map() {
  local map=$1 new_lines=$2
  { NEW_LINES=$new_lines awk 'BEGIN {
        n = split(ENVIRON["NEW_LINES"], lines, "\n")
        for (i = 1; i <= n; i++) if (split(lines[i], f, " ") >= 2) { serial[f[1]]; id[f[2]] }
      }
      !($1 in serial) && !($2 in id)' "$map" 2>/dev/null || true
    printf '%s' "$new_lines"; }
}

install_listener() {
  local apk=$1; shift
  local sensors_json="$GATEWAY_DIR/public/sensors.json"
  [[ -f $apk ]] || die "apk not found: $apk"
  [[ -f $GATEWAY_ENV && -f $sensors_json ]] || die "run the full bootstrap first"
  local master
  master=$(sed -n 's/^RELAY_HMAC_SECRET=//p' "$GATEWAY_ENV")
  # The emulator user has to read the apk; root's copy may sit where it cannot.
  local readable_apk
  readable_apk=$(mktemp --suffix=.apk)
  install -m 644 "$apk" "$readable_apk"
  restart_foreign_adb_server
  local targets
  targets=$(resolve_listener_targets "$SENSOR_MAP" "$@") || exit 1
  local sensor_map=""
  local serial sensor_id
  local installed=0
  # The targets come in on fd 3, so nothing in the loop can read them off stdin.
  while read -r serial sensor_id <&3; do
    # A typo here would make the gateway answer 400 to every alert, forever.
    local place
    place=$(node -e '
      const sensor = require(process.argv[1]).sensors.find(entry => entry.id === process.argv[2]);
      if (!sensor) process.exit(1);
      console.log(`${sensor.lat} ${sensor.lon}`);' "$sensors_json" "$sensor_id") \
      || die "unknown sensor_id $sensor_id (see $sensors_json)"
    [[ $(aea_adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r') == 1 ]] \
      || die "$serial ($sensor_id) is not booted, or adb is not authorized for $EMULATOR_USER"
    # Per-sensor key, HMAC(master, sensor_id): a leaked emulator cannot sign for the others.
    local sensor_secret
    sensor_secret=$(printf '%s' "$sensor_id" | openssl dgst -sha256 -hmac "$master" -hex | awk '{print $NF}')
    # -g grants the runtime permissions, location included: GpsKeeperService needs it to
    # hold GPS open, or every later geo fix is ignored and the location ages out (QA-84).
    aea_adb -s "$serial" install -r -g "$readable_apk"
    aea_adb -s "$serial" shell dumpsys package com.earthquakes.relay \
      | grep -q "android.permission.ACCESS_FINE_LOCATION: granted=true" \
      || die "$serial: ACCESS_FINE_LOCATION not granted to the listener"
    # 10.0.2.2 is the host's loopback as seen from inside the emulator.
    printf '{"gateway_url":"http://10.0.2.2:8787/events","hmac_secret":"%s","sensor_id":"%s"}' \
      "$sensor_secret" "$sensor_id" \
      | aea_adb_with_input -s "$serial" exec-in run-as com.earthquakes.relay sh -c 'mkdir -p files && cat > files/relay.json'
    aea_adb -s "$serial" shell cmd notification allow_listener com.earthquakes.relay/.CaptureService
    echo "$serial -> $sensor_id"
    sensor_map+="$serial $sensor_id $place $sensor_secret"$'\n'
    installed=$((installed + 1))
  done 3<<< "$targets"
  rm -f "$readable_apk"
  local expected
  expected=$(grep -c . <<< "$targets")
  ((installed == expected)) || die "installed $installed of $expected listeners: the sensor map was not changed"
  # Tells the host health check which emulator answers for which sensor, where it is, and
  # the per-sensor key to sign with. Only the emulator user can read it; the health check
  # never gets the master secret or the VAPID key.
  local merged
  merged=$(mktemp)
  merge_sensor_map "$SENSOR_MAP" "$sensor_map" > "$merged"
  install -m 600 -o "$EMULATOR_USER" "$merged" "$SENSOR_MAP"
  rm -f "$merged"
  # Report now instead of leaving the sensor red until the next timer tick.
  systemctl start --no-block sensor-health.service
}

# Sourced by scripts/test_bootstrap_listener.py: functions only, nothing runs.
[[ ${BASH_SOURCE[0]} == "$0" ]] || return 0

# Measured on r8i.large: booting is what needs CPU (two at once starve system_server and
# its watchdog kills them), a booted emulator idles near 0 CPU and ~3.2 GB. So they boot
# one at a time (aea-wait-previous below) and the count is set by RAM: 3.5 GB each plus
# 2 GB for the host, at most 2 per vCPU. EMULATOR_COUNT overrides it.
EMULATOR_CORES=2
if [[ -n ${EMULATOR_COUNT:-} ]]; then
  [[ $EMULATOR_COUNT =~ ^[1-9][0-9]*$ ]] || die "EMULATOR_COUNT must be a positive integer"
  AVD_COUNT=$EMULATOR_COUNT
else
  AVD_COUNT=$(awk -v cpus="$(nproc)" '/^MemTotal:/ {
    count = int(($2 / 1048576 - 2) / 3.5)
    if (count > 2 * cpus) count = 2 * cpus
    if (count < 1) count = 1
    print count
  }' /proc/meminfo)
fi

[[ $EUID -eq 0 ]] || die "run as root (sudo)"

if [[ ${1:-} == listener ]]; then
  [[ $# -ge 3 ]] || die "usage: $0 listener <apk> <sensor_id | emulator-NNNN=sensor_id>..."
  shift
  install_listener "$@"
  exit 0
fi

# Without KVM the emulator falls back to software CPU and never boots in useful time.
[[ -e /dev/kvm ]] || die "/dev/kvm missing: launch the instance with --cpu-options NestedVirtualization=enabled"
grep -qE 'vmx|svm' /proc/cpuinfo || die "CPU does not expose virtualization flags"

echo "== packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
# The emulator links X11/GL libraries even with -no-window.
apt-get install -y -q openjdk-17-jdk-headless unzip curl rsync nodejs npm \
  libpulse0 libnss3 libxcomposite1 libxcursor1 libxi6 libxtst6 libxdamage1 libxrandr2 \
  libxkbfile1 libx11-xcb1 libgbm1 libdrm2 libgl1 libasound2t64

echo "== users"
id "$EMULATOR_USER" &>/dev/null || useradd --system --create-home --home-dir /var/lib/aea "$EMULATOR_USER"
usermod -aG kvm "$EMULATOR_USER"
id "$GATEWAY_USER" &>/dev/null || useradd --system --home-dir "$GATEWAY_DATA" "$GATEWAY_USER"

echo "== android sdk"
SDKMANAGER="$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
if [[ ! -x $SDKMANAGER ]]; then
  workdir=$(mktemp -d)
  curl -fsSL -o "$workdir/tools.zip" "https://dl.google.com/android/repository/$CMDLINE_TOOLS_ZIP"
  unzip -q "$workdir/tools.zip" -d "$workdir"
  mkdir -p "$SDK_ROOT/cmdline-tools"
  mv "$workdir/cmdline-tools" "$SDK_ROOT/cmdline-tools/latest"
  rm -rf "$workdir"
fi
# `yes` dies of SIGPIPE when sdkmanager stops reading; that must not trip pipefail.
(yes || true) | "$SDKMANAGER" --sdk_root="$SDK_ROOT" --licenses >/dev/null
# Only what is missing. Updating the emulator or the image under an AVD that already has a
# Google login would boot it next time on a different system than the one it was set up on.
missing_packages=()
[[ -d $SDK_ROOT/platform-tools ]] || missing_packages+=("platform-tools")
[[ -d $SDK_ROOT/emulator ]] || missing_packages+=("emulator")
[[ -d $SDK_ROOT/system-images/android-35/google_apis_playstore/x86_64 ]] \
  || missing_packages+=("$SYSTEM_IMAGE")
if (( ${#missing_packages[@]} > 0 )); then
  "$SDKMANAGER" --sdk_root="$SDK_ROOT" "${missing_packages[@]}"
fi

echo "== avds"
for i in $(seq 1 "$AVD_COUNT"); do
  avd="sensor-$i"
  if [[ ! -d /var/lib/aea/.android/avd/$avd.avd ]]; then
    echo no | sudo -u "$EMULATOR_USER" env ANDROID_HOME="$SDK_ROOT" \
      "$SDK_ROOT/cmdline-tools/latest/bin/avdmanager" create avd \
      --name "$avd" --package "$SYSTEM_IMAGE" --device pixel_8
  fi
done

# Boot queue: instance N starts its emulator only once N-1 has finished booting, plus a
# margin. Covers the first start and a spot restart, where every unit starts at once.
cat > /usr/local/bin/aea-wait-previous <<'EOF'
#!/bin/sh
instance=$1
[ "$instance" -gt 1 ] || exit 0
previous=$((instance - 1))
unit="aea-emulator@$previous.service"
serial="emulator-$((5552 + 2 * previous))"
adb="$ANDROID_HOME/platform-tools/adb"
margin_s=90
# Measured boot on r8i.large: 82 s. A guest up longer than this plus the margin finished
# booting more than the margin ago.
settled_uptime_s=300
deadline=""
waited_for_boot=false
while :; do
  case "$(systemctl is-active "$unit")" in
    # Still waiting its own turn: its boot has not started, so no clock runs yet.
    activating) sleep 10; continue ;;
    active) ;;
    # Stopped or failed: nothing to wait for.
    *) exit 0 ;;
  esac
  if [ -z "$deadline" ]; then
    # The 15 min cap counts from when the previous emulator really started.
    started=$(systemctl show -p ActiveEnterTimestamp --value "$unit")
    deadline=$(( $(date -d "$started" +%s) + 900 ))
  fi
  if [ "$("$adb" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; then
    break
  fi
  waited_for_boot=true
  # Bounded: a predecessor that never boots must not keep every later sensor down.
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "sensor-$previous not booted 15 min after starting, starting sensor-$instance anyway"
    exit 0
  fi
  sleep 10
done
if [ "$waited_for_boot" = false ]; then
  uptime_s=$("$adb" -s "$serial" shell cut -d. -f1 /proc/uptime 2>/dev/null | tr -d '\r')
  # Already up for a while (a single restart of this one): no margin to wait.
  [ "${uptime_s:-0}" -ge "$settled_uptime_s" ] && exit 0
fi
sleep "$margin_s"
EOF
chmod 755 /usr/local/bin/aea-wait-previous

# Template unit: instance N runs AVD sensor-N on console port 5552+2N (5554, 5556, ...).
# $$ is systemd's escape for a literal $, so the arithmetic reaches sh intact.
cat > /etc/systemd/system/aea-emulator@.service <<EOF
[Unit]
Description=Headless AEA emulator sensor-%i
After=network-online.target
Wants=network-online.target

[Service]
User=$EMULATOR_USER
Environment=ANDROID_HOME=$SDK_ROOT
ExecStartPre=/usr/local/bin/aea-wait-previous %i
# The queue wait (up to 15 min + 90 s) happens before the start counts as started.
TimeoutStartSec=20min
ExecStart=/bin/sh -c 'exec $SDK_ROOT/emulator/emulator -avd sensor-%i -port \$\$((5552 + 2 * %i)) -no-window -no-audio -no-snapshot -gpu swiftshader_indirect -cores $EMULATOR_CORES'
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

echo "== gateway"
mkdir -p "$GATEWAY_DATA"
# Built beside the live copy and swapped in only once npm ci succeeded: a failed install
# (network, registry) must not leave the running gateway unable to start again.
staging="$GATEWAY_DIR.new"
rm -rf "$staging"
rsync -a --exclude node_modules --exclude '*.jsonl' --exclude 'subscriptions*.json' --exclude 'devices*.json' --exclude 'coverage-state*.json' --exclude 'heartbeats*.json' "$GATEWAY_SRC/" "$staging/"
(cd "$staging" && npm ci --omit=dev --no-audit --no-fund)
rm -rf "$GATEWAY_DIR.old"
if [[ -d $GATEWAY_DIR ]]; then
  mv "$GATEWAY_DIR" "$GATEWAY_DIR.old"
fi
mv "$staging" "$GATEWAY_DIR"
rm -rf "$GATEWAY_DIR.old"
chown -R "$GATEWAY_USER:" "$GATEWAY_DATA"

# Secrets are generated once; a rerun must not rotate them under running sensors and phones.
if [[ ! -f $GATEWAY_ENV ]]; then
  [[ -n ${VAPID_SUBJECT:-} ]] || die "set VAPID_SUBJECT=mailto:... (push services reject a missing contact)"
  vapid_json=$(cd "$GATEWAY_DIR" && node -e \
    'console.log(JSON.stringify(require("web-push").generateVAPIDKeys()))')
  vapid_public=$(node -e 'console.log(JSON.parse(process.argv[1]).publicKey)' "$vapid_json")
  vapid_private=$(node -e 'console.log(JSON.parse(process.argv[1]).privateKey)' "$vapid_json")
  umask 077
  cat > "$GATEWAY_ENV" <<EOF
PORT=8787
RELAY_HMAC_SECRET=$(openssl rand -hex 32)
RELAY_KILL_SWITCH=0
APNS_DRY_RUN=1
APNS_TEAM_ID=unset
APNS_KEY_ID=unset
APNS_BUNDLE_ID=unset
VAPID_SUBJECT=$VAPID_SUBJECT
VAPID_PUBLIC_KEY=$vapid_public
VAPID_PRIVATE_KEY=$vapid_private
EVIDENCE_FILE=$GATEWAY_DATA/gateway-evidence.jsonl
SUBSCRIPTIONS_FILE=$GATEWAY_DATA/subscriptions.json
DEVICES_FILE=$GATEWAY_DATA/devices.json
COVERAGE_STATE_FILE=$GATEWAY_DATA/coverage-state.json
HEARTBEATS_FILE=$GATEWAY_DATA/heartbeats.json
EOF
  umask 022
fi
# Added apart so an env file from before the certifier gets it without rotating the rest.
if ! grep -q '^MONITOR_KEY=' "$GATEWAY_ENV"; then
  echo "MONITOR_KEY=$(openssl rand -hex 32)" >> "$GATEWAY_ENV"
fi

cat > /etc/systemd/system/earthquake-gateway.service <<EOF
[Unit]
Description=Earthquake relay gateway
After=network-online.target
Wants=network-online.target

[Service]
User=$GATEWAY_USER
WorkingDirectory=$GATEWAY_DATA
EnvironmentFile=$GATEWAY_ENV
ExecStart=/usr/bin/node $GATEWAY_DIR/src/server.js
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Service workers and web push only work over HTTPS, so phones need a real domain.
if [[ -n ${GATEWAY_DOMAIN:-} ]]; then
  echo "== https via caddy for $GATEWAY_DOMAIN"
  apt-get install -y -q caddy
  printf '%s {\n\treverse_proxy 127.0.0.1:8787\n}\n' "$GATEWAY_DOMAIN" > /etc/caddy/Caddyfile
  systemctl reload-or-restart caddy
else
  echo "GATEWAY_DOMAIN not set: gateway only on 127.0.0.1, the web app will not work on phones"
fi

echo "== host checks"
mkdir -p "$TOOLS_DIR"
# lab.py comes along because sensor-health.py reuses its AEA checks.
install -m 755 "$SCRIPTS_SRC/lab.py" "$SCRIPTS_SRC/sensor-health.py" "$SCRIPTS_SRC/aea-geofix.py" \
  "$SCRIPTS_SRC/receptor-placement.py" "$TOOLS_DIR/"
install -m 644 "$SCRIPTS_SRC/aea-alerts-colombia.json" "$TOOLS_DIR/"

# Play Services reads the GPS once, minutes into each boot, and keeps that place. This feeds
# the assigned one during every boot (start, crash, guest reboot, spot restart). A fix sent
# later is accepted and ignored, so it cannot be left to the 5-minute health check.
cat > /etc/systemd/system/aea-geofix.service <<EOF
[Unit]
Description=Feed each emulator its assigned GPS fix while it boots
After=network-online.target

[Service]
User=$EMULATOR_USER
Environment=ANDROID_SDK_ROOT=$SDK_ROOT
ExecStart=/usr/bin/python3 $TOOLS_DIR/aea-geofix.py $SENSOR_MAP
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# AEA health per sensor, reported as aea_ok. Runs as the emulator user, the only one adb
# trusts. It signs with the per-sensor keys in the map, never with the gateway's secrets.
# Without the listener step's sensor map it exits 0 and waits for the next tick.
cat > /etc/systemd/system/sensor-health.service <<EOF
[Unit]
Description=Report AEA health of each sensor to the gateway

[Service]
Type=oneshot
User=$EMULATOR_USER
Environment=ANDROID_SDK_ROOT=$SDK_ROOT
ExecStart=/usr/bin/python3 $TOOLS_DIR/sensor-health.py $SENSOR_MAP
EOF
# Wall-clock schedule: it keeps firing whatever the last run did.
cat > /etc/systemd/system/sensor-health.timer <<EOF
[Unit]
Description=AEA health every 5 minutes

[Timer]
OnCalendar=*:0/5

[Install]
WantedBy=timers.target
EOF

# Proposes receptors where phones have no coverage (docs/siting-pilot.md). It never creates
# one: AUTO_RECEPTOR_BUDGET_USD defaults to 0, and at 0 every proposal is a proposal only.
cat > /etc/systemd/system/receptor-placement.service <<EOF
[Unit]
Description=Propose new receptors from demand and hazard

[Service]
Type=oneshot
User=$GATEWAY_USER
Environment=AUTO_RECEPTOR_BUDGET_USD=${AUTO_RECEPTOR_BUDGET_USD:-0}
ExecStart=/usr/bin/python3 $TOOLS_DIR/receptor-placement.py $GATEWAY_DATA/devices.json $GATEWAY_DIR/public/sensors.json $TOOLS_DIR/aea-alerts-colombia.json $GATEWAY_DATA/receptor-proposals.json
EOF
cat > /etc/systemd/system/receptor-placement.timer <<EOF
[Unit]
Description=Receptor proposals once a day

[Timer]
OnCalendar=*-*-* 06:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

if [[ -n ${NTFY_TOPIC:-} ]]; then
  umask 077
  echo "NTFY_TOPIC=$NTFY_TOPIC" > /etc/earthquake-watchdog.env
  umask 022
fi
# Quoted heredoc: the variables belong to the watchdog, not to this script.
cat > /usr/local/bin/gateway-watchdog <<'EOF'
#!/bin/sh
# Tells the operator once when the gateway stops answering, and once when it is back.
# Same, per push channel, when a sensor's last alert reached nobody on it (degraded in
# /status). A broken APNs cannot warn the iPhones itself, so this is the only warning.
down_marker=/run/gateway-watchdog.down
degraded_marker=/run/gateway-watchdog.degraded
notify() {
  logger -t gateway-watchdog "$1"
  [ -n "${NTFY_TOPIC:-}" ] && curl -fsS --max-time 10 -d "$1" "https://ntfy.sh/$NTFY_TOPIC" >/dev/null
  return 0
}
if status=$(curl -fsS --max-time 10 http://127.0.0.1:8787/status); then
  if [ -e "$down_marker" ]; then
    rm -f "$down_marker"
    notify "Alert gateway responding again."
  fi
  # The channel keys only appear inside each sensor's "degraded" object.
  channels=$(echo "$status" | grep -oE '"(apns|webpush)":"' | tr -d '":' | sort -u | paste -sd ' ' -)
  previous=$(cat "$degraded_marker" 2>/dev/null || true)
  if [ -n "$channels" ] && [ "$channels" != "$previous" ]; then
    echo "$channels" > "$degraded_marker"
    notify "Degraded channel: ${channels}. An alert reached no one on it. Check /status (APNs: .p8 key; webpush: VAPID)."
  elif [ -z "$channels" ] && [ -e "$degraded_marker" ]; then
    rm -f "$degraded_marker"
    notify "No degraded channel: a delivery succeeded or the gateway restarted."
  fi
elif [ ! -e "$down_marker" ]; then
  touch "$down_marker"
  notify "Alert gateway down: /status not responding. No one gets alerts or the no-coverage push."
fi
EOF
chmod 755 /usr/local/bin/gateway-watchdog
cat > /etc/systemd/system/gateway-watchdog.service <<'EOF'
[Unit]
Description=Check that the relay gateway answers

[Service]
Type=oneshot
EnvironmentFile=-/etc/earthquake-watchdog.env
ExecStart=/usr/local/bin/gateway-watchdog
EOF
cat > /etc/systemd/system/gateway-watchdog.timer <<'EOF'
[Unit]
Description=Gateway check every minute

[Timer]
OnCalendar=minutely

[Install]
WantedBy=timers.target
EOF

echo "== start"
systemctl daemon-reload
systemctl enable earthquake-gateway.service
# A rerun on a smaller host must not keep extra emulators alive. Their AVDs are kept, only
# the units are stopped, so a bigger host can bring them back.
# Enabled and running units both count: one started by hand without enable runs too.
emulator_units=$({
  ls /etc/systemd/system/multi-user.target.wants/ 2>/dev/null | grep '^aea-emulator@' || true
  systemctl list-units --plain --no-legend 'aea-emulator@*.service' | awk '{print $1}'
} | sort -u)
for unit in $emulator_units; do
  instance=${unit##*@}
  instance=${instance%.service}
  if (( instance > AVD_COUNT )); then
    systemctl disable --now "aea-emulator@$instance.service"
  fi
done
busy_ports=()
for i in $(seq 1 "$AVD_COUNT"); do
  port=$((5552 + 2 * i))
  # An emulator started by hand (for the Google sign-in) already holds the port and the
  # AVD lock; a second one would crash-loop against it every 30 s.
  if ! systemctl is-active --quiet "aea-emulator@$i.service" \
      && ss -ltnH "sport = :$port" | grep -q .; then
    echo "port $port busy outside aea-emulator@$i: stop that emulator, then rerun" >&2
    busy_ports+=("$port")
    continue
  fi
  # --no-block: each unit waits its turn in the queue, which must not hold this script.
  systemctl enable --now --no-block "aea-emulator@$i.service"
done
# Marks the restart as planned, so the certifier does not count it as the gateway going down.
evidence_file="$GATEWAY_DATA/gateway-evidence.jsonl"
gateway_version=$(sha256sum "$GATEWAY_DIR/src/server.js" | cut -c1-12)
printf '{"type":"DEPLOY","at":"%s","version":"%s"}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" "$gateway_version" >> "$evidence_file"
chown "$GATEWAY_USER:" "$evidence_file"
chmod 600 "$evidence_file"
# Restart, not start: a rerun has to pick up new gateway code.
systemctl restart earthquake-gateway.service
systemctl enable --now sensor-health.timer gateway-watchdog.timer receptor-placement.timer
# restart, not start: a rerun has to pick up a new aea-geofix.py.
systemctl enable aea-geofix.service
systemctl restart aea-geofix.service

(( ${#busy_ports[@]} == 0 )) || die "not done: emulator port(s) ${busy_ports[*]} busy, see above"
echo "done. emulators: systemctl status 'aea-emulator@*'  gateway: journalctl -u earthquake-gateway"
echo "next: sign in to Google on each AVD, then: $0 listener <apk> <sensor_id>..."
