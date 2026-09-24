#!/usr/bin/env bash
# Fleet of Android emulators, each pinned to a Colombian city, listening for
# real Android Earthquake Alerts. Cloned from a working AVD so the Google
# sign-in and the updated Play Services carry over.
set -euo pipefail

SDK="${ANDROID_SDK_ROOT:-/opt/homebrew/share/android-commandlinetools}"
EMULATOR="$SDK/emulator/emulator"
ADB="$SDK/platform-tools/adb"
AVD_HOME="$HOME/.android/avd"
TEMPLATE="AEA_Pixel8_API35_Play"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT/evidence/fleet-logs"
BOOT_TIMEOUT_TRIES=48   # 48 x 5s = 4 minutes per emulator

# port:name:lat:lon  — chosen from the real Google alert list, see docs/fleet-siting.md
FLEET=(
  "5554:bucaramanga-a:7.1193:-73.1227"
  "5556:hinatuan:8.3667:126.3333"
  "5558:chaparral:3.7236:-75.4836"
  "5560:quibdo:5.6947:-76.6611"
)

avd_name() { echo "AEA_$1"; }

create() {
  [[ -d "$AVD_HOME/$TEMPLATE.avd" ]] || { echo "template AVD $TEMPLATE missing" >&2; exit 1; }
  for entry in "${FLEET[@]}"; do
    IFS=: read -r _ name _ _ <<< "$entry"
    local avd; avd="$(avd_name "$name")"
    if [[ -d "$AVD_HOME/$avd.avd" ]]; then
      echo "exists  $avd"
      continue
    fi
    cp -R "$AVD_HOME/$TEMPLATE.avd" "$AVD_HOME/$avd.avd"
    # Stale absolute paths and the old id would point the clone back at the template.
    rm -f "$AVD_HOME/$avd.avd/"{hardware-qemu.ini,emulator-user.ini,*.lock}
    rm -rf "$AVD_HOME/$avd.avd/snapshots"
    sed -i '' "s|$TEMPLATE|$avd|g" "$AVD_HOME/$avd.avd/config.ini"
    printf 'avd.ini.encoding=UTF-8\npath=%s\npath.rel=avd/%s.avd\ntarget=android-35\n' \
      "$AVD_HOME/$avd.avd" "$avd" > "$AVD_HOME/$avd.ini"
    echo "created $avd"
  done
}

start() {
  mkdir -p "$LOG_DIR"
  for entry in "${FLEET[@]}"; do
    IFS=: read -r port name lat lon <<< "$entry"
    local avd; avd="$(avd_name "$name")"
    if "$ADB" devices | grep -q "emulator-$port[[:space:]]*device"; then
      echo "running $name (emulator-$port)"
      continue
    fi
    # setsid, so the emulator leaves the caller's process group. Without this a
    # launchd restart of the supervisor kills every emulator the supervisor
    # started, and a months-long run would cold boot on each restart.
    python3 -c '
import os, sys
os.setsid()
log = os.open(sys.argv[1], os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
os.dup2(log, 1); os.dup2(log, 2)
devnull = os.open(os.devnull, os.O_RDONLY); os.dup2(devnull, 0)
os.execv(sys.argv[2], sys.argv[2:])
' "$LOG_DIR/$name.log" "$EMULATOR" -avd "$avd" -port "$port" \
      -no-window -no-audio -no-boot-anim -no-snapshot \
      -gpu swiftshader_indirect &
    echo "starting $name on emulator-$port (avd $avd)"
  done
  echo "waiting for boot..."
  # Bounded: an emulator that never comes up must not block the others. The
  # watcher already treats an absent device as down, and the next cycle retries.
  for entry in "${FLEET[@]}"; do
    IFS=: read -r port name _ _ <<< "$entry"
    booted=""
    for _ in $(seq 1 "$BOOT_TIMEOUT_TRIES"); do
      if [[ "$("$ADB" -s "emulator-$port" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then
        booted=1
        break
      fi
      sleep 5
    done
    [[ -n "$booted" ]] && echo "booted  $name" || echo "TIMEOUT $name did not boot, continuing"
  done
  provision
}

provision() {
  for entry in "${FLEET[@]}"; do
    IFS=: read -r port name lat lon <<< "$entry"
    local serial="emulator-$port"
    "$ADB" -s "$serial" emu geo fix "$lon" "$lat" >/dev/null
    "$ADB" -s "$serial" shell cmd notification allow_listener com.earthquakes.relay/.CaptureService >/dev/null 2>&1 || true
    "$ADB" -s "$serial" shell pm grant com.earthquakes.fixture android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
    # The listener only binds once its activity has run at least one time.
    "$ADB" -s "$serial" shell am start -n com.earthquakes.relay/.MainActivity >/dev/null 2>&1 || true
    echo "provisioned $name at $lat,$lon"
  done
}

install_apps() {
  (cd "$ROOT" && ./gradlew :android-listener:assembleDebug :android-fixture:assembleDebug --no-daemon --console=plain)
  for entry in "${FLEET[@]}"; do
    IFS=: read -r port name _ _ <<< "$entry"
    local serial="emulator-$port"
    "$ADB" -s "$serial" install -r -g "$ROOT/android-listener/build/outputs/apk/debug/android-listener-debug.apk"
    "$ADB" -s "$serial" install -r -g "$ROOT/android-fixture/build/outputs/apk/debug/android-fixture-debug.apk"
    echo "installed on $name"
  done
  provision
}

status() {
  printf '%-16s %-14s %-8s %-22s %s\n' DEVICE SERIAL BOOTED LOCATION EVENTS
  for entry in "${FLEET[@]}"; do
    IFS=: read -r port name lat lon <<< "$entry"
    local serial="emulator-$port" booted="no" events="-" loc="-"
    if "$ADB" devices | grep -q "$serial[[:space:]]*device"; then
      booted="$("$ADB" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
      [[ "$booted" == "1" ]] && booted="yes" || booted="booting"
      loc="$lat,$lon"
      events="$("$ADB" -s "$serial" exec-out run-as com.earthquakes.relay cat files/notification-evidence.jsonl 2>/dev/null | wc -l | tr -d ' ')"
    fi
    printf '%-16s %-14s %-8s %-22s %s\n' "$name" "$serial" "$booted" "$loc" "$events"
  done
}

stop() {
  for entry in "${FLEET[@]}"; do
    IFS=: read -r port name _ _ <<< "$entry"
    "$ADB" -s "emulator-$port" emu kill >/dev/null 2>&1 && echo "stopped $name" || echo "not running $name"
  done
}

case "${1:-status}" in
  create) create ;;
  start) start ;;
  install) install_apps ;;
  provision) provision ;;
  status) status ;;
  stop) stop ;;
  *) echo "usage: fleet.sh {create|start|install|provision|status|stop}" >&2; exit 1 ;;
esac
