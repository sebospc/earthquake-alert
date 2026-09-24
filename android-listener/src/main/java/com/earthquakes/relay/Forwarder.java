package com.earthquakes.relay;

import android.content.Context;
import android.util.Log;

import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/**
 * Pushes an early warning to the gateway the moment it is posted. The lab watcher
 * polls every 5 minutes, which would turn any warning into a post-mortem.
 *
 * Config lives in files/relay.json, pushed per sensor with adb:
 * {"gateway_url": "...", "hmac_secret": "...", "sensor_id": "chaparral"}.
 * No config means lab mode: capture only, relay nothing.
 */
final class Forwarder {
    static final String CONFIG_FILE = "relay.json";
    private static final long[] RETRY_BACKOFF_MS = {0, 500, 1000, 2000, 4000};
    /** Runs the full relay path without waking anyone, so a broken path shows before a quake. */
    private static final long CANARY_INTERVAL_MS = 6 * 60 * 60_000;
    // ponytail: one sender thread. With the gateway down an alert holds it up to ~47 s and the
    // next one waits; a pool per alert if two alerts within a minute ever matter.
    private static final ExecutorService SENDER = Executors.newSingleThreadExecutor();
    // Own thread: an alert must never wait behind a heartbeat stuck on its timeouts.
    private static final ScheduledExecutorService MONITOR = Executors.newSingleThreadScheduledExecutor();
    private static ScheduledFuture<?> heartbeatTask;
    private static ScheduledFuture<?> canaryTask;
    private static volatile boolean invalidConfigReported;

    private Forwarder() {}

    static void relay(Context context, Float magnitude, Double distanceKm,
                      Long timeOccurredS, long postTimeMs) {
        JSONObject config = readConfig(context);
        if (config == null) return;
        String sensorId = config.optString("sensor_id");
        long capturedAt = System.currentTimeMillis();
        // NaN would make JSONObject.put throw on the main thread and lose the alert.
        Float finiteMagnitude = RelayPolicy.finiteOrNull(magnitude);
        Double finiteDistanceKm = RelayPolicy.finiteOrNull(distanceKm);

        JSONObject event = relayEvent(sensorId,
                RelayPolicy.eventId(sensorId, timeOccurredS, postTimeMs), capturedAt);
        CaptureService.put(event, "title", "Alerta de sismo");
        CaptureService.put(event, "body", RelayPolicy.bodyFor(finiteMagnitude));
        CaptureService.put(event, "interruption_level", "time-sensitive");
        CaptureService.put(event, "magnitude", finiteMagnitude);
        CaptureService.put(event, "distance_km", finiteDistanceKm);
        CaptureService.put(event, "time_occurred_s", timeOccurredS);
        // Origin fallback for the gateway when Play Services leaves out TIME_OCCURRED_EXTRA.
        CaptureService.put(event, "post_time_ms", postTimeMs);

        byte[] body = event.toString().getBytes(StandardCharsets.UTF_8);
        String url = config.optString("gateway_url");
        String secret = config.optString("hmac_secret");
        long deadline = capturedAt + RelayPolicy.ALERT_TTL_MS;

        SENDER.execute(() -> {
            // The gateway keeps a failed alert retryable, so retrying here is safe.
            for (long backoff : RETRY_BACKOFF_MS) {
                if (System.currentTimeMillis() + backoff > deadline) break;
                sleep(backoff);
                PostResult result = post(url, secret, body);
                JSONObject attempt = CaptureService.baseEvent(context, "RELAY_ATTEMPT");
                CaptureService.put(attempt, "event_id", event.optString("event_id"));
                CaptureService.put(attempt, "http_status", result.status());
                CaptureService.put(attempt, "request_written_at_ms", result.writtenAtMs());
                CaptureService.put(attempt, "error", result.error());
                EvidenceStore.append(context, attempt);
                if (result.isSuccess()) return;
                if (result.status() == 401) return;  // wrong secret: retrying cannot fix it
                // Anything else is retried, including 409: the gateway is still sending
                // the first attempt, which may yet fail.
            }
        });
    }

    private static JSONObject relayEvent(String sensorId, String eventId, long capturedAt) {
        JSONObject event = new JSONObject();
        CaptureService.put(event, "event_id", eventId);
        CaptureService.put(event, "source", "android_earthquake_alert_candidate");
        CaptureService.put(event, "sensor_id", sensorId);
        CaptureService.put(event, "captured_at", Instant.ofEpochMilli(capturedAt).toString());
        CaptureService.put(event, "expires_at",
                Instant.ofEpochMilli(capturedAt + RelayPolicy.ALERT_TTL_MS).toString());
        return event;
    }

    /**
     * Beats from the capture process itself, so a live emulator with a dead listener
     * still shows up as a gap on the phone. Same config, key and network as the relay.
     */
    static synchronized void startMonitoring(Context context) {
        stopMonitoring();
        invalidConfigReported = false;
        Context appContext = context.getApplicationContext();
        heartbeatTask = scheduleSafely(appContext, "HEARTBEAT_FAILED",
                () -> sendHeartbeat(appContext), RelayPolicy.HEARTBEAT_INTERVAL_MS);
        canaryTask = scheduleSafely(appContext, "RELAY_CANARY",
                () -> sendCanary(appContext), CANARY_INTERVAL_MS);
    }

    static synchronized void stopMonitoring() {
        if (heartbeatTask != null) heartbeatTask.cancel(false);
        if (canaryTask != null) canaryTask.cancel(false);
        heartbeatTask = null;
        canaryTask = null;
    }

    private interface Check {
        void run() throws Exception;
    }

