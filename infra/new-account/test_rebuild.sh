#!/usr/bin/env bash
# Offline check of rebuild.sh: fake aws, gh, ssh, git and curl keep their state in a temp dir,
# so a second run sees what the first one created. Proves the step order (the backup is
# restored BEFORE the bootstrap, so the secrets are kept), that a rerun creates nothing and
# restores nothing again, and that the backup passphrase never reaches a command line.
#
#   bash infra/new-account/test_rebuild.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
mkdir -p "$WORK/bin" "$WORK/state" "$WORK/src/etc/caddy"
LOG="$WORK/calls.log"; : > "$LOG"
export PASS_FOR_TEST="correct horse battery staple" LOG STATE="$WORK/state"

# A backup like backup.sh writes, with two receptors.
echo "RELAY_HMAC_SECRET=dummy" > "$WORK/src/etc/earthquake-gateway.env"
printf 'emulator-5554 chaparral 3.7 -75.4 k1\nemulator-5556 quibdo 5.6 -76.6 k2\n' > "$WORK/src/etc/earthquake-sensors.map"
echo "AEA_ORIGIN_SECRET=0123456789abcdef0123456789abcdef" > "$WORK/src/etc/caddy/origin.env"
(cd "$WORK/src" && tar -czf - etc) | python3 "$HERE/envelope.py" pack \
  | AEA_BACKUP_PASS=$PASS_FOR_TEST openssl enc -aes-256-cbc -md sha256 -pbkdf2 -iter 600000 -salt -pass env:AEA_BACKUP_PASS \
  > "$WORK/backup.enc"

cat > "$WORK/bin/aws" <<'EOF'
#!/usr/bin/env bash
echo "aws $*" >> "$LOG"
has() { [[ -e $STATE/$1 ]]; }
case "$1 $2" in
  "sts get-caller-identity") echo 111122223333 ;;
  "iam create-service-linked-role") has slr && exit 1; touch "$STATE/slr" ;;
  "iam list-open-id-connect-providers") has oidc && echo 1 || echo 0 ;;
  "cloudformation deploy")
    stack=$(sed -n 's/.*--stack-name \([^ ]*\).*/\1/p' <<<"$*"); touch "$STATE/stack-$stack"
    [[ $* == *CreateOidcProvider=true* ]] && touch "$STATE/oidc"; echo "deployed $stack" ;;
  "cloudformation describe-stacks")
    stack=$(sed -n 's/.*--stack-name \([^ ]*\).*/\1/p' <<<"$*")
    has "stack-$stack" || exit 255
    case "$*" in
      *CreateOidcProvider*) echo true ;;
      *DeployRoleArn*) echo arn:aws:iam::111122223333:role/aea-lab-github-deploy ;;
      *ArtifactBucketName*) echo aea-lab-deploy-111122223333 ;;
      *PublicUrl*) echo https://dnew.cloudfront.net ;;
      *ElasticIp*) echo 203.0.113.10 ;;
      *) echo "ElasticIp 203.0.113.10" ;;
    esac ;;
  "ec2 describe-key-pairs") has keypair ;;
  "ec2 create-key-pair") touch "$STATE/keypair"; echo "-----FAKE KEY-----" ;;
  "ec2 describe-vpcs") echo vpc-1 ;;
  "ec2 describe-security-groups") has sg && echo sg-1 || echo None ;;
  "ec2 create-security-group") touch "$STATE/sg"; echo sg-1 ;;
  "ec2 authorize-security-group-ingress") has ssh-rule && exit 1; touch "$STATE/ssh-rule" ;;
  "ec2 describe-instances")
    case "$*" in
      *tag:Name*) has instance && echo i-1 || echo None ;;
      *PublicIpAddress*) echo 203.0.113.10 ;;
      *GroupId*) echo sg-1 ;;
    esac ;;
  "ec2 describe-subnets") echo subnet-1 ;;
  "ec2 run-instances") touch "$STATE/instance"; echo i-1 ;;
  "ec2 start-instances"|"ec2 wait") ;;
  "ec2 describe-managed-prefix-lists") echo pl-1 ;;
  "ssm get-parameter")
    case "$*" in *origin-secret*) cat "$STATE/origin-secret" ;; *) echo ami-1 ;; esac ;;
  "ssm put-parameter") file=$(sed -n 's/.*file:\/\/\([^ ]*\).*/\1/p' <<<"$*"); cp "$file" "$STATE/origin-secret" ;;
  "cloudwatch describe-alarms")
    [[ -n ${FAKE_NO_ALARMS:-} ]] && exit 0
    for alarm in gateway-down receptor-uncovered backup-stale swap-in-use memory-low location-age aea-not-ok nudge-failed; do
      printf 'aea-lab-i-1-%s\tOK\n' "$alarm"
    done ;;
  *) echo "fake aws: unexpected $*" >&2; exit 9 ;;
