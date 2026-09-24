#!/usr/bin/env bash
# Runs on the GitHub runner, with the OIDC role already assumed. Ships the build in <dist_dir>
# to the host over S3 presigned URLs and runs remote.sh steps there with SSM Run Command.
# No SSH, no inbound port, no key on the host.
#
#   ssm-run.sh <instance_id> <bucket> <commit> <dist_dir> "<step>"...
#
# Each step is remote.sh's arguments, BUNDLE standing for the downloaded dir, e.g.
# "gateway BUNDLE abc123". Exit 0 only if SSM says Success and every step printed DEPLOY_OK.
set -euo pipefail

instance_id=$1 bucket=$2 commit=$3 dist_dir=$4
shift 4
(($# > 0)) || { echo "no steps" >&2; exit 2; }

# The artifact must still be exactly what CI built.
(cd "$dist_dir" && sha256sum -c --quiet SHA256SUMS)

script=$'set -euo pipefail\nd=$(mktemp -d)\ntrap \'rm -rf "$d"\' EXIT\n'
for path in "$dist_dir"/*; do
  name=$(basename "$path")
  key="$commit/$(date -u +%Y%m%dT%H%M%SZ)/$name"
  aws s3 cp --only-show-errors "$path" "s3://$bucket/$key"
  url=$(aws s3 presign "s3://$bucket/$key" --expires-in 900)
  script+="curl -fsS -o \"\$d/$name\" '$url'"$'\n'
done
# Checked again on the host: what was downloaded is what CI built.
script+="(cd \"\$d\" && sha256sum -c --quiet SHA256SUMS)"$'\n'
script+=$'mkdir "$d/t" && tar -xzf "$d/tools.tar.gz" -C "$d/t"\n(cd "$d/t" && sha256sum -c --quiet "$d/tools.manifest")\n'
for step in "$@"; do
  script+="bash \"\$d/t/infra/deploy/remote.sh\" ${step//BUNDLE/\"\$d\"}"$'\n'
done

command_id=$(aws ssm send-command --instance-ids "$instance_id" --document-name AWS-RunShellScript \
  --comment "deploy $commit" --timeout-seconds 60 \
  --parameters "$(jq -n --arg script "$script" '{commands: [$script], executionTimeout: ["1500"]}')" \
  --query Command.CommandId --output text)
echo "SSM command $command_id on $instance_id"

deadline=$((SECONDS + 1600))
status=Pending
while [[ $status == Pending || $status == InProgress || $status == Delayed ]]; do
  ((SECONDS < deadline)) || { echo "::error::SSM command did not finish in time"; exit 1; }
  sleep 10
  status=$(aws ssm get-command-invocation --command-id "$command_id" --instance-id "$instance_id" \
    --query Status --output text 2>/dev/null || echo Pending)
done

output=$(aws ssm get-command-invocation --command-id "$command_id" --instance-id "$instance_id" \
  --query '[StandardOutputContent,StandardErrorContent]' --output text)
echo "$output"
[[ $status == Success ]] || { echo "::error::SSM status $status"; exit 1; }
deploy_ok_count=$(grep -c '^DEPLOY_OK' <<<"$output" || true)
((deploy_ok_count == $#)) || { echo "::error::$deploy_ok_count of $# steps proved they landed"; exit 1; }
