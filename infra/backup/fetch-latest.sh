#!/usr/bin/env bash
# The newest hourly gateway backup from S3 into ~/aea-backups, checked, ready for
# infra/new-account/rebuild.sh (same format as backup.sh). For a lost host or a lost disk:
#
#   AWS_PROFILE=<admin> infra/backup/fetch-latest.sh [out dir]
#   AWS_PROFILE=<admin> ALERT_EMAIL=... infra/new-account/rebuild.sh <the file it prints>
#
# Needs s3:ListBucket and s3:GetObject on the deploy bucket: the host role cannot read backups.
# The passphrase is asked for (not echoed), or taken from AEA_BACKUP_PASS.
set -euo pipefail
out_dir=${1:-$HOME/aea-backups}
HERE="$(cd "$(dirname "$0")" && pwd)"
die() { echo "FETCH_FAILED: $*" >&2; rm -f "${out:-}"; exit 1; }
bucket=${BACKUP_BUCKET:-aea-lab-deploy-$(aws sts get-caller-identity --query Account --output text)}
if [[ -z ${AEA_BACKUP_PASS:-} ]]; then
  read -rsp "Backup passphrase: " AEA_BACKUP_PASS </dev/tty; echo >&2
fi
export AEA_BACKUP_PASS

# The keys carry a UTC stamp, so the last one in key order is the newest.
key=$(aws s3api list-objects-v2 --bucket "$bucket" --prefix gateway-state/ --query 'Contents[-1].Key' --output text)
[[ $key == gateway-state/aea-backup-*.tar.gz.enc ]] || die "no backup in s3://$bucket/gateway-state/"
mkdir -p "$out_dir"
out="$out_dir/${key#gateway-state/}"
umask 077
trap 'rm -f "$out"' ERR
aws s3 cp --only-show-errors "s3://$bucket/$key" "$out"

contents=$(openssl enc -d -aes-256-cbc -md sha256 -pbkdf2 -iter 600000 -pass env:AEA_BACKUP_PASS -in "$out" \
  | python3 "$HERE/../new-account/envelope.py" open | tar -tzf -) || die "$key does not open (passphrase?)"
for required in etc/earthquake-gateway.env etc/earthquake-sensors.map var/lib/earthquake-gateway/subscriptions.json; do
  [[ $'\n'$contents$'\n' == *$'\n'"$required"$'\n'* ]] || die "$key has no $required"
done
stamp=${key#gateway-state/aea-backup-}
echo "FETCH_OK $out (taken ${stamp%.tar.gz.enc}, $(grep -c . <<<"$contents") files)"
