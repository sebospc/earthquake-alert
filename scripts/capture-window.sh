#!/usr/bin/env bash
set -euo pipefail

label="${1:-window}"
ADB="$(command -v adb 2>/dev/null || true)"
if [[ -z "$ADB" && -x /opt/homebrew/share/android-commandlinetools/platform-tools/adb ]]; then
  ADB=/opt/homebrew/share/android-commandlinetools/platform-tools/adb
fi
if [[ -z "$ADB" ]]; then
  echo "adb is required" >&2
  exit 1
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
output="evidence/${timestamp}-${label}"
mkdir -p "$output"

"$ADB" logcat -c
"$ADB" logcat -b all -v epoch > "$output/logcat.txt" &
logcat_pid=$!
trap 'kill "$logcat_pid" 2>/dev/null || true' EXIT

echo "Capture active. Reproduce or observe the event, then press Enter."
read -r

"$ADB" shell dumpsys notification --noredact > "$output/notifications.txt"
"$ADB" shell dumpsys activity activities > "$output/activities.txt"
"$ADB" shell dumpsys window > "$output/window.txt"
"$ADB" shell dumpsys package com.google.android.gms > "$output/gms-package.txt"
kill "$logcat_pid" 2>/dev/null || true
wait "$logcat_pid" 2>/dev/null || true
trap - EXIT

echo "$output"
