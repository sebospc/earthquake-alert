# Earthquake relay lab

Android emulators ("receptores") with a fixed simulated location receive Google's real
Android Earthquake Alerts (AEA). A listener app forwards each alert to a Node gateway, which
pushes it to iPhones subscribed to that receptor (APNs for the future native app, Web Push
for the PWA). Validated with a real quake on 2026-09-24: AWS receptor, no Google account,
alert at +18.1 s, ~0.8 s added by us (see `docs/qa/load.md`).

## Read in this order, and stop when you have enough

1. `docs/STATUS.md`: current state, what is running, open items. Always first.
2. `docs/roles/<your-name>.md`: if your session name is developer, developer-qa,
   developer-ios, devops-earthquake or investigator. It says what you own and your rules.
3. Only what the task needs:

| topic | file |
|---|---|
| why things are the way they are (decisions) | `docs/decision.md` |
| what was measured and proven | `docs/findings.md` |
| API the iOS app uses | `docs/ios-contract.md` |
| QA findings: read only the "current state" part at the top | `docs/qa/review.md` |
| load test numbers | `docs/qa/load.md` |
| certifier | `monitor/README.md` |
| pilot receptor sites | `docs/siting-pilot.md` |
| emails drafted, dropped by the user (never sent, not to be sent) | `docs/outreach/` |

## Token rules

- Never read a whole doc to find one thing. `grep -n` first, then read that range.
- Do not re-derive what `docs/STATUS.md` or `docs/findings.md` already says.
- Keep command output small: `tail`, `grep`, `head`. No full logs, no full dumpsys.
- A finished piece of work updates `docs/STATUS.md` (a few lines), not a new report file.

## Hard rules

- Do not touch the live Mac fleet (emulator-5554..5560, `~/Library/Application Support/aea-lab/`)
  or the AWS EC2 unless your role says so. The coordinator approves every deploy; devops-earthquake runs the pipeline.
- Nothing leaves the machine (email, Slack, GitHub, posts) without the user's approval.
- Git repo, remote `origin` = github.com/sebospc/earthquake-alert (PUBLIC: anything committed is published). Only the coordinator commits; never push without the user's approval. Secrets and live config stay out: see `.gitignore`.
- Code style and writing style: `~/.claude/CLAUDE.md`.
- Life-safety system: a silent failure is worse than a loud one. Every change keeps a test.
