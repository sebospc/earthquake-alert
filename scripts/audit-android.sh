#!/usr/bin/env bash
set -euo pipefail

label="${1:-device}"
ADB="$(command -v adb 2>/dev/null || true)"
if [[ -z "$ADB" && -x /opt/homebrew/share/android-commandlinetools/platform-tools/adb ]]; then
  ADB=/opt/homebrew/share/android-commandlinetools/platform-tools/adb
fi
if [[ -z "$ADB" ]]; then
  echo "adb is required" >&2
  exit 1
fi

serial_count="$("$ADB" devices | awk 'NR > 1 && $2 == "device" { count++ } END { print count + 0 }')"
if [[ "$serial_count" -ne 1 ]]; then
  echo "Exactly one authorized Android device must be connected; found $serial_count" >&2
  "$ADB" devices -l
  exit 1
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
output="evidence/${timestamp}-${label}-audit"
mkdir -p "$output"

"$ADB" devices -l > "$output/adb-devices.txt"
"$ADB" shell getprop > "$output/getprop.txt" || true
"$ADB" shell pm path com.google.android.gms > "$output/gms-path.txt" || true
"$ADB" shell dumpsys package com.google.android.gms > "$output/gms-package.txt" || true
"$ADB" shell dumpsys location > "$output/location.txt" || true
"$ADB" shell cmd location is-location-enabled > "$output/location-enabled.txt" 2>&1 || true
"$ADB" shell settings get secure location_mode > "$output/location-mode.txt" || true
"$ADB" shell settings get secure enabled_notification_listeners > "$output/listeners.txt" || true
"$ADB" shell dumpsys notification --noredact > "$output/notifications.txt" || true
"$ADB" shell dumpsys activity activities > "$output/activities.txt" || true
"$ADB" shell dumpsys window > "$output/window.txt" || true

{
  echo "captured_at_utc=$timestamp"
  echo "label=$label"
  echo "manual_play_protect_certified=TODO"
  echo "manual_earthquake_toggle_visible=TODO"
  echo "manual_earthquake_toggle_enabled=TODO"
  echo "manual_demo_available=TODO"
} > "$output/manual-checks.txt"

echo "$output"
