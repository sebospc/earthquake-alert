package com.earthquakes.relay;

final class EventClassifier {
    static final String GOOGLE_PLAY_SERVICES = "com.google.android.gms";
    static final String FIXTURE = "com.earthquakes.fixture";

    private EventClassifier() {}

    static String sourceFor(String packageName) {
        if (FIXTURE.equals(packageName)) return "SYNTHETIC_FIXTURE";
        if (GOOGLE_PLAY_SERVICES.equals(packageName)) return "GMS_CANDIDATE";
        return "IGNORED";
    }

    static boolean shouldCapture(String packageName) {
        return !sourceFor(packageName).equals("IGNORED");
    }
}
