#!/usr/bin/env bash
# Offline check of backup.sh and envelope.py: a fake ssh serves a tar of dummy files, the
# archive round-trips across every openssl on this machine (LibreSSL on macOS, OpenSSL 3 on
# Ubuntu), and a truncated, corrupted or wrong-passphrase archive fails loudly.
#
#   bash infra/new-account/test_backup.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$WORK/bin" "$WORK/root/etc/caddy" "$WORK/root/var/lib/earthquake-gateway" "$WORK/out"
echo "RELAY_HMAC_SECRET=dummy-master" > "$WORK/root/etc/earthquake-gateway.env"
echo "emulator-5554 chaparral 3.7 -75.4 dummykey" > "$WORK/root/etc/earthquake-sensors.map"
echo "AEA_ORIGIN_SECRET=dummy" > "$WORK/root/etc/caddy/origin.env"
echo '{"subscriptions":[]}' > "$WORK/root/var/lib/earthquake-gateway/subscriptions.json"
cat > "$WORK/bin/ssh" <<FAKE
#!/bin/sh
for arg; do last=\$arg; done
echo "\$last" > "$WORK/ssh-command"
cd "$WORK/root" && tar -czf - etc var
FAKE
chmod +x "$WORK/bin/ssh"

openssls=()
for candidate in /usr/bin/openssl /opt/homebrew/bin/openssl /usr/local/bin/openssl; do
  [[ -x $candidate ]] && openssls+=("$candidate")
done
((${#openssls[@]} > 0)) || fail "no openssl"
export AEA_BACKUP_PASS="correct horse battery staple"
open_with() {  # open_with <openssl> <archive>
  "$1" enc -d -aes-256-cbc -md sha256 -pbkdf2 -iter 600000 -pass env:AEA_BACKUP_PASS -in "$2" \
    | python3 "$HERE/envelope.py" open
}

for writer in "${openssls[@]}"; do
  mkdir -p "$WORK/bin-$$"; ln -sf "$writer" "$WORK/bin-$$/openssl"
  output=$(PATH="$WORK/bin-$$:$WORK/bin:$PATH" bash "$HERE/backup.sh" 10.0.0.1 "$WORK/out" 2>&1) \
    || fail "backup with $writer: $output"
  archive=$(ls -t "$WORK/out"/*.enc | head -1)
  for reader in "${openssls[@]}"; do
    restored=$(open_with "$reader" "$archive" | tar -xzOf - etc/earthquake-gateway.env) \
      || fail "$writer -> $reader does not open"
    [[ $restored == "RELAY_HMAC_SECRET=dummy-master" ]] || fail "$writer -> $reader wrong content"
  done
  rm -rf "$WORK/bin-$$"
  echo "PASS written with $writer, opens with: ${openssls[*]}"
done

head -c $(( $(wc -c < "$archive") - 40 )) "$archive" > "$WORK/truncated.enc"
open_with "${openssls[0]}" "$WORK/truncated.enc" >/dev/null 2>&1 && fail "a truncated backup opened"
cp "$archive" "$WORK/corrupt.enc"
printf 'X' | dd of="$WORK/corrupt.enc" bs=1 seek=200 conv=notrunc 2>/dev/null
open_with "${openssls[0]}" "$WORK/corrupt.enc" >/dev/null 2>&1 && fail "a corrupted backup opened"
AEA_BACKUP_PASS="wrong passphrase!!" open_with "${openssls[0]}" "$archive" >/dev/null 2>&1 && fail "wrong passphrase opened"
echo "PASS truncated, corrupted and wrong-passphrase backups fail"

# The APNs key is downloadable once: the host's tar must ask for it, and a backup whose env names
# a key it does not hold must fail.
[[ $(cat "$WORK/ssh-command") == *" etc/earthquake-gateway/*.p8 "* ]] || fail "the host tar does not ask for the APNs key"
echo "APNS_PRIVATE_KEY_FILE=/etc/earthquake-gateway/AuthKey_ABC123DEFG.p8" >> "$WORK/root/etc/earthquake-gateway.env"
output=$(PATH="$WORK/bin:$PATH" bash "$HERE/backup.sh" 10.0.0.1 "$WORK/out-nokey" 2>&1) && fail "a backup without the APNs key passed"
[[ $output == *"BACKUP_FAILED: etc/earthquake-gateway/AuthKey_ABC123DEFG.p8 missing"* && -z $(ls "$WORK/out-nokey") ]] \
  || fail "missing APNs key not reported, or the archive was kept: $output"
mkdir -p "$WORK/root/etc/earthquake-gateway"
echo "dummy key" > "$WORK/root/etc/earthquake-gateway/AuthKey_ABC123DEFG.p8"
output=$(PATH="$WORK/bin:$PATH" bash "$HERE/backup.sh" 10.0.0.1 "$WORK/out-key" 2>&1) || fail "backup with the APNs key: $output"
echo "PASS the host tar asks for the APNs key, and a backup without the key the env names fails"
