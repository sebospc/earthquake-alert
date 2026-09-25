#!/usr/bin/env bash
# Rebuilds the whole receptor service in a fresh AWS account, from a backup.sh archive.
# Run from the repo on the operator's machine, with the NEW account's admin credentials:
#
#   AWS_PROFILE=new-admin ALERT_EMAIL=you@example.com \
#     infra/new-account/rebuild.sh ~/aea-backups/aea-backup-<utc>.tar.gz.enc
# The backup passphrase is asked for (or AEA_BACKUP_PASS); never on a command line.
#
# Every step checks before it creates, so a rerun after a failure picks up where it stopped.
# The backup is restored once (marker on the host): a rerun never rolls back subscriptions
# made since. Human-only steps are in README.md; what is left is printed at the end.
set -euo pipefail

backup=${1:?usage: rebuild.sh <backup.tar.gz.enc>}
: "${ALERT_EMAIL:?set ALERT_EMAIL (the SNS alarm address)}"
if [[ -z ${AEA_BACKUP_PASS:-} ]]; then
  read -rsp "Backup passphrase: " AEA_BACKUP_PASS </dev/tty; echo >&2
fi
export AEA_BACKUP_PASS
export AWS_REGION=${AWS_REGION:-sa-east-1} AWS_DEFAULT_REGION=${AWS_REGION:-sa-east-1}
REPO=${REPO:-sebospc/earthquake-alert}
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NAME=aea-lab-sensor-1
KEY_NAME=aea-lab
VAPID_SUBJECT=${VAPID_SUBJECT:-mailto:alertas@example.com}
leftover=()

step() { echo; echo "== $*"; }
die() { echo "REBUILD_FAILED: $*" >&2; exit 1; }
# Verified on every read: a damaged backup never restores half a config.
decrypt() { openssl enc -d -aes-256-cbc -md sha256 -pbkdf2 -iter 600000 -pass env:AEA_BACKUP_PASS -in "$backup" \
  | python3 "$ROOT/infra/new-account/envelope.py" open; }

step "account and backup"
account=$(aws sts get-caller-identity --query Account --output text)
echo "account $account, region $AWS_REGION"
backup_files=$(decrypt | tar -tzf -) || die "cannot open the backup (passphrase?)"
[[ $'\n'$backup_files$'\n' == *$'\n'etc/earthquake-sensors.map$'\n'* ]] || die "backup has no sensor map"
sensor_map=$(decrypt | tar -xzOf - etc/earthquake-sensors.map)
emulator_count=$(grep -c . <<<"$sensor_map")
listener_pairs=$(awk 'NF >= 2 {printf "%s=%s ", $1, $2}' <<<"$sensor_map")
sensor_ids=$(awk 'NF >= 2 {print $2}' <<<"$sensor_map")
echo "receptors: $listener_pairs"
SSH_KEY=${SSH_KEY:-$HOME/.ssh/aea-lab-$account.pem}

step "spot service-linked role"
aws iam create-service-linked-role --aws-service-name spot.amazonaws.com >/dev/null 2>&1 \
  || echo "already there"

step "deploy stack (OIDC, deploy role, bucket, receptor instance profile)"
oidc_prefix=$(gh api "repos/$REPO/actions/oidc/customization/sub" --jq .sub_claim_prefix)
provider_count=$(aws iam list-open-id-connect-providers --output text \
  --query "length(OpenIDConnectProviderList[?ends_with(Arn, 'token.actions.githubusercontent.com')])")
create_provider=true
[[ $provider_count == 0 ]] || create_provider=false
# A stack that made the provider keeps owning it: never flip it to false on a rerun.
existing=$(aws cloudformation describe-stacks --stack-name aea-lab-deploy \
  --query "Stacks[0].Parameters[?ParameterKey=='CreateOidcProvider'].ParameterValue" --output text 2>/dev/null || true)
