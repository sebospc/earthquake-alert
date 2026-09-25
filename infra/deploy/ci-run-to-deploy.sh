#!/usr/bin/env bash
# Which ci run deploy.yml deploys, written as run_id= and sha= to $GITHUB_OUTPUT.
#   workflow_run: the run that triggered it (EVENT_RUN_ID, EVENT_SHA).
#   workflow_dispatch (hotfix, macOS runners down): DISPATCH_RUN_ID, only if it is a ci run of a
#   push to main, it is the tip of main, and every job but ios-core is green.
set -euo pipefail
refuse() { echo "REFUSED: $*" >&2; exit 1; }
if [[ $GITHUB_EVENT_NAME == workflow_run ]]; then
  echo "run_id=$EVENT_RUN_ID" >> "$GITHUB_OUTPUT"
  echo "sha=$EVENT_SHA" >> "$GITHUB_OUTPUT"
  exit 0
fi
[[ $DISPATCH_RUN_ID =~ ^[0-9]+$ ]] || refuse "ci_run_id must be a number"
run=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$DISPATCH_RUN_ID")
[[ $(jq -r '"\(.name) \(.event) \(.head_branch)"' <<<"$run") == "ci push main" ]] \
  || refuse "run $DISPATCH_RUN_ID is not a ci run of a push to main"
sha=$(jq -r .head_sha <<<"$run")
# An older or mistyped id would roll the live gateway back past later fixes (QA-99).
[[ $sha == "$(gh api "repos/$GITHUB_REPOSITORY/commits/main" --jq .sha)" ]] || refuse "run $DISPATCH_RUN_ID ($sha) is not the tip of main"
jobs=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$DISPATCH_RUN_ID/jobs" --jq '.jobs[] | "\(.name) \(.conclusion)"')
echo "$jobs"
# Only ios-core may be red or missing; every other job must be green.
not_green=$(grep -v '^ios-core ' <<<"$jobs" | grep -v ' success$' || true)
[[ -z $not_green && $'\n'$jobs$'\n' == *$'\n'"gateway success"$'\n'* ]] || refuse "not green: ${not_green:-gateway missing}"
echo "run_id=$DISPATCH_RUN_ID" >> "$GITHUB_OUTPUT"
echo "sha=$sha" >> "$GITHUB_OUTPUT"
