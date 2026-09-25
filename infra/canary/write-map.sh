#!/usr/bin/env bash
# Writes /etc/earthquake-sensors.map on a canary host, from the operator's machine:
#   infra/canary/write-map.sh <main public ip> <canary public ip> <sensor_id for emulator-5554> [<sensor_id for emulator-5556>]
# Per-sensor keys are HMAC(master, sensor_id), computed on the main host. They travel over
# ssh stdin straight into a root-only file: never on a command line, never on this machine's
# disk, and the master never leaves the main host. Unknown ids (not in the main gateway's
# sensors.json yet) stop it before anything is written.
set -euo pipefail
main_host=${1:?main public ip} canary_host=${2:?canary public ip}
shift 2
(($# >= 1 && $# <= 2)) || { echo "one or two sensor ids" >&2; exit 2; }
for id in "$@"; do [[ $id =~ ^[a-z0-9-]+$ ]] || { echo "bad sensor id: $id" >&2; exit 2; }; done
SSH_KEY=${SSH_KEY:-$HOME/.ssh/aea-lab.pem}
ssh_to() { ssh -i "$SSH_KEY" -o BatchMode=yes "ubuntu@$1" "${@:2}"; }

HERE="$(cd "$(dirname "$0")" && pwd)"
ssh_to "$main_host" sudo python3 - "$@" < "$HERE/sensor-map.py" \
  | ssh_to "$canary_host" "sudo sh -c 'umask 077; tmp=\$(mktemp /etc/.sensors.map.XXXXXX); cat > \"\$tmp\"; [ \$(wc -l < \"\$tmp\") -eq $# ] && chown aea:aea \"\$tmp\" && mv \"\$tmp\" /etc/earthquake-sensors.map && echo MAP_OK || { rm -f \"\$tmp\"; echo MAP_FAILED; exit 1; }'"
