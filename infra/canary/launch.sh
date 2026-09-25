#!/usr/bin/env bash
# Launches one canary receptor host: spot persistent/stop (survives interruptions like the
# main host), nested virtualization for the emulators, the receptor instance profile, 30 GB
# (13 GB measured on the main host, two AVDs can grow to 6 GB each). Same subnet and security
# group as the main host, so the 8787 rule (source: that group) lets it reach the gateway.
#   infra/canary/launch.sh aea-lab-canary-a
set -euo pipefail
name=${1:?usage: launch.sh <Name tag>}
REGION=sa-east-1
MAIN_INSTANCE=${MAIN_INSTANCE:-i-0d1c0b6dd02e0ae61}

read -r image subnet security_group key_name < <(aws ec2 describe-instances --region "$REGION" \
  --instance-ids "$MAIN_INSTANCE" --output text --query \
  'Reservations[0].Instances[0].[ImageId,SubnetId,SecurityGroups[0].GroupId,KeyName]')

# Only receptor hosts in this group may reach the gateway forwarder. Already there = fine.
aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$security_group" \
  --ip-permissions "IpProtocol=tcp,FromPort=8787,ToPort=8787,UserIdGroupPairs=[{GroupId=$security_group,Description=receptor hosts to the gateway forwarder}]" \
  --tag-specifications 'ResourceType=security-group-rule,Tags=[{Key=project,Value=aea-lab}]' >/dev/null 2>&1 \
  || [[ $(aws ec2 describe-security-group-rules --region "$REGION" --filters "Name=group-id,Values=$security_group" \
       --query "SecurityGroupRules[?FromPort==\`8787\` && ReferencedGroupInfo.GroupId=='$security_group'] | [0].SecurityGroupRuleId" \
       --output text) == sgr-* ]] || { echo "LAUNCH_FAILED: no 8787 rule" >&2; exit 1; }

instance_id=$(aws ec2 run-instances --region "$REGION" --image-id "$image" --instance-type r8i.large \
  --subnet-id "$subnet" --security-group-ids "$security_group" --key-name "$key_name" \
  --cpu-options NestedVirtualization=enabled --iam-instance-profile Name=aea-lab-receptor \
  --instance-market-options 'MarketType=spot,SpotOptions={SpotInstanceType=persistent,InstanceInterruptionBehavior=stop}' \
  --metadata-options HttpTokens=required \
  --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=30,VolumeType=gp3,DeleteOnTermination=true}' \
  --tag-specifications "ResourceType=instance,Tags=[{Key=project,Value=aea-lab},{Key=Name,Value=$name}]" \
    'ResourceType=volume,Tags=[{Key=project,Value=aea-lab}]' 'ResourceType=spot-instances-request,Tags=[{Key=project,Value=aea-lab}]' \
  --query 'Instances[0].InstanceId' --output text)
aws ec2 wait instance-running --region "$REGION" --instance-ids "$instance_id"
aws ec2 describe-instances --region "$REGION" --instance-ids "$instance_id" --output text \
  --query 'Reservations[0].Instances[0].[InstanceId,PublicIpAddress,PrivateIpAddress,Placement.AvailabilityZone]'
