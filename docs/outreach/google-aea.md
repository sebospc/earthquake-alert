# Draft: Google, Android Earthquake Alerts team

Status: DRAFT. Do not send without approval.

## Recipient and channel (verified 24-sep-2026)

I did not find a public channel for the AEA team. What exists:

| channel | what it is for | fits |
|---|---|---|
| Richard Allen, `rallen@berkeley.edu` | Director of the Berkeley Seismology Lab and **Research Scientist at Google**, first author of the AEA paper in Science (2025). He is the most direct door to the team. | yes, see variant B |
| [Public Alerts form](https://support.google.com/publicalerts/contact/publicalerts_interest) | for agencies that publish official alerts in CAP | no, we are not issuers. Use only if Allen does not answer, and say so in the first line |
| [GMS form](https://www.android.com/gms/contact/) | GMS licenses for manufacturers | only for question (b) |
| [crisisresilience.google/partnerships](https://crisisresilience.google/partnerships) | has no form and does not mention earthquakes | no |

Recommendation: send variant B to Allen first and ask him to forward it to the team. Variant A stays ready for when he gives a name.

Sources: [Berkeley profile](https://vcresearch.berkeley.edu/faculty/richard-allen), [personal page](https://seismo.berkeley.edu/~rallen/), [paper](https://www.science.org/doi/10.1126/science.ads4779), [Public Alerts FAQ](https://support.google.com/publicalerts/faq/2696427?hl=en), [GMS](https://www.android.com/gms/).

---

## Variant A: to the AEA team

**Subject:** Android Earthquake Alerts in Colombia: lab measurements and four questions

Hello,

I run a small private lab in Medellín that measures how Android Earthquake Alerts reach users in Colombia. I would like to share what we saw and ask four questions. A no is also a useful answer.

What we measured:

- On 23 Sep 2026, 15:09 local time, an M4.5 near Chaparral, Tolima. An Android emulator (API 35, Google Play image) with its location set to Chaparral got the `eew_alert_v2` notification 17.6 s after origin. Three other emulators outside the BeAware radius got nothing, which is our control.
- On 24 Sep 2026, 01:19 UTC, a second event, M4.46 by your estimate, about 19 km away. We only got the `eew_update` ("You may have felt shaking"), 5 min 21 s later, with no alert before it.
- None of these events appear in USGS. Only the SGC catalog has them.

The point I care about: iPhones in Colombia have no native earthquake alerts, so a large part of the population gets nothing. I am looking for a legitimate way to help close that gap, and I would not build anything on AEA without your permission.

The questions:

1. Is there a partner program to redistribute AEA alerts to other channels, similar to how ShakeAlert works with Android in the US?
2. Does Google grant a GMS license for virtual devices, or is that never possible?
3. Are there plans for alerts on iOS, or for another channel in Colombia?
4. Who should I contact about a research collaboration with this data?

I can share the raw captures and the method. The lab is private and not open to anyone else.

Thank you,
Sebastián Cabarcas
Medellín, Colombia
[phone]

---

## Variant B: Richard Allen

**Subject:** AEA in Colombia: 17.6 s alert on a location-mocked emulator, with a control

Dear Professor Allen,

I read your 2025 Science paper on Android Earthquake Alerts and used the Zenodo dataset to plan a small private lab in Colombia. I have a result I think you will find interesting, and a question about who to talk to at Google.

On 23 Sep 2026 an M4.5 hit near Chaparral, Tolima. One Android emulator with its location set to Chaparral received the BeAware alert 17.6 s after origin. Three other emulators, 478 km away or more, received nothing. The only thing that put the first one inside the radius was an injected coordinate. So delivery follows the reported location, and an emulator is accepted as a receiver. It does not take part in detection: in 18 hours of sensor logs, `earthquake_alerting` never registered the accelerometer.

Two more things matched or extended your data:

- The radius behaves like a lookup table. Interpolating your magnitude to radius values predicts the Colombian cases with a median error of 0.4 km.
- A second event on 24 Sep, M4.46, produced only the `eew_update`, 5 min 21 s late, with no alert first. I would like to understand if that is expected near the threshold.

Why I care: iPhones in Colombia have no native earthquake alerts, and Congress is discussing a national system (SNAST). I want to find a legitimate way to use what AEA already does for people who are not on Android. I am not going to build anything on it without Google's permission.

Could you point me to the right person on the AEA team for a research conversation? I can send the raw captures and method.

Best regards,
Sebastián Cabarcas
Medellín, Colombia
[phone]

---

## Notes to review before sending

- Both variants say we use a simulated location on emulators. It is the finding, and hiding it would be worse, but Google may read it as use outside the terms (see `decision.md` §5). Decide whether to send it anyway.
- Question 2 (GMS for virtual devices) is almost surely a no. It is useful to have it in writing.
- Before sending, move the emulators to a dedicated Google account (pending in `decision.md`).