esac
EOF
cat > "$WORK/bin/ssh" <<'EOF'
#!/usr/bin/env bash
while [[ $1 == -* ]]; do [[ $1 == -i || $1 == -o ]] && shift; shift; done
shift  # user@host
command="$*"
echo "ssh $command" >> "$LOG"
case "$command" in
  true) ;;
  "test -e /var/lib/aea-restored") [[ -e $STATE/restored ]] ;;
  *"tar -xzpf -"*) cat > "$STATE/restored-payload"; touch "$STATE/restored" ;;
  *"backup/install.sh"*) cat > "$STATE/backup-pass" ;;
  hostname) echo ip-10-0-0-1 ;;
  *"getprop sys.boot_completed"*) echo 1 ;;
  *"127.0.0.1:8787/status"*)
    quibdo=true; [[ -n ${FAKE_UNCOVERED:-} ]] && quibdo=false
    echo "{\"sensors\":[{\"id\":\"chaparral\",\"covered\":true},{\"id\":\"quibdo\",\"covered\":$quibdo}]}" ;;
  # Only commands that take input read stdin: reading it for all would block on an open pipe.
  *"cat > "*|*"tar -x"*|*"/dev/stdin"*) cat > /dev/null ;;
  *) ;;
esac
EOF
cat > "$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >> "$LOG"
case "$1 $2" in
  "api repos/sebospc/earthquake-alert/actions/oidc/customization/sub") echo "repo:sebospc@1/earthquake-alert@2" ;;
  "run list") echo "42 abc123" ;;
  "run download")
    dir=$(sed -n 's/.*--dir \([^ ]*\).*/\1/p' <<<"$*")
    echo apk > "$dir/listener.apk"; (cd "$dir" && shasum -a 256 listener.apk > listener.apk.sha256) ;;
  "variable set") ;;
  *) echo "fake gh: unexpected $*" >&2; exit 9 ;;
esac
EOF
cat > "$WORK/bin/git" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *fetch*) ;;
  *rev-parse*) echo 1234567890abcdef ;;
  *archive*) tar -cf - -T /dev/null ;;
  *) echo "fake git: unexpected $*" >&2; exit 9 ;;
esac
EOF
cat > "$WORK/bin/curl" <<'EOF'
#!/usr/bin/env bash
url=${!#}; method=GET
while (($#)); do [[ $1 == -X ]] && method=$2; shift; done
case "$url" in
  *checkip*) echo 198.51.100.7; exit 0 ;;
  http://203.0.113.10/*) printf 000; exit 0 ;;
  http://*) printf 301; exit 0 ;;
esac
case "$method ${url#https://dnew.cloudfront.net}" in
  "GET /status"|"GET /"|"GET /sw.js") printf 200 ;;
  "POST /subscribe"|"POST /devices"|"DELETE /devices") printf 400 ;;
  *) printf 404 ;;
