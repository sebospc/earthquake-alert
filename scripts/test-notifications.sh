#!/usr/bin/env bash
set -euo pipefail

ADB="$(command -v adb 2>/dev/null || true)"
if [[ -z "$ADB" && -x /opt/homebrew/share/android-commandlinetools/platform-tools/adb ]]; then
  ADB=/opt/homebrew/share/android-commandlinetools/platform-tools/adb
fi
if [[ -z "$ADB" ]]; then
  echo "adb is required" >&2
  exit 1
fi

if [[ "$("$ADB" devices | awk 'NR > 1 && $2 == "device" { count++ } END { print count + 0 }')" -ne 1 ]]; then
  echo "Exactly one Android device must be connected" >&2
  exit 1
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
output="evidence/${timestamp}-functional-notifications"
mkdir -p "$output"

./gradlew :android-listener:installDebug :android-fixture:installDebug \
  --no-daemon --console=plain
"$ADB" shell pm grant com.earthquakes.fixture android.permission.POST_NOTIFICATIONS
"$ADB" shell cmd notification allow_listener com.earthquakes.relay/.CaptureService
"$ADB" shell am start -n com.earthquakes.relay/.MainActivity >/dev/null
sleep 2
"$ADB" shell run-as com.earthquakes.relay rm -f files/notification-evidence.jsonl

"$ADB" shell am broadcast \
  -n com.earthquakes.fixture/.FixtureReceiver \
  -a com.earthquakes.fixture.POST_NORMAL >/dev/null
sleep 1

"$ADB" shell appops set com.earthquakes.fixture USE_FULL_SCREEN_INTENT allow
"$ADB" shell input keyevent SLEEP
"$ADB" shell am broadcast \
  -n com.earthquakes.fixture/.FixtureReceiver \
  -a com.earthquakes.fixture.POST_FULL_SCREEN >/dev/null
sleep 2

"$ADB" shell dumpsys activity activities > "$output/activities.txt"
"$ADB" shell dumpsys notification --noredact > "$output/notifications.txt"
"$ADB" exec-out screencap -p > "$output/full-screen.png"
"$ADB" exec-out run-as com.earthquakes.relay sh -c \
  'cat files/notification-evidence.jsonl' > "$output/listener.jsonl"
"$ADB" shell appops set com.earthquakes.fixture USE_FULL_SCREEN_INTENT default

node --input-type=module - "$output/listener.jsonl" "$output/activities.txt" <<'NODE'
import { readFileSync } from "node:fs";

const [evidencePath, activitiesPath] = process.argv.slice(2);
const events = readFileSync(evidencePath, "utf8")
  .trim()
  .split("\n")
  .filter(Boolean)
  .map(JSON.parse);
const normal = events.find(event =>
  event.notification_id === 2001 &&
  event.source_label === "SYNTHETIC_FIXTURE" &&
  event.has_full_screen_intent === false
);
const full = events.find(event =>
  event.notification_id === 2002 &&
  event.source_label === "SYNTHETIC_FIXTURE" &&
  event.has_full_screen_intent === true
);
const activities = readFileSync(activitiesPath, "utf8");

if (!normal) throw new Error("normal notification was not captured");
if (!full) throw new Error("full-screen notification was not captured");
if (!activities.includes("com.earthquakes.fixture/.AlertActivity")) {
  throw new Error("full-screen AlertActivity did not open");
}
console.log("PASS normal notification");
console.log("PASS full-screen listener callback");
console.log("PASS full-screen Activity presentation");
NODE

echo "$output"
