#!/usr/bin/env bash
# Puts Caddy on :80 in front of the gateway, as CloudFront's origin. Idempotent. Does not
# restart the gateway or touch an emulator.
#
#   sudo infra/https/install.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ORIGIN_ENV=/etc/caddy/origin.env
[[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }
# Put there by infra/https/deploy.sh secret. An empty value would make the header check
# match any request, so a short or missing one stops here.
origin_secret=$(sed -n 's/^AEA_ORIGIN_SECRET=//p' "$ORIGIN_ENV" 2>/dev/null || true)
((${#origin_secret} >= 32)) || { echo "HTTPS_INSTALL_FAILED: no origin secret in $ORIGIN_ENV (run deploy.sh secret)" >&2; exit 1; }

dpkg -s caddy >/dev/null 2>&1 || apt-get install -y -q caddy
install -m 644 "$HERE/Caddyfile" /etc/caddy/Caddyfile
install -d /etc/systemd/system/caddy.service.d
printf '[Service]\nEnvironmentFile=%s\n' "$ORIGIN_ENV" > /etc/systemd/system/caddy.service.d/origin.conf
systemctl daemon-reload
AEA_ORIGIN_SECRET=$origin_secret caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
systemctl enable caddy
systemctl restart caddy  # admin is off, so no reload

# Prove the allowlist, locally: public paths reach the gateway, internal ones never do.
sleep 2
# The secret goes to curl on stdin (-H @-), never on a command line other users can read.
code() { printf 'X-Origin-Verify: %s\n' "$origin_secret" | curl -s -o /dev/null -w '%{http_code}' -H @- -X "$1" "http://127.0.0.1$2"; }
[[ $(code GET /status) == 200 ]] || { echo "HTTPS_INSTALL_FAILED: /status not proxied" >&2; exit 1; }
[[ $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1/status) == 403 ]] \
  || { echo "HTTPS_INSTALL_FAILED: request without the origin header was not rejected" >&2; exit 1; }
[[ $(curl -s -o /dev/null -w '%{http_code}' -H 'X-Origin-Verify: wrong' http://127.0.0.1/status) == 403 ]] \
  || { echo "HTTPS_INSTALL_FAILED: wrong origin header was not rejected" >&2; exit 1; }
for internal in "POST /events" "POST /heartbeat" "POST /probe" "GET /evidence"; do
  [[ $(code $internal) == 404 ]] || { echo "HTTPS_INSTALL_FAILED: $internal is reachable" >&2; exit 1; }
done
echo "HTTPS_INSTALL_OK"
