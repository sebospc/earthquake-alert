#!/usr/bin/env bash
# From anywhere, against the live CloudFront URL: the phone API reaches the gateway (its own
# 400 on a bad body proves the method and body made it through), internal paths never do.
#
#   infra/https/verify.sh https://dxxxx.cloudfront.net <elastic ip>
set -euo pipefail
base=${1:?usage: verify.sh https://<distribution>.cloudfront.net <elastic ip>}
elastic_ip=${2:?usage: verify.sh https://<distribution>.cloudfront.net <elastic ip>}
failures=0
expect() {  # expect <code> <method> <path> [body]
  local got
  got=$(curl -s -o /dev/null -w '%{http_code}' -X "$2" -H 'content-type: application/json' ${4:+--data "$4"} "$base$3")
  if [[ $got == "$1" ]]; then echo "ok   $2 $3 -> $got"; else echo "FAIL $2 $3 -> $got, want $1"; failures=$((failures + 1)); fi
}
expect 200 GET /status
expect 200 GET /
expect 200 GET /sw.js
expect 400 POST /subscribe '{}'
expect 400 POST /devices '{}'
expect 400 DELETE /devices '{}'
expect 404 POST /events '{}'
expect 404 POST /heartbeat '{}'
expect 404 POST /probe '{}'
expect 404 GET /evidence
[[ $(curl -s -o /dev/null -w '%{http_code}' "http://${base#https://}/status") == 301 ]] \
  && echo "ok   http redirects to https" || { echo "FAIL http does not redirect"; failures=$((failures + 1)); }
# Straight to the origin, without our header: the SG drops it (000) or Caddy answers 403.
# Anything else means the origin is open.
direct=$(curl -s -m 8 -o /dev/null -w '%{http_code}' "http://$elastic_ip/status" || true)
if [[ $direct == 000 || $direct == 403 ]]; then echo "ok   direct to origin -> $direct (rejected)"
else echo "FAIL direct to origin -> $direct, want 000 or 403"; failures=$((failures + 1)); fi
((failures == 0)) && echo "HTTPS_VERIFY_OK" || exit 1
