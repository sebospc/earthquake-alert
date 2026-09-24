package com.earthquakes.relay;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.Locale;

import org.junit.Test;

/** Runs on the JDK's HttpURLConnection, not Android's; both stream a fixed-length body. */
public class ForwarderPostTest {
    private static final long GATEWAY_READ_DELAY_MS = 300;
    // Far past the loopback socket buffers, so the write can only finish once the gateway reads.
    private static final int BODY_BYTES = 32 * 1024 * 1024;

    @Test
    public void stampsWhenTheBodyIsOnTheWireNotWhenItIsBuffered() throws Exception {
        try (ServerSocket gateway = new ServerSocket(0, 1, InetAddress.getLoopbackAddress())) {
            final Thread slowReader = new Thread(() -> readLateAndAccept(gateway));
            slowReader.start();
            final long startedAtMs = System.currentTimeMillis();
            final Forwarder.PostResult result = Forwarder.post(
                    "http://127.0.0.1:" + gateway.getLocalPort() + "/events", "secret", new byte[BODY_BYTES]);
            slowReader.join();

            assertEquals(202, result.status());
            assertNotNull(result.writtenAtMs());
            // A buffered body would be "written" at once and only sent in getResponseCode.
            assertTrue("stamped before the body left",
                    result.writtenAtMs() - startedAtMs >= GATEWAY_READ_DELAY_MS);
        }
    }

    @Test
    public void noStampWhenTheBodyNeverLeft() {
        final Forwarder.PostResult result = Forwarder.post("http://127.0.0.1:1/events", "secret", new byte[] {1});
        assertEquals(-1, result.status());
        assertNull(result.writtenAtMs());
    }

    /** Reads the headers, waits, drains the body, then answers 202. */
    private static void readLateAndAccept(ServerSocket gateway) {
        try (Socket client = gateway.accept()) {
            final InputStream input = client.getInputStream();
            long length = -1;
            for (String line = readLine(input); !line.isEmpty(); line = readLine(input)) {
                if (line.toLowerCase(Locale.ROOT).startsWith("content-length:")) {
                    length = Long.parseLong(line.substring("content-length:".length()).trim());
                }
            }
            assertEquals("not a fixed-length body", BODY_BYTES, length);
            Thread.sleep(GATEWAY_READ_DELAY_MS);
            input.readNBytes(BODY_BYTES);
            final OutputStream output = client.getOutputStream();
            output.write("HTTP/1.1 202 Accepted\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                    .getBytes(StandardCharsets.US_ASCII));
            output.flush();
        } catch (Exception error) {
            throw new AssertionError(error);
        }
    }

    private static String readLine(InputStream input) throws Exception {
        final ByteArrayOutputStream line = new ByteArrayOutputStream();
        for (int next = input.read(); next != '\n'; next = input.read()) {
            if (next != '\r') line.write(next);
        }
        return line.toString(StandardCharsets.US_ASCII);
    }
}