    private static ScheduledFuture<?> scheduleSafely(Context context, String failureType,
                                                     Check check, long periodMs) {
        return MONITOR.scheduleAtFixedRate(() -> {
            // An exception escaping here would silently cancel every later run.
            try {
                check.run();
            } catch (Exception error) {
                recordStatus(context, failureType, PostResult.failed(error, null));
            }
        }, 0, periodMs, TimeUnit.MILLISECONDS);
    }

    /** A device with a valid relay.json relays; without one it is a lab capture device. */
    static boolean isRelaySensor(Context context) {
        return readConfig(context) != null;
    }

    private static void sendHeartbeat(Context context) throws Exception {
        // Read on every beat: relay.json is pushed after install, while the listener is already up.
        JSONObject config = readConfig(context);
        // Also the one place the GPS keeper follows relay.json, on connect and every 5 min.
        GpsKeeperService.sync(context, config != null);
        if (config == null) return;
        JSONObject heartbeat = new JSONObject();
        CaptureService.put(heartbeat, "sensor_id", config.optString("sensor_id"));
        CaptureService.put(heartbeat, "sent_at", Instant.now().toString());
        String url = RelayPolicy.heartbeatUrl(config.optString("gateway_url")).toString();
        PostResult result = post(url, config.optString("hmac_secret"),
                heartbeat.toString().getBytes(StandardCharsets.UTF_8));
        // Only failures are logged: a success every 5 min would bury the captures.
        if (!result.isSuccess()) recordStatus(context, "HEARTBEAT_FAILED", result);
    }

    private static void sendCanary(Context context) {
        JSONObject config = readConfig(context);
        if (config == null) return;
        String sensorId = config.optString("sensor_id");
        long now = System.currentTimeMillis();
        JSONObject canary = relayEvent(sensorId, sensorId + ":canary:" + now, now);
        CaptureService.put(canary, "canary", true);
        CaptureService.put(canary, "title", "Canary");
        CaptureService.put(canary, "body", "Relay path test.");
        CaptureService.put(canary, "interruption_level", "active");
        PostResult result = post(config.optString("gateway_url"), config.optString("hmac_secret"),
                canary.toString().getBytes(StandardCharsets.UTF_8));
        recordStatus(context, "RELAY_CANARY", result);
    }

    private static void recordStatus(Context context, String type, PostResult result) {
        JSONObject record = CaptureService.baseEvent(context, type);
        CaptureService.put(record, "http_status", result.status());
        CaptureService.put(record, "error", result.error());
        EvidenceStore.append(context, record);
    }

    /**
     * status -1 means the request never got an HTTP answer; `error` then says why. A bare -1
     * hid a cleartext block on the EC2 for hours. writtenAtMs is when the whole body was on
     * the socket, null if it never got there.
     */
    record PostResult(int status, String error, Long writtenAtMs) {
        static PostResult failed(Exception error, Long writtenAtMs) {
            return new PostResult(-1, error.getClass().getName() + ": " + error.getMessage(), writtenAtMs);
        }

        boolean isSuccess() {
            return status >= 200 && status < 300;
        }
    }

    static PostResult post(String url, String secret, byte[] body) {
        HttpURLConnection connection = null;
        Long writtenAtMs = null;
        try {
            connection = (HttpURLConnection) new URL(url).openConnection();
            connection.setRequestMethod("POST");
            connection.setConnectTimeout(3000);
            connection.setReadTimeout(5000);
            connection.setDoOutput(true);
            connection.setRequestProperty("content-type", "application/json");
            connection.setRequestProperty("x-relay-signature", hmacHex(secret, body));
            // Streamed, not buffered: otherwise the body only leaves in getResponseCode and
            // writtenAtMs would stamp a request still sitting in memory.
            connection.setFixedLengthStreamingMode(body.length);
            try (OutputStream output = connection.getOutputStream()) {
                output.write(body);
            }
            writtenAtMs = System.currentTimeMillis();
            return new PostResult(connection.getResponseCode(), null, writtenAtMs);
        } catch (Exception error) {
            return PostResult.failed(error, writtenAtMs);
        } finally {
            if (connection != null) connection.disconnect();
        }
    }

    static String hmacHex(String secret, byte[] body) throws Exception {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
        StringBuilder hex = new StringBuilder();
        for (byte value : mac.doFinal(body)) hex.append(String.format("%02x", value));
        return hex.toString();
    }

    /** Missing file = lab mode, silent. A file that is there but broken is a sensor gone quiet. */
    private static JSONObject readConfig(Context context) {
        File file = new File(context.getFilesDir(), CONFIG_FILE);
        if (!file.exists()) return null;
        try (FileInputStream input = new FileInputStream(file)) {
            byte[] raw = new byte[(int) file.length()];
            int read = input.read(raw);
            JSONObject config = new JSONObject(new String(raw, 0, Math.max(read, 0), StandardCharsets.UTF_8));
            boolean complete = !config.optString("gateway_url").isEmpty()
                    && !config.optString("hmac_secret").isEmpty()
                    && !config.optString("sensor_id").isEmpty();
            if (complete) return config;
            reportInvalidConfig(context, "missing field");
        } catch (Exception error) {
            reportInvalidConfig(context, error.getClass().getSimpleName());
        }
        return null;
    }

    // Once per listener connection: the heartbeat re-reads the config every 5 min.
    private static void reportInvalidConfig(Context context, String reason) {
        if (invalidConfigReported) return;
        invalidConfigReported = true;
        Log.e("Forwarder", "relay.json invalid: " + reason);
        JSONObject record = CaptureService.baseEvent(context, "RELAY_CONFIG_INVALID");
        CaptureService.put(record, "reason", reason);
        EvidenceStore.append(context, record);
    }

    private static void sleep(long millis) {
        if (millis <= 0) return;
        try {
            Thread.sleep(millis);
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
        }
    }
}
