import CoreHaptics
import RelayCore
import SwiftUI

/// In-app alert, once the user opens the app or taps the notification. The notification's own
/// sound and vibration are the primary channel; this is second. No map, no distance (contract).
struct AlertView: View {
    let alert: EarthquakeAlert
    let receivedAt: Date
    let onClose: () -> Void

    @State private var haptics: CHHapticEngine?

    @ScaledMetric(relativeTo: .largeTitle) private var magnitudeSize = 96

    var body: some View {
        // A sibling after the scroll view, not a safe-area inset, so VoiceOver reads it last.
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: symbol)
                        .font(.largeTitle)
                        .imageScale(.large)
                        .foregroundStyle(alert.isTest ? .gray : alert.late ? .orange : .red)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.title2.bold())
                        .accessibilityIdentifier("alertTitle")
                    if let magnitude = alert.magnitudeText {
                        Text(magnitude)
                            .font(.system(size: magnitudeSize, weight: .heavy, design: .rounded))
                    }
                    // The gateway's words only: the app adds no advice of its own.
                    if let body = alert.body {
                        Text(body).font(.title3.weight(.semibold))
                    }
                    TimelineView(.periodic(from: receivedAt, by: 1)) { context in
                        // The locale words it ("hace 4 s", "4 sec. ago"); the timeline redraws it every second.
                    Text("Recibida \(receivedAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated).locale(.current)))")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity, minHeight: 560)
            }
            .scrollBounceBehavior(.basedOnSize)
            // White on black: the one control on this screen must be found at a glance.
            Button(action: onClose) {
                Text("Cerrar").font(.headline).foregroundStyle(.black).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .accessibilityIdentifier("close")
            .buttonStyle(.glassProminent)
            .tint(.white)
            .padding(.horizontal, 32)
            .padding(.bottom, 12)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
        .background(.black)
        .accessibilityElement(children: .contain)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            // Late and test alerts: nothing a real, on-time alert does beyond the sound.
            if !alert.late && !alert.isTest { playHaptics() }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            haptics?.stop()
        }
    }

    private var title: String {
        alert.isTest ? String(localized: "Alerta de prueba") : alert.late ? String(localized: "Aviso atrasado")
            : String(localized: "Alerta de sismo")
    }

    private var symbol: String {
        alert.isTest ? "speaker.wave.2.fill" : alert.late ? "clock.badge.exclamationmark.fill" : "exclamationmark.triangle.fill"
    }

    /// A strong tap every second for the first 10 s, only while the app is in front.
    private func playHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = try? CHHapticEngine() else { return }
        let taps = (0..<10).map { second in
            CHHapticEvent(eventType: .hapticTransient,
                          parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                                       CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)],
                          relativeTime: TimeInterval(second))
        }
        guard let pattern = try? CHHapticPattern(events: taps, parameters: []),
              let player = try? engine.makePlayer(with: pattern) else { return }
        try? engine.start()
        try? player.start(atTime: 0)
        haptics = engine
    }
}

#if DEBUG
#Preview("Alert") { AlertView(alert: AppState.sampleAlert, receivedAt: .now - 4, onClose: {}) }
#Preview("Test") {
    AlertView(alert: EarthquakeAlert(eventID: "test:1", magnitude: nil, late: false, expiresAt: .distantFuture,
                                     body: "Así sonará una alerta de sismo. Esto es solo una prueba.", isTest: true),
              receivedAt: .now - 2, onClose: {})
}
#Preview("Late") { AlertView(alert: AppState.sampleLateAlert, receivedAt: .now - 40, onClose: {}) }
#endif
