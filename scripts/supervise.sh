#!/usr/bin/env bash
# Keeps the fleet up and the watcher running. Restarts emulators that died,
# then does one watch pass. Meant to be driven by launchd so it survives a
# reboot; a months-long run that silently stops after a restart is worthless.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$ROOT/evidence/supervise.log"
mkdir -p "$(dirname "$LOG")"

# The display never sleeps and the disk stays spun up while this runs.
caffeinate -dimsu -w $$ &

while true; do
  {
    echo "--- $(date -u +%Y-%m-%dT%H:%M:%SZ) ---"
    "$ROOT/scripts/fleet.sh" start 2>&1 | grep -vE "^(waiting|booted)" || true
    python3 "$ROOT/scripts/lab.py" once 2>&1
  } >> "$LOG" 2>&1
  sleep 300
done
