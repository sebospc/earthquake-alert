#!/usr/bin/env bash
# One gateway for every receptor host. The gateway listens on 127.0.0.1:8787 only, and the
# listener may only speak cleartext to 10.0.2.2:8787 (the host's loopback), so:
#   main host:   sudo forward.sh main              private IP:8787 -> 127.0.0.1:8787
#   canary host: sudo forward.sh canary <main ip>  127.0.0.1:8787  -> main private IP:8787
# Port 8787 on the private IP is reachable only from the receptor security group itself.
# Idempotent. Never touches the gateway or an emulator.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }
mode=${1:?usage: forward.sh main | canary <main private ip>}

imds_token=$(curl -fsS -m 5 -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
own_ip=$(curl -fsS -m 5 -H "X-aws-ec2-metadata-token: $imds_token" http://169.254.169.254/latest/meta-data/local-ipv4)

case $mode in
  main)
    listen="TCP-LISTEN:8787,bind=$own_ip,reuseaddr,fork"
    target="TCP:127.0.0.1:8787"
    check_url="http://$own_ip:8787/status"
    ;;
  canary)
    main_ip=${2:?usage: forward.sh canary <main private ip>}
    [[ $main_ip =~ ^[0-9.]+$ ]] || { echo "bad ip: $main_ip" >&2; exit 1; }
    # A canary host must not run its own gateway: the forwarder takes its port.
    ! systemctl is-active --quiet earthquake-gateway.service \
      || { echo "FORWARD_FAILED: a gateway runs here; canary hosts use the main one" >&2; exit 1; }
    listen="TCP-LISTEN:8787,bind=127.0.0.1,reuseaddr,fork"
    target="TCP:$main_ip:8787,connect-timeout=5"
    check_url="http://127.0.0.1:8787/status"
    ;;
  *) echo "usage: forward.sh main | canary <main private ip>" >&2; exit 2 ;;
esac

command -v socat >/dev/null || apt-get install -y -q socat
cat > /etc/systemd/system/aea-gateway-forward.service <<UNIT
[Unit]
Description=Forward gateway traffic between receptor hosts ($mode)
Wants=network-online.target
After=network-online.target
[Service]
DynamicUser=yes
ExecStart=/usr/bin/socat $listen $target
Restart=always
RestartSec=2
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable aea-gateway-forward.service
systemctl restart aea-gateway-forward.service

# Prove it: /status answers through the forwarder.
for _ in $(seq 20); do
  if curl -fsS -m 5 -o /dev/null "$check_url"; then echo "FORWARD_OK $mode $check_url"; exit 0; fi
  sleep 1
done
echo "FORWARD_FAILED: $check_url does not answer" >&2
exit 1