[[ $existing == true ]] && create_provider=true
aws cloudformation deploy --stack-name aea-lab-deploy --template-file "$ROOT/infra/deploy/stack.yml" \
  --capabilities CAPABILITY_NAMED_IAM --no-fail-on-empty-changeset --tags project=aea-lab \
  --parameter-overrides "CreateOidcProvider=$create_provider" "OidcSubjectPrefix=$oidc_prefix"
stack_output() { aws cloudformation describe-stacks --stack-name "$1" --output text \
  --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue"; }
deploy_role_arn=$(stack_output aea-lab-deploy DeployRoleArn)
deploy_bucket=$(stack_output aea-lab-deploy ArtifactBucketName)

step "ssh key pair"
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" >/dev/null 2>&1; then
  [[ -f $SSH_KEY ]] || die "key pair $KEY_NAME exists in the account but $SSH_KEY is not here"
  echo "already there: $SSH_KEY"
else
  (umask 077; aws ec2 create-key-pair --key-name "$KEY_NAME" --key-type ed25519 \
    --tag-specifications 'ResourceType=key-pair,Tags=[{Key=project,Value=aea-lab}]' \
    --query KeyMaterial --output text > "$SSH_KEY")
  echo "created $SSH_KEY"
fi

step "security group"
vpc=$(aws ec2 describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text)
[[ $vpc == vpc-* ]] || die "no default VPC in $AWS_REGION"
security_group=$(aws ec2 describe-security-groups --filters Name=group-name,Values=aea-lab-receptor "Name=vpc-id,Values=$vpc" \
  --query 'SecurityGroups[0].GroupId' --output text)
if [[ $security_group != sg-* ]]; then
  security_group=$(aws ec2 create-security-group --group-name aea-lab-receptor --vpc-id "$vpc" \
    --description "aea-lab receptor host" --tag-specifications 'ResourceType=security-group,Tags=[{Key=project,Value=aea-lab}]' \
    --query GroupId --output text)
fi
operator_ip=$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')
aws ec2 authorize-security-group-ingress --group-id "$security_group" --protocol tcp --port 22 \
  --cidr "$operator_ip/32" >/dev/null 2>&1 || echo "ssh from $operator_ip already allowed"

step "receptor host (spot r8i.large, persistent/stop, nested virtualization)"
instance_id=$(aws ec2 describe-instances --output text --query 'Reservations[].Instances[0].InstanceId' \
  --filters "Name=tag:Name,Values=$NAME" Name=tag:project,Values=aea-lab \
  Name=instance-state-name,Values=pending,running,stopping,stopped)
if [[ $instance_id != i-* ]]; then
  image=$(aws ssm get-parameter --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
    --query Parameter.Value --output text)
  subnet=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc" Name=default-for-az,Values=true \
    --query 'Subnets[0].SubnetId' --output text)
  # 60 GB: 13 GB measured for 2 AVDs + system, each AVD may grow to 6 GB more.
  instance_id=$(aws ec2 run-instances --image-id "$image" --instance-type r8i.large --subnet-id "$subnet" \
    --security-group-ids "$security_group" --key-name "$KEY_NAME" \
    --cpu-options NestedVirtualization=enabled --iam-instance-profile Name=aea-lab-receptor \
    --instance-market-options 'MarketType=spot,SpotOptions={SpotInstanceType=persistent,InstanceInterruptionBehavior=stop}' \
    --metadata-options HttpTokens=required \
    --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=60,VolumeType=gp3}' \
    --tag-specifications "ResourceType=instance,Tags=[{Key=project,Value=aea-lab},{Key=Name,Value=$NAME}]" \
      'ResourceType=volume,Tags=[{Key=project,Value=aea-lab}]' \
    --query 'Instances[0].InstanceId' --output text)
  echo "launched $instance_id"
fi
aws ec2 start-instances --instance-ids "$instance_id" >/dev/null 2>&1 || true
aws ec2 wait instance-running --instance-ids "$instance_id"

step "origin secret from the backup into SSM, then the HTTPS stack (Elastic IP first: the address stops moving)"
secret_file=$(mktemp); trap 'rm -f "$secret_file"' EXIT
decrypt | tar -xzOf - etc/caddy/origin.env 2>/dev/null | sed -n 's/^AEA_ORIGIN_SECRET=//p' > "$secret_file" || true
if [[ -s $secret_file ]]; then
  # file:// keeps the value off every command line.
  aws ssm put-parameter --name /aea-lab/origin-secret --type SecureString --overwrite \
    --value "file://$secret_file" >/dev/null
fi
INSTANCE_ID=$instance_id SSH_KEY=$SSH_KEY "$ROOT/infra/https/deploy.sh" stack

host=$(aws ec2 describe-instances --instance-ids "$instance_id" --output text \
  --query 'Reservations[0].Instances[0].PublicIpAddress')
on_host() { ssh -i "$SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "ubuntu@$host" "$@"; }
for _ in $(seq 60); do on_host true 2>/dev/null && break; sleep 10; done
on_host true || die "no ssh to $host"

step "code: the reviewed main, not this working tree"
git -C "$ROOT" fetch -q origin main
commit=$(git -C "$ROOT" rev-parse origin/main)
git -C "$ROOT" archive --format=tar "$commit" | on_host 'rm -rf ~/earthquake-alert && mkdir ~/earthquake-alert && tar -x -C ~/earthquake-alert'
echo "main at $commit"

step "restore the backup (once): secrets, map, subscriptions, before the bootstrap"
# Before the bootstrap on purpose: it keeps an existing gateway env, so the master HMAC and
# VAPID keys stay the ones every receptor and every subscription already uses.
if on_host 'test -e /var/lib/aea-restored'; then
  echo "already restored"
else
  decrypt | on_host 'sudo tar -xzpf - -C / && sudo touch /var/lib/aea-restored'
  echo "restored $(grep -c . <<<"$backup_files") files"
fi

step "bootstrap with EMULATOR_COUNT=$emulator_count"
on_host "cd ~/earthquake-alert/scripts && sudo EMULATOR_COUNT=$emulator_count VAPID_SUBJECT=$VAPID_SUBJECT ./aws-bootstrap.sh" \
  | tail -5

step "listener APK from the last green CI run on main, onto every receptor"
apk_dir=$(mktemp -d)
ci_run=$(gh run list -R "$REPO" --workflow ci.yml --branch main --status success --limit 1 --json databaseId,headSha \
  --jq '.[0] | "\(.databaseId) \(.headSha)"')
gh run download -R "$REPO" "${ci_run% *}" --name "listener-apk-${ci_run#* }" --dir "$apk_dir"
(cd "$apk_dir" && shasum -a 256 -c listener.apk.sha256) || die "APK checksum mismatch"
on_host 'cat > /tmp/listener.apk' < "$apk_dir/listener.apk"
# Emulators boot one after the other; each must be up before its listener goes in.
for serial in $(awk 'NF >= 2 {print $1}' <<<"$sensor_map"); do
  for _ in $(seq 90); do
    [[ $(on_host "sudo -u aea -H /opt/android-sdk/platform-tools/adb -s $serial shell getprop sys.boot_completed 2>/dev/null" | tr -d '\r') == 1 ]] && break
    sleep 20
  done
done
on_host "cd ~/earthquake-alert/scripts && sudo ./aws-bootstrap.sh listener /tmp/listener.apk $listener_pairs" | tail -3

step "CloudWatch: shared stack, agent and probe, hourly backup, host alarms"
aws cloudformation deploy --stack-name aea-lab-cloudwatch --template-file "$ROOT/infra/cloudwatch/stack.yml" \
  --no-fail-on-empty-changeset --tags project=aea-lab --parameter-overrides "AlertEmail=$ALERT_EMAIL"
on_host 'sudo ~/earthquake-alert/infra/cloudwatch/install.sh' | tail -2
# Before the alarms: backup-stale pages until the first upload. Same passphrase as this backup.
on_host 'sudo ~/earthquake-alert/infra/backup/install.sh' <<<"$AEA_BACKUP_PASS" | tail -2
journal_hostname=$(on_host hostname)
aws cloudformation deploy --stack-name "aea-lab-alarms-$instance_id" --template-file "$ROOT/infra/cloudwatch/host-alarms.yml" \
  --no-fail-on-empty-changeset --tags project=aea-lab \
  --parameter-overrides "Host=$instance_id" "JournalHostname=$journal_hostname"

step "HTTPS origin: secret on the host, Caddy"
INSTANCE_ID=$instance_id SSH_KEY=$SSH_KEY "$ROOT/infra/https/deploy.sh" secret
on_host 'sudo ~/earthquake-alert/infra/https/install.sh' | tail -1

step "GitHub: point the pipeline at the new account"
gh variable set AWS_DEPLOY_ROLE_ARN -R "$REPO" --body "$deploy_role_arn"
gh variable set DEPLOY_BUCKET -R "$REPO" --body "$deploy_bucket"
gh variable set RECEPTOR_INSTANCE_ID -R "$REPO" --body "$instance_id"

step "verify"
public_url=$(stack_output aea-lab-https PublicUrl)
elastic_ip=$(stack_output aea-lab-https ElasticIp)
covered=""
for _ in $(seq 45); do
  if covered=$(on_host 'curl -fsS 127.0.0.1:8787/status' | python3 -c '
import json, sys
wanted = sys.argv[1].split()
covered = {s["id"] for s in json.load(sys.stdin)["sensors"] if s["covered"]}
missing = [i for i in wanted if i not in covered]
print("missing: " + " ".join(missing) if missing else "all covered")
sys.exit(1 if missing else 0)' "$sensor_ids"); then break; fi
  sleep 20
done
echo "receptors: $covered"
[[ $covered == "all covered" ]] || leftover+=("receptors not covered yet ($covered): check /status and sensor-health")
"$ROOT/infra/https/verify.sh" "$public_url" "$elastic_ip" | tail -1 || leftover+=("infra/https/verify.sh failed: rerun it and read each line")
alarm_states=$(aws cloudwatch describe-alarms --alarm-name-prefix "aea-lab-$instance_id" \
  --query 'MetricAlarms[].[AlarmName,StateValue]' --output text)
echo "$alarm_states"
# Every host alarm must exist: no alarms at all must not read as "all OK" (QA-95).
missing_alarms=""
for alarm in gateway-down receptor-uncovered backup-stale swap-in-use memory-low location-age aea-not-ok nudge-failed; do
  [[ $'\n'$alarm_states == *$'\n'"aea-lab-$instance_id-$alarm"$'\t'* ]] || missing_alarms+=" $alarm"
done
[[ -z $missing_alarms ]] || leftover+=("host alarms MISSING:$missing_alarms (check the aea-lab-alarms-$instance_id stack)")
not_ok=$(awk '$2 != "OK" {print $1}' <<<"$alarm_states")
[[ -z $not_ok ]] || leftover+=("alarms not OK yet (some need 15-20 min of data): $not_ok")

echo
echo "REBUILD_DONE account=$account host=$instance_id ip=$elastic_ip url=$public_url"
echo "Left for a human (see README.md):"
echo "  - confirm the SNS subscription email sent to $ALERT_EMAIL"
echo "  - the gateway URL is now $public_url: without our own domain the iPhone app needs an App Store update (see README.md)"
echo "  - update docs/STATUS.md (instance, IP, URL) and ~/.ssh config to $SSH_KEY"
echo "  - approve one pipeline deploy in GitHub to prove OIDC and SSM in the new account"
echo "  - point the certifier at the new host: MONITOR_INSTANCE=$instance_id MONITOR_SSH_KEY=$SSH_KEY, AWS creds that can read ec2:DescribeInstances in account $account; tell developer-qa"
echo "  - stop the OLD gateway once this one verifies, or users get every alert twice (both hold the same subscriptions):"
echo "      on the old host: sudo systemctl disable --now gateway-watchdog.timer earthquake-gateway   (NOT RELAY_KILL_SWITCH=1: it pushes 'uncovered' to everyone)"
echo "  - then, and only then, tear down the old account"
for item in "${leftover[@]}"; do echo "  - $item"; done
