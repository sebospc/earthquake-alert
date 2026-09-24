package com.earthquakes.relay;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class RelayPolicyTest {
    private static final String GMS = "com.google.android.gms";
    private static final String SIGNER = RelayPolicy.PLAY_SERVICES_SIGNER;

    @Test
    public void relaysOnlySignedEarlyWarnings() {
        assertTrue(RelayPolicy.isRelayable(GMS, SIGNER, "eew_alert_v2"));
        // The late "you may have felt shaking" notice must never become "take cover".
        assertFalse(RelayPolicy.isRelayable(GMS, SIGNER, "eew_update"));
        assertFalse(RelayPolicy.isRelayable(GMS, SIGNER, "finder-configuration"));
        assertFalse(RelayPolicy.isRelayable(GMS, "00", "eew_alert_v2"));
        assertFalse(RelayPolicy.isRelayable(GMS, "UNAVAILABLE:X", "eew_alert_v2"));
        assertFalse(RelayPolicy.isRelayable("com.earthquakes.fixture", SIGNER, "eew_alert_v2"));
        assertFalse(RelayPolicy.isRelayable(GMS, SIGNER, null));
    }

    @Test
    public void usesOwnWordsFromTheStructuredExtras() {
        assertEquals("Sismo M4.5 cerca de tu zona. Protéjase ahora.", RelayPolicy.bodyFor(4.45852f));
        assertEquals("Posible sismo cerca de tu zona. Protéjase ahora.", RelayPolicy.bodyFor(null));
        // The distance is from the receptor, never from the phone: it must not reach the text.
        assertFalse(RelayPolicy.bodyFor(4.48f).contains("km"));
    }

    @Test
    public void keysOnQuakeOriginNotOnNotificationTag() {
        // The two real Chaparral quakes, 5 h apart, shared one tag but not one origin.
        String first = RelayPolicy.eventId("chaparral", 1790194179L, 0);
        String second = RelayPolicy.eventId("chaparral", 1790212783L, 0);
        assertNotEquals(first, second);
        assertEquals(first, RelayPolicy.eventId("chaparral", 1790194179L, 999));
        assertNotEquals(first, RelayPolicy.eventId("quibdo", 1790194179L, 0));
    }

    @Test
    public void replaysOnlyWarningsStillInsideTheirTtl() {
        long now = 1_790_230_000_000L;
        assertTrue(RelayPolicy.isReplayable(now, now));
        assertTrue(RelayPolicy.isReplayable(now - RelayPolicy.ALERT_TTL_MS + 1, now));
        assertFalse(RelayPolicy.isReplayable(now - RelayPolicy.ALERT_TTL_MS, now));
        // An NTP step back leaves a fresh warning a little in the future; a real jump does not.
        assertTrue(RelayPolicy.isReplayable(now + RelayPolicy.CLOCK_STEP_TOLERANCE_MS, now));
        assertFalse(RelayPolicy.isReplayable(now + RelayPolicy.CLOCK_STEP_TOLERANCE_MS + 1, now));
    }

    @Test
    public void dropsNonFiniteNumbersInsteadOfCrashing() {
        // Both kinds of non-finite on both overloads: checking only NaN or only infinity passes half.
        assertNull(RelayPolicy.finiteOrNull(Float.NaN));
        assertNull(RelayPolicy.finiteOrNull(Float.NEGATIVE_INFINITY));
        assertNull(RelayPolicy.finiteOrNull(Double.NaN));
        assertNull(RelayPolicy.finiteOrNull(Double.POSITIVE_INFINITY));
        assertNull(RelayPolicy.finiteOrNull((Float) null));
        assertNull(RelayPolicy.finiteOrNull((Double) null));
        assertEquals(Float.valueOf(4.5f), RelayPolicy.finiteOrNull(4.5f));
        assertEquals(Double.valueOf(18.9089), RelayPolicy.finiteOrNull(18.9089));
    }

    @Test
    public void heartbeatSitsNextToEventsEvenBehindAPrefix() throws Exception {
        assertEquals("http://10.0.2.2:8787/heartbeat",
                RelayPolicy.heartbeatUrl("http://10.0.2.2:8787/events").toString());
        assertEquals("https://relay.example/api/heartbeat",
                RelayPolicy.heartbeatUrl("https://relay.example/api/events").toString());
    }
}
