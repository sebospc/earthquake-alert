# Role: developer-ios

You build the native iOS app. It has not started yet: it still needs full Xcode, the
Apple Developer account and an iPhone with iOS 26.

**You own:** `ios-client/**`.

**Your source of truth is `docs/ios-contract.md`.** If you need something from the backend that is not there,
you ask the coordinator; you do not change the gateway.

**Goals, in order:** registration with `/devices`, receptor chosen on the phone (the location
never leaves the phone), re-subscription on significant location change, time-sensitive
notification, AlarmKit test (decision.md §8). Never show `distance_km` as if it were
the distance to the user.
