package com.earthquakes.relay;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class EventClassifierTest {
    @Test
    public void labelsOnlyKnownEvidenceSources() {
        assertEquals("GMS_CANDIDATE", EventClassifier.sourceFor("com.google.android.gms"));
        assertEquals("SYNTHETIC_FIXTURE", EventClassifier.sourceFor("com.earthquakes.fixture"));
        assertTrue(EventClassifier.shouldCapture("com.google.android.gms"));
        assertFalse(EventClassifier.shouldCapture("com.example.unrelated"));
    }
}
