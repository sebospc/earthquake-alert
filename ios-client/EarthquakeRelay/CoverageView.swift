import RelayCore
import SwiftUI

/// The quiet second screen: which receptors cover the user and whether they are up.
struct CoverageView: View {
    let followed: [Sensor]
    let coverage: [String: Bool]?
    let lastFix: Fix?
    var testAlert = TestAlertTracker()
    var onTestAlert: () -> Void = {}
    var onWithdrawConsent: () -> Void = {}

    @State private var confirmingWithdrawal = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // The list's default grey headers and footers, and system blue, fall just short of 4.5:1.
    private static let readable = Color(uiColor: .label)
    private static let readableTint = Color.blue.mix(with: .black, by: 0.25)
    private static let readableDestructive = Color.red.mix(with: .black, by: 0.25)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if followed.isEmpty {
                        Text("Ningún sensor cerca por ahora.")
                    }
                    ForEach(followed, id: \.id) { sensor in
                        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading))
                                                                         : AnyLayout(HStackLayout())
                        layout {
                            name(of: sensor).frame(maxWidth: .infinity, alignment: .leading)
                            state(of: sensor)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Sensores que lo cubren").foregroundStyle(Self.readable)
                } footer: {
                    Text("Su posición exacta no sale del teléfono.").foregroundStyle(Self.readable)
                }
                // Only worth saying when it is old (research §6).
                if let lastFix, Date.now.timeIntervalSince(lastFix.timestamp) > 7 * 24 * 3600 {
                    Section {
                        Text("Ubicación actualizada \(lastFix.timestamp, format: .relative(presentation: .named)). Abra la app en su zona para actualizarla.")
                    }
                }
                Section {
                    // Ticks once a second so "waiting" turns into "no llegó" at 30 s.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Button(action: onTestAlert) { iconText(String(localized: "Probar alerta"), "speaker.wave.2.fill") }
                            .accessibilityIdentifier("testAlert")
                            .font(.body.weight(.semibold))
                            .tint(Self.readableTint)
                            .disabled(!testAlert.canSend(at: context.date))
                        if let line = Self.line(for: testAlert.status(at: context.date)) {
                            Text(line).font(.footnote).accessibilityIdentifier("testAlertStatus")
                        }
                    }
                } footer: {
                    Text("Le enviamos una alerta de prueba para que escuche cómo suena.").foregroundStyle(Self.readable)
                }
                Section {
                    Link("Aviso de privacidad", destination: ConsentView.privacyNoticeURL).tint(Self.readableTint)
                    Link("Términos de uso", destination: ConsentView.termsURL).tint(Self.readableTint)
                    Button("Retirar consentimiento", role: .destructive) { confirmingWithdrawal = true }
                        .accessibilityIdentifier("withdraw")
                        .foregroundStyle(Self.readableDestructive)
                        .confirmationDialog("¿Retirar su consentimiento?", isPresented: $confirmingWithdrawal, titleVisibility: .visible) {
                            Button("Retirar consentimiento", role: .destructive, action: onWithdrawConsent)
                                .accessibilityIdentifier("withdrawConfirm")
                        } message: {
                            Text("Dejará de recibir alertas de sismo y borraremos su registro del servidor.")
                        }
                } footer: {
                    Text("Esta app no es un sistema oficial ni del Estado. Puede fallar o llegar tarde, y no reemplaza las indicaciones de las autoridades.")
                        .foregroundStyle(Self.readable)
                }
            }
            .navigationTitle("Cobertura")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

extension CoverageView {
    private func name(of sensor: Sensor) -> some View {
        Text(sensor.name.isEmpty ? sensor.id : sensor.name)
    }

    @ViewBuilder
    private func state(of sensor: Sensor) -> some View {
        switch coverage?[sensor.id] {
        case true: iconText(String(localized: "Activo"), "checkmark.circle.fill").foregroundStyle(.green)
        case false: iconText(String(localized: "Sin señal"), "xmark.octagon.fill").foregroundStyle(.red)
        case nil: iconText(String(localized: "Sin datos"), "questionmark.circle")
        }
    }

    /// Icon and words in one Text, so it wraps as one at large sizes. A Label reads as clipped to the
    /// accessibility audit.
    private func iconText(_ words: String, _ symbol: String) -> some View {
        Text("\(Image(systemName: symbol)) \(words)").accessibilityLabel(words)
    }

    static func line(for status: TestAlertTracker.Status) -> String? {
        switch status {
        case .ready: nil
        case .sending: String(localized: "Enviando…")
        case .waiting: String(localized: "Enviada. Debería sonar en unos segundos.")
        case .arrived: String(localized: "Llegó. Así sonará una alerta.")
        case .notArrived: String(localized: "No llegó. Revise que las notificaciones estén activadas.")
        case .tooSoon: String(localized: "Espere unos minutos para probar de nuevo.")
        case .notRegistered: String(localized: "Su teléfono aún no está registrado. Reintentando.")
        case .paused: String(localized: "Servicio interrumpido: ahora mismo no podemos avisarle.")
        case .failed: String(localized: "No se pudo enviar. Revise su conexión a internet.")
        }
    }
}

#if DEBUG
#Preview {
    CoverageView(followed: [Sensor(id: "chaparral", name: "Chaparral", lat: 0, lon: 0), Sensor(id: "quibdo", name: "Quibdó", lat: 0, lon: 0)],
                 coverage: ["chaparral": true, "quibdo": false], lastFix: nil)
}
#endif
