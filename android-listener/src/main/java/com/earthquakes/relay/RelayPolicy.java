package com.earthquakes.relay;

import java.net.MalformedURLException;
import java.net.URL;
import java.util.Locale;

/** What gets relayed to iPhones, and with which words. Pure so it can be tested off-device. */
final class RelayPolicy {
    static final String PLAY_SERVICES_SIGNER =
            "5f2391277b1dbd489000467e4c2fa6af802430080457dce2f618992e9dfb5402";
    /** A warning is only useful while the S wave is still travelling: ~86 s reach 300 km. */
    static final long ALERT_TTL_MS = 3 * 60_000;
    /** Three missed beats fit inside the 15 min the phone waits before showing red. */
    static final long HEARTBEAT_INTERVAL_MS = 5 * 60_000;

    private RelayPolicy() {}

    /**
     * Only the early warning is relayed. A channel Google renames to some other eew_* is
     * NOT relayed on purpose: guessing it is a warning risks a false one. lab.py flags it
     * for review instead, so a human decides.
     * eew_update arrives minutes after the shaking
     * (5 min 21 s on 24-sep); sending it as "take cover" would be wrong advice.
     */
    static boolean isRelayable(String packageName, String signerSha256, String channelId) {
        return EventClassifier.GOOGLE_PLAY_SERVICES.equals(packageName)
                && PLAY_SERVICES_SIGNER.equals(signerSha256)
                && channelId != null
                && channelId.startsWith("eew_alert");
    }

    /**
     * Own wording, never Google's text or brand: facts only. No distance: the one AEA gives
     * is from this receptor to the quake, and a phone reading "a ~16 km" takes it as its own
     * (seen in the 24-sep Chaparral alert). distance_km still travels as its own field.
     */
    static String bodyFor(Float magnitude) {
        if (magnitude == null) return "Posible sismo cerca de su zona. Protéjase ahora.";
        return String.format(Locale.ROOT, "Sismo M%.1f cerca de su zona. Protéjase ahora.", magnitude);
    }

    /**
     * The same quake seen twice by one sensor must collapse, and two quakes must not.
     * The notification tag is reused across quakes (seen 23/24-sep), so it cannot be the key.
     */
    static String eventId(String sensorId, Long timeOccurredS, long postTimeMs) {
        String origin = timeOccurredS != null ? "t" + timeOccurredS : "p" + postTimeMs;
        return sensorId + ":" + origin + ":alert";
    }

    /** NTP stepping the clock back can put a fresh warning's post time slightly ahead of now. */
    static final long CLOCK_STEP_TOLERANCE_MS = 30_000;

    /**
     * A warning found on screen at reconnect is still worth sending while inside the TTL.
     * A post time further in the future than an NTP step means a clock jump, and nothing
     * about its age can be trusted.
     */
    static boolean isReplayable(long postTimeMs, long nowMs) {
        long ageMs = nowMs - postTimeMs;
        return ageMs >= -CLOCK_STEP_TOLERANCE_MS && ageMs < ALERT_TTL_MS;
    }

    static Float finiteOrNull(Float value) {
        return value != null && Float.isFinite(value) ? value : null;
    }

    static Double finiteOrNull(Double value) {
        return value != null && Double.isFinite(value) ? value : null;
    }

    /** Sibling of the events URL, so a gateway behind a path prefix keeps working. */
    static URL heartbeatUrl(String eventsUrl) throws MalformedURLException {
        return new URL(new URL(eventsUrl), "heartbeat");
    }
}
