#!/usr/bin/env bash
# The real Caddyfile against a fake gateway, on test ports. Proves the origin secret, the
# allowlist, the X-Forwarded-For pass-through, the empty-secret lockout and the log filter.
#
#   CADDY=/path/to/caddy bash infra/https/test_caddy.sh     (default: caddy on PATH)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CADDY=${CADDY:-caddy}
WORK="$(mktemp -d)"
CADDY_PORT=$((19000 + RANDOM % 500))
GATEWAY_PORT=$((19600 + RANDOM % 300))
SECRET=$(printf 'a%.0s' {1..64})
pids=()
cleanup() { kill "${pids[@]}" 2>/dev/null || true; rm -rf "$WORK"; }
trap cleanup EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

sed "s/^:80 {/:$CADDY_PORT {/; s/127.0.0.1:8787/127.0.0.1:$GATEWAY_PORT/g" "$HERE/Caddyfile" > "$WORK/Caddyfile"

# Fake gateway: 200, and records the headers it received.
cat > "$WORK/gateway.py" <<'EOF'
import http.server, json, sys
class Handler(http.server.BaseHTTPRequestHandler):
    def answer(self):
        with open(sys.argv[2], "a") as seen:
            seen.write(json.dumps(dict(self.headers)) + "\n")
        self.send_response(200); self.end_headers(); self.wfile.write(b"gateway")
    do_GET = do_POST = do_DELETE = do_HEAD = answer
    def log_message(self, *args): pass
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
EOF

start_gateway() { python3 "$WORK/gateway.py" "$GATEWAY_PORT" "$WORK/seen.jsonl" & pids+=($!); }
start_caddy() {  # start_caddy <secret>
  AEA_ORIGIN_SECRET=$1 "$CADDY" run --config "$WORK/Caddyfile" --adapter caddyfile > "$WORK/caddy.log" 2>&1 &
  pids+=($!)
  for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:$CADDY_PORT/" && return; sleep 0.1; done
  fail "caddy did not start: $(tail -3 "$WORK/caddy.log")"
}
code() {  # code <method> <path> [header]
  curl -s -o /dev/null -w '%{http_code}' -X "$1" ${3:+-H "$3"} "http://127.0.0.1:$CADDY_PORT$2"
}

start_gateway
start_caddy "$SECRET"
sleep 0.3
ours="X-Origin-Verify: $SECRET"
[[ $(code GET /status "$ours") == 200 ]] || fail "our header must pass"
[[ $(code GET /status) == 403 ]] || fail "no header must be 403"
[[ $(code GET /status "X-Origin-Verify: wrong") == 403 ]] || fail "wrong header must be 403"
echo "PASS origin secret: ours 200, none 403, wrong 403"

for allowed in "GET /" "GET /health" "GET /sw.js" "GET /sensors.json" "GET /manifest.webmanifest" "POST /subscribe" "POST /devices" "DELETE /devices"; do
  set -- $allowed
  [[ $(code "$1" "$2" "$ours") == 200 ]] || fail "$allowed must reach the gateway"
done
for internal in "POST /events" "POST /heartbeat" "POST /probe" "GET /evidence" "GET /anything" "POST /status"; do
  set -- $internal
  [[ $(code "$1" "$2" "$ours") == 404 ]] || fail "$internal must be 404"
done
echo "PASS allowlist: phone paths through, internal paths 404"

: > "$WORK/seen.jsonl"
curl -s -o /dev/null -H "$ours" -H "X-Forwarded-For: 6.6.6.6, 203.0.113.9" "http://127.0.0.1:$CADDY_PORT/status"
python3 - "$WORK/seen.jsonl" <<'EOF' || fail "headers seen by the gateway are wrong"
import json, sys
headers = {k.lower(): v for k, v in json.loads(open(sys.argv[1]).readline()).items()}
assert "x-origin-verify" not in headers, "the secret reached the gateway"
assert headers["x-forwarded-for"].split(",")[-1].strip() == "203.0.113.9", headers["x-forwarded-for"]
EOF
echo "PASS gateway sees CloudFront's last X-Forwarded-For entry and never the secret"

kill "${pids[0]}"; wait "${pids[0]}" 2>/dev/null || true  # gateway down: Caddy logs a 502
[[ $(code GET /status "$ours") == 502 ]] || fail "expected 502 with the gateway down"
sleep 0.3
! grep -q "$SECRET" "$WORK/caddy.log" || fail "the secret is in Caddy's log"
grep -q "502\|dial tcp" "$WORK/caddy.log" || fail "no error log line to check (filter test is empty)"
echo "PASS the secret never reaches Caddy's log, even on a 502"

kill "${pids[1]}"; wait "${pids[1]}" 2>/dev/null || true
if AEA_ORIGIN_SECRET= "$CADDY" validate --config "$WORK/Caddyfile" --adapter caddyfile >/dev/null 2>&1; then
  fail "Caddy accepts the config without the secret: it would only check that the header exists"
fi
echo "PASS without the secret Caddy refuses to start (fails closed)"
