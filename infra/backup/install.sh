#!/usr/bin/env bash
# Installs the hourly gateway state backup on the receptor host and runs it once. Idempotent,
# touches no emulator and no gateway process. Needs the aea-lab-receptor role with the
# gateway-state PutObject grant (infra/deploy/stack.yml) and the CloudWatch agent (EMF).
#
#   ssh ubuntu@<host> 'sudo ~/earthquake-alert/infra/backup/install.sh' <<<"$AEA_BACKUP_PASS"
#
# The passphrase comes on stdin, never on a command line. Keep it in the password manager as
# well: the copy on the host dies with the host, and without it no backup opens.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TOOLS_DIR=/opt/earthquake-tools

[[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }
IFS= read -r passphrase || true
[[ ${#passphrase} -ge 12 ]] || { echo "backup passphrase on stdin (12+ characters)" >&2; exit 2; }
(umask 077; printf '%s' "$passphrase" > /etc/earthquake-backup.pass)

command -v aws >/dev/null || snap install aws-cli --classic
install -D -m 0755 "$HERE/gateway-state-backup.sh" "$TOOLS_DIR/gateway-state-backup.sh"
install -D -m 0644 "$HERE/../new-account/envelope.py" "$TOOLS_DIR/envelope.py"

cat > /etc/systemd/system/aea-gateway-backup.service <<EOF
[Unit]
Description=Encrypted gateway state backup to S3
[Service]
Type=oneshot
Nice=10
Environment=AWS_DEFAULT_REGION=${AWS_REGION:-sa-east-1}
ExecStart=$TOOLS_DIR/gateway-state-backup.sh
EOF

cat > /etc/systemd/system/aea-gateway-backup.timer <<'EOF'
[Unit]
Description=Gateway state backup every hour
[Timer]
OnCalendar=hourly
RandomizedDelaySec=300
Persistent=true
[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now aea-gateway-backup.timer
# Prove it once now: a first upload that fails must fail the install, not the 2 h alarm.
systemctl start aea-gateway-backup.service
journalctl -u aea-gateway-backup.service -n 20 --no-pager | grep -o 'GATEWAY_BACKUP_OK .*' | tail -1
echo "GATEWAY_BACKUP_INSTALL_OK"
