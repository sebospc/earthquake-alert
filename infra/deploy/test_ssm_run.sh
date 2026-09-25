#!/usr/bin/env bash
# Offline check of ssm-run.sh end to end: a fake aws uploads to a temp dir, presigns file://
# URLs, and runs the command list the way AWS-RunShellScript does, with /bin/sh. On the CI
# runner that is dash, the shell that rejected `set -o pipefail` on the host (25-sep).
#
#   bash infra/deploy/test_ssm_run.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
RUN_SHELL=$(command -v dash || echo /bin/sh)

mkdir -p "$WORK/bin" "$WORK/dist" "$WORK/s3" "$WORK/tools"
cat > "$WORK/bin/aws" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "s3 cp") cp "\$4" "$WORK/s3/\$(basename "\$5")"; [[ -z \${TAMPER:-} ]] || echo junk >> "$WORK/s3/\$(basename "\$5")" ;;
  "s3 presign") echo "file://$WORK/s3/\$(basename "\$3")" ;;
  "ssm send-command")
    while [[ \$1 != --parameters ]]; do shift; done
    jq -r '.commands[0]' <<<"\$2" > "$WORK/cmd.sh"
    # 60 s cap: a step stuck on stdin fails the test instead of hanging it.
    perl -e 'alarm 60; exec @ARGV' $RUN_SHELL "$WORK/cmd.sh" < "$WORK/stdin-that-never-ends" > "$WORK/out" 2> "$WORK/err"; echo \$? > "$WORK/rc"; echo cmd-1 ;;
  "ssm get-command-invocation")
    case "\$*" in
      *"--query Status"*) [[ \$(cat "$WORK/rc") == 0 ]] && echo Success || echo Failed ;;
      *StandardOutputContent*) cat "$WORK/out" ;;
      *StandardErrorContent*) cat "$WORK/err" ;;
    esac ;;
  *) echo "fake aws: unexpected \$*" >&2; exit 9 ;;
esac
EOF
# Reads stdin like adb shell does: a script fed to bash on stdin would be swallowed here.
printf '#!/bin/sh\necho "$@" >> "%s/systemctl.log"\ncat >/dev/null\n' "$WORK" > "$WORK/bin/systemctl"
printf '#!/bin/sh\nexit 0\n' > "$WORK/bin/sleep"
chmod +x "$WORK/bin/"*

# The same tools bundle CI builds.
tools="scripts/lab.py scripts/sensor-health.py scripts/aea-geofix.py infra/cloudwatch/aea-cw-probe.py infra/deploy/remote.sh"
(cd "$ROOT" && tar -czf "$WORK/dist/tools.tar.gz" $tools && sha256sum $tools > "$WORK/dist/tools.manifest")
(cd "$WORK/dist" && sha256sum tools.tar.gz > SHA256SUMS)

# Like an agent that leaves stdin open: a FIFO nobody closes. A step reading stdin would hang
# on it unless the script gives bash </dev/null.
mkfifo "$WORK/stdin-that-never-ends"
sleep_bin=$(command -v sleep)
"$sleep_bin" 600 > "$WORK/stdin-that-never-ends" 2>/dev/null </dev/null & keeper=$!
trap 'kill $keeper 2>/dev/null; rm -rf "$WORK"' EXIT

export PATH="$WORK/bin:$PATH" TOOLS_DIR="$WORK/tools"
output=$(bash "$HERE/ssm-run.sh" i-test bucket abc123 "$WORK/dist" "tools BUNDLE" "tools BUNDLE" 2>&1) \
  || fail "tools deploy through $RUN_SHELL failed: $output"
[[ $(grep -c "^DEPLOY_OK tools" <<<"$output") == 2 ]] || fail "a step reading stdin swallowed the next one: $output"
cmp -s "$ROOT/scripts/sensor-health.py" "$WORK/tools/sensor-health.py" || fail "tools did not land"
if command -v dash >/dev/null; then dash -n "$WORK/cmd.sh" || fail "the command list is not valid sh"; fi
echo "PASS the SSM command list runs under $RUN_SHELL, both steps run past a stdin reader, the tools land"

output=$(TAMPER=1 bash "$HERE/ssm-run.sh" i-test bucket abc123 "$WORK/dist" "tools BUNDLE" 2>&1) \
  && fail "a bundle altered in S3 deployed"
grep -q "stderr on the host" <<<"$output" && grep -q "FAILED" <<<"$output" \
  || fail "the host's stderr must be in the job log: $output"
echo "PASS a bundle altered in S3 fails, and the host's stderr is in the log"
