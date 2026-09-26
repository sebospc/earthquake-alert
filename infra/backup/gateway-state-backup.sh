#!/usr/bin/env bash
# Hourly on the receptor host (aea-gateway-backup.timer, infra/backup/install.sh): the gateway
# state and secrets, encrypted, into the deploy bucket under gateway-state/. Without it, losing
# the EBS volume silently unsubscribes every iPhone.
#
# Same archive format and file list as infra/new-account/backup.sh, so rebuild.sh restores an
# object from here as is. The passphrase is in /etc/earthquake-backup.pass (root, 0600) and in
# the operator's password manager. The host role may only PutObject under gateway-state/; it
# cannot read a backup back. Retention is the bucket's 30-day expiry.
# Every success sends GatewayBackupOk=1; the backup-stale alarm pages after 2 h without one.
set -euo pipefail
TOOLS_DIR=${TOOLS_DIR:-/opt/earthquake-tools}
PASS_FILE=${PASS_FILE:-/etc/earthquake-backup.pass}
ROOT_DIR=${ROOT_DIR:-/}
EMF_TARGET=${EMF_TARGET:-/dev/udp/127.0.0.1/25888}
CIPHER=(-aes-256-cbc -md sha256 -pbkdf2 -iter 600000)
trap 'echo "GATEWAY_BACKUP_FAILED line $LINENO" >&2' ERR
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if [[ -z ${BACKUP_BUCKET:-} || -z ${METRIC_HOST:-} ]]; then
  token=$(curl -fsS -m 5 -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
  identity=$(curl -fsS -m 5 -H "X-aws-ec2-metadata-token: $token" http://169.254.169.254/latest/dynamic/instance-identity/document)
  BACKUP_BUCKET=aea-lab-deploy-$(python3 -c 'import json, sys; print(json.load(sys.stdin)["accountId"])' <<<"$identity")
  METRIC_HOST=$(python3 -c 'import json, sys; print(json.load(sys.stdin)["instanceId"])' <<<"$identity")
fi

name=aea-backup-$(date -u +%Y%m%dT%H%M%SZ).tar.gz.enc
(cd "$ROOT_DIR" && shopt -s nullglob && tar -czpf - --ignore-failed-read etc/earthquake-gateway.env etc/earthquake-sensors.map \
    etc/caddy/origin.env etc/earthquake-gateway/*.p8 var/lib/earthquake-gateway/*.json*) \
  | python3 "$TOOLS_DIR/envelope.py" pack \
  | openssl enc "${CIPHER[@]}" -salt -pass "file:$PASS_FILE" -out "$work/$name"

# Upload only what opens and holds what cannot be regenerated: the secrets, the map, the users.
open_backup() { openssl enc -d "${CIPHER[@]}" -pass "file:$PASS_FILE" -in "$work/$name" | python3 "$TOOLS_DIR/envelope.py" open; }
contents=$(open_backup | tar -tzf -)
# The APNs key is downloadable once: a host rebuilt with the key id but no key reaches no iPhone.
apns_key=$(open_backup | tar -xzOf - etc/earthquake-gateway.env | sed -n "s|^APNS_PRIVATE_KEY_FILE=[\"']*/*\([^\"']*\).*|\1|p")
for required in etc/earthquake-gateway.env etc/earthquake-sensors.map var/lib/earthquake-gateway/subscriptions.json $apns_key; do
  [[ $'\n'$contents$'\n' == *$'\n'"$required"$'\n'* ]] || { echo "GATEWAY_BACKUP_FAILED: $required missing" >&2; exit 1; }
done

aws s3 cp --only-show-errors "$work/$name" "s3://$BACKUP_BUCKET/gateway-state/$name"
printf '{"_aws":{"Timestamp":%s000,"CloudWatchMetrics":[{"Namespace":"AeaLab","Dimensions":[["Host"]],"Metrics":[{"Name":"GatewayBackupOk"}]}]},"Host":"%s","GatewayBackupOk":1}\n' \
  "$(date +%s)" "$METRIC_HOST" >> "$EMF_TARGET"
echo "GATEWAY_BACKUP_OK s3://$BACKUP_BUCKET/gateway-state/$name ($(grep -c . <<<"$contents") files)"
