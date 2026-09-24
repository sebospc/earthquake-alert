#!/usr/bin/env bash
# Installs log shipping and the alarm probe on the receptor host. Idempotent, touches no
# emulator and no gateway process. Needs the instance role with CloudWatchAgentServerPolicy.
#
#   sudo AEA_CW_GPSKEEPER=quibdo infra/cloudwatch/install.sh
#
# AEA_CW_GPSKEEPER: this host's receptors running GpsKeeperService, comma separated, or ""
# when none. Required: the deliveries alarm must watch exactly the right receptors.
#
# Survives a spot stop/start: everything lives on the EBS root and every unit is enabled.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TOOLS_DIR=/opt/earthquake-tools
SENSOR_MAP=/etc/earthquake-sensors.map
EMULATOR_USER=aea
REGION="${AWS_REGION:-sa-east-1}"

[[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }
[[ -n ${AEA_CW_GPSKEEPER+set} ]] || { echo "set AEA_CW_GPSKEEPER (\"\" if no GpsKeeper receptor here)" >&2; exit 1; }
imds_token=$(curl -fsS -m 5 -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
instance_id=$(curl -fsS -m 5 -H "X-aws-ec2-metadata-token: $imds_token" http://169.254.169.254/latest/meta-data/instance-id)

if ! dpkg -s amazon-cloudwatch-agent >/dev/null 2>&1; then
  deb="$(mktemp --suffix=.deb)"
  curl -fsSL -o "$deb" "https://amazoncloudwatch-agent-$REGION.s3.$REGION.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb"
  dpkg -i "$deb"
  rm -f "$deb"
fi

install -d -o "$EMULATOR_USER" -g "$EMULATOR_USER" -m 0750 /var/lib/aea-cw /var/log/aea-cw
install -D -m 0755 "$HERE/aea-cw-probe.py" "$TOOLS_DIR/aea-cw-probe.py"
install -D -m 0644 "$HERE/amazon-cloudwatch-agent.json" /opt/aws/amazon-cloudwatch-agent/etc/aea-lab.json

cat > /etc/systemd/system/aea-cw-probe.service <<EOF
[Unit]
Description=CloudWatch alarm probe: gateway, coverage, earthquake_alerting deliveries
[Service]
Type=oneshot
User=$EMULATOR_USER
Nice=10
Environment=AEA_CW_HOST=$instance_id
Environment=AEA_CW_GPSKEEPER=$AEA_CW_GPSKEEPER
ExecStart=/usr/bin/python3 $TOOLS_DIR/aea-cw-probe.py $SENSOR_MAP
EOF

cat > /etc/systemd/system/aea-cw-probe.timer <<'EOF'
[Unit]
Description=CloudWatch alarm probe every minute
[Timer]
OnCalendar=minutely
AccuracySec=1s
Persistent=false
[Install]
WantedBy=timers.target
EOF

# The agent reads files only, not journald. The cursor file makes a restart resume where it
# stopped instead of re-sending or skipping.
cat > /etc/systemd/system/aea-cw-journal.service <<'EOF'
[Unit]
Description=Copy the relay units' journal to a file the CloudWatch agent ships
[Service]
ExecStart=/bin/sh -c 'exec journalctl --follow --output=short-iso --cursor-file=/var/lib/aea-cw/journal.cursor -u earthquake-gateway -u sensor-health -u "aea-*" >> /var/log/aea-cw/journal.log'
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF

cat > /etc/logrotate.d/aea-cw <<'EOF'
/var/log/aea-cw/*.log /var/log/aea-cw/*.jsonl {
  weekly
  rotate 4
  compress
  missingok
  notifempty
  copytruncate
}
EOF

systemctl daemon-reload
systemctl enable --now aea-cw-journal.service aea-cw-probe.timer
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/aea-lab.json

# Prove it: the agent runs and the probe reaches /status.
sleep 5
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status | grep -q '"status": "running"'
systemctl start aea-cw-probe.service
systemctl is-active --quiet aea-cw-journal.service
echo "CLOUDWATCH_INSTALL_OK host=$instance_id gpskeeper=$AEA_CW_GPSKEEPER"
echo "next: deploy infra/cloudwatch/host-alarms.yml with Host=$instance_id"
