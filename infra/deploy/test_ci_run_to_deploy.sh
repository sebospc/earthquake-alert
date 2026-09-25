#!/usr/bin/env bash
# Offline check of ci-run-to-deploy.sh with a fake gh: the hotfix dispatch deploys only the tip
# of main with every job but ios-core green; workflow_run passes its own run through.
#
#   bash infra/deploy/test_ci_run_to_deploy.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'GH'
#!/usr/bin/env bash
case "$2" in
  */jobs) printf '%b\n' "$FAKE_JOBS" ;;
  */commits/main) echo "${FAKE_TIP:-abc}" ;;
  *) echo "{\"name\":\"ci\",\"event\":\"${FAKE_EVENT:-push}\",\"head_branch\":\"main\",\"head_sha\":\"abc\"}" ;;
esac
GH
chmod +x "$WORK/bin/gh"

resolve() {
  : > "$WORK/out"
  PATH="$WORK/bin:$PATH" GITHUB_OUTPUT="$WORK/out" GITHUB_REPOSITORY=x/y GITHUB_EVENT_NAME=${EVENT:-workflow_dispatch} \
    DISPATCH_RUN_ID=${ID:-5} bash "$HERE/ci-run-to-deploy.sh" >/dev/null 2>"$WORK/err"
}
deploys() { resolve || fail "$1 refused: $(cat "$WORK/err")"; [[ $(cat "$WORK/out") == $'run_id=5\nsha=abc' ]] || fail "$1 output: $(cat "$WORK/out")"; echo "PASS $1"; }
refuses() { ! resolve || fail "$1 deployed"; grep -q "$2" "$WORK/err" || fail "$1 wrong reason: $(cat "$WORK/err")"; echo "PASS $1 refused"; }

FAKE_JOBS='gateway success\nandroid success\nios-core failure' deploys "ios-core red"
FAKE_JOBS='gateway success\nandroid success' deploys "ios-core missing"
FAKE_JOBS='gateway failure\nandroid success\nios-core success' refuses "gateway red" "gateway failure"
FAKE_JOBS='android success\nios-core failure' refuses "gateway missing" "gateway missing"
FAKE_JOBS='lint-gateway success\nandroid success' refuses "only a job named like gateway" "gateway missing"
FAKE_JOBS='gateway success\nandroid null\nios-core failure' refuses "android still running" "android null"
FAKE_EVENT=pull_request FAKE_JOBS='gateway success' refuses "a PR run" "not a ci run of a push to main"
ID='5;x' FAKE_JOBS='gateway success' refuses "a non-numeric id" "must be a number"
FAKE_TIP=def FAKE_JOBS='gateway success\nandroid success' refuses "an older run than the tip of main" "not the tip of main"

: > "$WORK/out"
GITHUB_OUTPUT="$WORK/out" GITHUB_EVENT_NAME=workflow_run EVENT_RUN_ID=7 EVENT_SHA=fed bash "$HERE/ci-run-to-deploy.sh"
[[ $(cat "$WORK/out") == $'run_id=7\nsha=fed' ]] || fail "workflow_run output: $(cat "$WORK/out")"
echo "PASS workflow_run passes its own run through"
