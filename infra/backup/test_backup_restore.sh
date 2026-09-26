#!/usr/bin/env bash
# Offline check of the hourly backup and its restore: a fake aws keeps the bucket in a temp dir.
# A backup round-trips byte for byte through fetch-latest.sh and rebuild.sh's decrypt, the newest
# one is the one fetched, and every failure (missing file, failed upload, damaged object) is loud
# and sends no GatewayBackupOk.
#
#   bash infra/backup/test_backup_restore.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

root=$WORK/root
mkdir -p "$WORK/bin" "$WORK/bucket/gateway-state" "$WORK/tools" "$root/etc/caddy" "$root/var/lib/earthquake-gateway"
echo "RELAY_HMAC_SECRET=dummy-master" > "$root/etc/earthquake-gateway.env"
echo "emulator-5554 chaparral 3.7 -75.4 dummykey" > "$root/etc/earthquake-sensors.map"
echo "AEA_ORIGIN_SECRET=dummy" > "$root/etc/caddy/origin.env"
echo '{"chaparral":[{"endpoint":"https://push.example/1"}]}' > "$root/var/lib/earthquake-gateway/subscriptions.json"
echo '{"device-1":{"token":"abc"}}' > "$root/var/lib/earthquake-gateway/devices.json"
echo '{"id":1}' > "$root/var/lib/earthquake-gateway/gateway-evidence.jsonl"
cp "$HERE/../new-account/envelope.py" "$WORK/tools/"
printf '%s' "correct horse battery staple" > "$WORK/pass"

cat > "$WORK/bin/aws" <<EOF
#!/usr/bin/env bash
[[ -n \${FAKE_AWS_FAIL:-} ]] && { echo "upload failed" >&2; exit 1; }
case "\$1 \$2" in
  "s3 cp")
    src=\$4 dst=\$5
    [[ \$dst == s3://* ]] && { cp "\$src" "$WORK/bucket/\${dst#s3://*/}"; exit 0; }
    cp "$WORK/bucket/\${src#s3://*/}" "\$dst" ;;
  "s3api list-objects-v2")
    newest=\$(ls "$WORK/bucket/gateway-state" | sort | tail -1)
    echo "\${newest:+gateway-state/}\${newest:-None}" ;;
  *) echo "fake aws: \$*" >&2; exit 2 ;;
esac
EOF
# macOS tar (bsdtar) has no --ignore-failed-read; the host runs GNU tar.
cat > "$WORK/bin/tar" <<'EOF'
#!/usr/bin/env bash
args=(); for a in "$@"; do [[ $a == --ignore-failed-read ]] || args+=("$a"); done
exec /usr/bin/tar "${args[@]}"
EOF
chmod +x "$WORK/bin/"*
export PATH="$WORK/bin:$PATH" BACKUP_BUCKET=fake-bucket METRIC_HOST=i-test \
  TOOLS_DIR="$WORK/tools" PASS_FILE="$WORK/pass" ROOT_DIR="$root" EMF_TARGET="$WORK/emf"

backup() { bash "$HERE/gateway-state-backup.sh" 2>&1; }
metric_count() { grep -c '"GatewayBackupOk":1' "$WORK/emf" 2>/dev/null || true; }

output=$(backup) || fail "first backup: $output"
[[ $output == "GATEWAY_BACKUP_OK s3://fake-bucket/gateway-state/aea-backup-"*" (6 files)" ]] || fail "first backup said: $output"
[[ $(metric_count) == 1 ]] || fail "no GatewayBackupOk after a good backup"
grep -q '"Host":"i-test"' "$WORK/emf" || fail "metric without the Host dimension"
sleep 1  # the key has a one-second stamp
echo '{"chaparral":[],"quibdo":[{"endpoint":"https://push.example/2"}]}' > "$root/var/lib/earthquake-gateway/subscriptions.json"
output=$(backup) || fail "second backup: $output"
[[ $(ls "$WORK/bucket/gateway-state" | wc -l | tr -d ' ') == 2 ]] || fail "expected two objects"
echo "PASS two hourly backups uploaded, one metric each"

