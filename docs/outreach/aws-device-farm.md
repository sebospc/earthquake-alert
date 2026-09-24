# Draft: AWS Device Farm, private devices

Status: DRAFT. Do not send without approval.

## Recipient and channel (verified 24-sep-2026)

`aws-devicefarm-support@amazon.com`. It is the contact that the AWS documentation gives to request a private device fleet.

What the documentation already says, so we do not ask it:

- Private devices only exist in **us-west-2 (Oregon)**.
- Rooted Android devices can be requested.
- There is an agreed initial term and cancelling requires 30 days' notice.
- Public price: none. Third parties mention about USD 200 per device per month, not confirmed.

Sources: [private devices](https://docs.aws.amazon.com/devicefarm/latest/developerguide/working-with-private-devices.html), [terminating](https://docs.aws.amazon.com/devicefarm/latest/developerguide/terminate-private-device.html), [pricing](https://aws.amazon.com/device-farm/pricing/).

---

**Subject:** Private devices: pricing and continuous 24/7 use

Hello,

I am looking at Device Farm private devices for a long-running research setup and need a few answers before I decide.

The use case: a small number of Android phones (maybe 2 to 5 to start) running all the time, each with our own app that listens to system notifications and forwards some of them to our server. No automated test runs. The phones would stay logged into a Google account with Play Services up to date.

My questions:

1. What is the monthly price per private device, and what is the minimum term?
2. Is continuous 24/7 use allowed, with our app running in the background all the time? Or is the device meant only for test runs and remote sessions?
3. Are there limits on session length, or automatic resets or reboots between sessions that would remove our app or its state?
4. Private devices are only in us-west-2 today. Is any other region planned, especially São Paulo?
5. Can we set the GPS location of the device to a fixed point outside the US and keep it there? If yes, how, and does it survive reboots?
6. Can the device keep a Google account signed in and update Play Services on its own?

Thanks,
Sebastián Cabarcas
[phone]

---

## Notes to review before sending

- With Oregon as the only region, the devices have a US IP and a location in Colombia. It is the same open question as Hetzner (`decision.md` §3): we do not know if Google cross-checks IP with location.
- A physical phone avoids the Android SDK license problem, but not the one of forwarding AEA content or the one of the fake location. The email does not mention it, but it does not change the verdict of `decision.md`.
