#!/usr/bin/env bash
# Everything a new AWS account needs to carry on as the same service, in ONE encrypted file
# on this machine, never in the repo:
#   - /etc/earthquake-gateway.env: the master HMAC secret (every receptor's relay.json key
#     derives from it), the VAPID keys (every web push subscription is bound to them), APNs;
#   - /var/lib/earthquake-gateway/*.json and *.jsonl: subscriptions, devices, coverage state,
#     heartbeats, evidence;
#   - /etc/earthquake-sensors.map: which emulator is which receptor, with its key;
#   - /etc/caddy/origin.env: the CloudFront origin secret.
#
#   infra/new-account/backup.sh <old host ip> [out dir]
# The passphrase is asked for (not echoed), or taken from AEA_BACKUP_PASS; never from a command
# line. Output: <out dir>/aea-backup-<utc>.tar.gz.enc (default ~/aea-backups). The plaintext
# carries its own sha256 (envelope.py): CBC has no integrity, a damaged file must fail loudly.
set -euo pipefail
host=${1:?usage: backup.sh <old host ip> [out dir]}
out_dir=${2:-$HOME/aea-backups}
SSH_KEY=${SSH_KEY:-$HOME/.ssh/aea-lab.pem}
HERE="$(cd "$(dirname "$0")" && pwd)"
if [[ -z ${AEA_BACKUP_PASS:-} ]]; then
  read -rsp "Backup passphrase (12+ characters): " AEA_BACKUP_PASS </dev/tty; echo >&2
fi
export AEA_BACKUP_PASS
[[ ${#AEA_BACKUP_PASS} -ge 12 ]] || { echo "passphrase too short (12+ characters)" >&2; exit 2; }
# -md sha256 spelled out: LibreSSL (macOS) and OpenSSL 3 (Ubuntu) must derive the same key.
CIPHER=(-aes-256-cbc -md sha256 -pbkdf2 -iter 600000)
repo_root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || true)
mkdir -p "$out_dir"
out_dir=$(cd "$out_dir" && pwd)
[[ -z $repo_root || $out_dir != "$repo_root"* ]] || { echo "refusing to write secrets inside the repo" >&2; exit 2; }

out="$out_dir/aea-backup-$(date -u +%Y%m%dT%H%M%SZ).tar.gz.enc"
umask 077
# ssh or tar dying mid-stream must not leave a half archive next to the good ones (QA-97).
trap 'rm -f "$out"' ERR
# tar on the host streams straight into the cipher here: no plaintext copy on either disk.
ssh -i "$SSH_KEY" -o BatchMode=yes "ubuntu@$host" \
  "sudo sh -c 'cd / && tar -czpf - --ignore-failed-read etc/earthquake-gateway.env etc/earthquake-sensors.map etc/caddy/origin.env var/lib/earthquake-gateway/*.json*'" \
  | python3 "$HERE/envelope.py" pack \
  | openssl enc "${CIPHER[@]}" -salt -pass env:AEA_BACKUP_PASS -out "$out"

# Prove it opens and holds the two things that cannot be regenerated.
contents=$(openssl enc -d "${CIPHER[@]}" -pass env:AEA_BACKUP_PASS -in "$out" | python3 "$HERE/envelope.py" open | tar -tzf -) \
  || { echo "BACKUP_FAILED: the new archive does not open" >&2; rm -f "$out"; exit 1; }
for required in etc/earthquake-gateway.env etc/earthquake-sensors.map; do
  [[ $'\n'$contents$'\n' == *$'\n'"$required"$'\n'* ]] || { echo "BACKUP_FAILED: $required missing" >&2; rm -f "$out"; exit 1; }
done
echo "BACKUP_OK $out ($(wc -l <<<"$contents" | tr -d ' ') files)"