esac
EOF
# The real openssl, behind a wrapper that logs its arguments: a passphrase passed as
# `-pass pass:...` would show up in the log (QA-96).
real_openssl=$(command -v openssl)
printf '#!/bin/sh\necho "openssl $*" >> "$LOG"\nexec %s "$@"\n' "$real_openssl" > "$WORK/bin/openssl"
# Waits are instant here: a step that would loop until its deadline fails fast instead.
printf '#!/bin/sh\nexit 0\n' > "$WORK/bin/sleep"
chmod +x "$WORK/bin/"*

run_rebuild() {
  PATH="$WORK/bin:$PATH" HOME="$WORK" ALERT_EMAIL=ops@example.com AEA_BACKUP_PASS=$PASS_FOR_TEST \
    bash "$HERE/rebuild.sh" "$WORK/backup.enc" 2>&1
}
mkdir -p "$WORK/.ssh"

output=$(run_rebuild) || fail "first run: $output"
grep -q "^REBUILD_DONE account=111122223333 host=i-1" <<<"$output" || fail "no REBUILD_DONE: $output"
order_of() { grep -n -m1 -- "$1" "$LOG" | cut -d: -f1; }
previous=0
for mark in "create-service-linked-role" "--stack-name aea-lab-deploy" "run-instances" "--stack-name aea-lab-https" \
            "ssh sudo tar -xzpf -" "aws-bootstrap.sh$" "aws-bootstrap.sh listener /tmp/listener.apk emulator-5554=chaparral emulator-5556=quibdo" \
            "--stack-name aea-lab-cloudwatch" "cloudwatch/install.sh" "backup/install.sh" "--stack-name aea-lab-alarms-i-1" "https/install.sh" "gh variable set"; do
  line=$(order_of "$mark"); [[ -n $line ]] || fail "step never ran: $mark"
  ((line > previous)) || fail "step out of order: $mark"
  previous=$line
done
grep -q "EMULATOR_COUNT=2 " "$LOG" || fail "EMULATOR_COUNT must come from the backup's map"
[[ $(cat "$WORK/state/backup-pass") == "$PASS_FOR_TEST" ]] || fail "the hourly backup must get the backup's passphrase on stdin"
grep -q "RELAY_HMAC_SECRET=dummy" <(tar -xzOf "$WORK/state/restored-payload" etc/earthquake-gateway.env) \
  || fail "the restore must carry the gateway env"
grep -q "0123456789abcdef" "$WORK/state/origin-secret" || fail "the origin secret must come from the backup"
echo "PASS first run: every step, in order, restore before bootstrap, secrets from the backup"

: > "$LOG"
output=$(run_rebuild) || fail "second run: $output"
grep -q "^REBUILD_DONE" <<<"$output" || fail "rerun did not finish: $output"
for created in run-instances create-key-pair create-security-group "tar -xzpf"; do
  ! grep -q -- "$created" "$LOG" || fail "rerun did it again: $created"
done
echo "PASS rerun creates nothing and does not restore over live state"

grep -q "^openssl enc -d" "$LOG" || fail "the openssl wrapper was not used"
! grep -rqF "$PASS_FOR_TEST" "$LOG" || fail "the backup passphrase reached a command line"
echo "PASS the backup passphrase never appears in any command, openssl included"

output=$(FAKE_UNCOVERED=1 run_rebuild) || fail "uncovered run: $output"
grep -q "receptors not covered yet (missing: quibdo)" <<<"$output" || fail "an uncovered receptor must be a leftover: $output"
echo "PASS an uncovered receptor is reported, not passed"

output=$(FAKE_NO_ALARMS=1 run_rebuild) || fail "no-alarms run: $output"
grep -q "host alarms MISSING: gateway-down receptor-uncovered backup-stale swap-in-use memory-low location-age aea-not-ok nudge-failed" <<<"$output" \
  || fail "no alarms at all must be reported missing: $output"
grep -q "MONITOR_INSTANCE=i-1" <<<"$output" || fail "the certifier repoint must be a leftover"
echo "PASS missing alarms are reported, and the certifier repoint is listed"
