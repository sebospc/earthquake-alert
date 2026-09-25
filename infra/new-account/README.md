# Moving to a new AWS account

When the credits run out, the whole service moves to a fresh account. Two scripts do the
work; this page lists what only a person can do, and what changes for users.

## Before: on the old account

1. `infra/new-account/backup.sh <old host ip>` asks for a passphrase and writes one encrypted
   file to `~/aea-backups/`. It holds the master HMAC secret, the VAPID keys, the sensor map,
   the subscriptions, the device tokens and the CloudFront origin secret. Keep the file and the
   passphrase apart (e.g. the file on a disk, the passphrase in a password manager). Never put
   the file in the repo; the script refuses to.
2. Take the backup as late as possible: every subscription made after it is lost.

## Human-only steps in the new account

1. Create the account and log in as root once.
2. Move it to the paid plan. The free plan does not allow r8i instances (the receptor host
   needs nested virtualization).
3. Create an admin IAM user (or an SSO admin role) with access keys for this machine, and add
   it as a profile: `aws configure --profile new-admin`. Region `sa-east-1`.
4. `gh auth status` must show a login with admin rights on `sebospc/earthquake-alert`: the
   script sets the repo variables.

## Run

```
AWS_PROFILE=new-admin ALERT_EMAIL=<alarm email> \
  infra/new-account/rebuild.sh ~/aea-backups/aea-backup-<utc>.tar.gz.enc
```

It asks for the backup passphrase. It takes about 40 minutes (the emulators boot one at a time).
If a step fails, fix the cause and run the same command again: every step checks before it
creates, and the backup is restored only once.

What it does, in order: spot service-linked role; the deploy stack (GitHub OIDC, deploy role,
artifact bucket, receptor instance profile); key pair and security group; the spot host; the
HTTPS stack (Elastic IP first, so the address stops moving); the reviewed `main` onto the host;
the backup restore; the bootstrap with one emulator per line of the backup's sensor map; the
listener APK from the last green CI run; CloudWatch and its alarms; Caddy; the GitHub variables;
then it checks every receptor is covered, runs `infra/https/verify.sh` and reads the alarms.

## After the run

1. Confirm the SNS subscription email, or no alarm reaches anyone.
2. Approve one pipeline deploy in GitHub: it proves OIDC and SSM work in the new account.
3. Point the certifier at the new host: `MONITOR_INSTANCE=<new id>`, `MONITOR_SSH_KEY=<new pem>`,
   and AWS credentials that can read `ec2:DescribeInstances` in the new account. Tell developer-qa.
4. Stop the old gateway as soon as the new one verifies: both hold the same subscriptions and
   VAPID keys, so while both run every user gets every alert twice. On the old host:
   `sudo systemctl disable --now gateway-watchdog.timer earthquake-gateway`. Not
   `RELAY_KILL_SWITCH=1`: that pushes "uncovered" to every user at once.
5. Update `docs/STATUS.md`: instance id, Elastic IP, the new URL.
6. Only then delete the old account's stacks and instance.

## What changes for users

- **Receptors:** nothing. The master secret moves with the backup, so the per-sensor keys and
  every `relay.json` stay valid.
- **Web push already subscribed (the PWA, testing only):** keeps working. The VAPID keys move
  with the backup, and the push endpoints do not depend on our URL. The PWA page itself is at the
  old CloudFront URL and dies with the old account.
- **The iPhone app breaks.** The app is what real users run, and the gateway URL is built into
  it. The CloudFront URL (`https://dxxxx.cloudfront.net`) belongs to the old account and dies
  with it. Without a domain of our own, an account move needs an App Store update (days of
  review), and every installed app talks to a dead URL until users update.
- **The fix is a real domain, bought before the app ships to real users.** Point it at the
  current CloudFront distribution and build only that address into the app. Then an account
  move is one DNS change and users see nothing.