export AEA_BACKUP_PASS="correct horse battery staple"
output=$(bash "$HERE/fetch-latest.sh" "$WORK/fetched" 2>&1) || fail "fetch: $output"
fetched=$(ls "$WORK/fetched"/*.enc)
[[ $fetched == *"$(ls "$WORK/bucket/gateway-state" | sort | tail -1)" ]] || fail "did not fetch the newest: $fetched"
# rebuild.sh's own decrypt, then the same tar -x it runs on the new host.
mkdir "$WORK/restored"
sed -n '/^decrypt()/,/envelope.py" open; }/p' "$HERE/../new-account/rebuild.sh" > "$WORK/decrypt.sh"
(backup="$fetched" ROOT="$HERE/../.."; source "$WORK/decrypt.sh"; decrypt | tar -xzpf - -C "$WORK/restored") \
  || fail "rebuild.sh cannot open the fetched backup"
diff -r "$root" "$WORK/restored" || fail "restored tree differs from the host"
echo "PASS newest backup fetched and restored byte for byte by rebuild.sh's decrypt"

before=$(ls "$WORK/bucket/gateway-state" | wc -l)
mv "$root/etc/earthquake-sensors.map" "$WORK/map.away"
backup >/dev/null && fail "a backup without the sensor map passed"
mv "$WORK/map.away" "$root/etc/earthquake-sensors.map"
rm "$root/var/lib/earthquake-gateway/subscriptions.json"
output=$(backup) && fail "a backup without subscriptions.json passed"
[[ $output == *"GATEWAY_BACKUP_FAILED"* ]] || fail "missing subscriptions not reported: $output"
echo '{}' > "$root/var/lib/earthquake-gateway/subscriptions.json"
FAKE_AWS_FAIL=1 backup >/dev/null && fail "a failed upload passed"
[[ $(ls "$WORK/bucket/gateway-state" | wc -l) == "$before" ]] || fail "a failed backup left an object"
[[ $(metric_count) == 2 ]] || fail "a failed backup sent GatewayBackupOk"
echo "PASS missing map, missing subscriptions and failed upload: loud, no object, no metric"

newest=$(ls "$WORK/bucket/gateway-state" | sort | tail -1)
printf 'X' | dd of="$WORK/bucket/gateway-state/$newest" bs=1 seek=200 conv=notrunc 2>/dev/null
rm -rf "$WORK/fetched"
output=$(bash "$HERE/fetch-latest.sh" "$WORK/fetched" 2>&1) && fail "a corrupted backup was fetched as good"
[[ $output == *"FETCH_FAILED"* && -z $(ls "$WORK/fetched") ]] || fail "corrupted fetch not loud or left a file: $output"
rm -rf "$WORK/bucket/gateway-state"/*
output=$(bash "$HERE/fetch-latest.sh" "$WORK/fetched" 2>&1) && fail "an empty bucket fetched something"
[[ $output == *"no backup in s3://fake-bucket/gateway-state/"* ]] || fail "empty bucket not reported: $output"
echo "PASS corrupted object and empty bucket fail loudly"

# The APNs key is downloadable once: once the env points at it, it must be in every backup.
env_file=$root/etc/earthquake-gateway.env
mkdir -p "$root/etc/earthquake-gateway"
echo "-----BEGIN PRIVATE KEY----- dummy" > "$root/etc/earthquake-gateway/AuthKey_ABC123DEFG.p8"
echo 'APNS_PRIVATE_KEY_FILE="/etc/earthquake-gateway/AuthKey_ABC123DEFG.p8"' >> "$env_file"
output=$(backup) || fail "backup with the APNs key: $output"
newest=$(ls "$WORK/bucket/gateway-state" | sort | tail -1)
key_back=$(openssl enc -d -aes-256-cbc -md sha256 -pbkdf2 -iter 600000 -pass "file:$PASS_FILE" -in "$WORK/bucket/gateway-state/$newest" \
  | python3 "$HERE/../new-account/envelope.py" open | tar -xzOf - etc/earthquake-gateway/AuthKey_ABC123DEFG.p8) \
  || fail "the APNs key is not in the backup"
[[ $key_back == "-----BEGIN PRIVATE KEY----- dummy" ]] || fail "the APNs key came back wrong"
sed -i.bak 's|^APNS_PRIVATE_KEY_FILE=.*|APNS_PRIVATE_KEY_FILE=/home/ubuntu/AuthKey_ABC123DEFG.p8|' "$env_file"
output=$(backup) && fail "a key outside /etc/earthquake-gateway/ passed"
[[ $output == *"GATEWAY_BACKUP_FAILED: home/ubuntu/AuthKey_ABC123DEFG.p8 missing"* ]] || fail "key outside not reported: $output"
sed -i.bak 's|^APNS_PRIVATE_KEY_FILE=.*|APNS_PRIVATE_KEY_FILE=/etc/earthquake-gateway/AuthKey_ABC123DEFG.p8|' "$env_file"
rm "$root/etc/earthquake-gateway/AuthKey_ABC123DEFG.p8"
output=$(backup) && fail "a backup without the key the env names passed"
[[ $output == *"AuthKey_ABC123DEFG.p8 missing"* ]] || fail "missing key not reported: $output"
[[ $(metric_count) == 3 ]] || fail "a backup without the APNs key sent GatewayBackupOk"
echo "PASS the APNs key the env names is backed up, and a backup without it fails"
