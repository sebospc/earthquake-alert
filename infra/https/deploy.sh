#!/usr/bin/env bash
# Deploys the HTTPS staging from the operator's machine. The origin secret lives only in SSM
# Parameter Store (SecureString), on the host in a root-only file, and in CloudFront's origin
# config. Never in the repo, never on a command line on the host, never in SSM command history.
#
#   infra/https/deploy.sh secret   # create it once if missing, push it to the host over ssh stdin
#   sudo infra/https/install.sh    # on the host (needs the coordinator's approval)
#   infra/https/deploy.sh stack    # EIP, SG rule and CloudFront, with the secret as NoEcho
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REGION=sa-east-1
INSTANCE_ID=${INSTANCE_ID:-i-0d1c0b6dd02e0ae61}
PARAMETER=/aea-lab/origin-secret
SSH_KEY=${SSH_KEY:-$HOME/.ssh/aea-lab.pem}

read_secret() {
  aws ssm get-parameter --region "$REGION" --name "$PARAMETER" --with-decryption \
    --query Parameter.Value --output text 2>/dev/null
}

case ${1:-} in
  secret)
    if ! secret=$(read_secret); then
      aws ssm put-parameter --region "$REGION" --name "$PARAMETER" --type SecureString \
        --tags Key=project,Value=aea-lab --value "$(openssl rand -hex 32)" >/dev/null
      secret=$(read_secret)
    fi
    host=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
      --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
    printf 'AEA_ORIGIN_SECRET=%s\n' "$secret" | ssh -i "$SSH_KEY" "ubuntu@$host" \
      'sudo install -d /etc/caddy && sudo install -m 600 -o root -g root /dev/stdin /etc/caddy/origin.env'
    echo "origin secret on $INSTANCE_ID; next: sudo infra/https/install.sh on the host"
    ;;
  stack)
    secret=$(read_secret) || { echo "no $PARAMETER: run deploy.sh secret first" >&2; exit 1; }
    security_group=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
      --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text)
    prefix_list=$(aws ec2 describe-managed-prefix-lists --region "$REGION" \
      --filters Name=prefix-list-name,Values=com.amazonaws.global.cloudfront.origin-facing \
      --query 'PrefixLists[0].PrefixListId' --output text)
    aws cloudformation deploy --region "$REGION" --stack-name aea-lab-https \
      --template-file "$HERE/stack.yml" --tags project=aea-lab --parameter-overrides \
      "InstanceId=$INSTANCE_ID" "SecurityGroupId=$security_group" \
      "CloudFrontPrefixList=$prefix_list" "OriginSecret=$secret"
    aws cloudformation describe-stacks --region "$REGION" --stack-name aea-lab-https \
      --query 'Stacks[0].Outputs' --output text
    ;;
  *) echo "usage: $0 secret|stack" >&2; exit 2 ;;
esac
