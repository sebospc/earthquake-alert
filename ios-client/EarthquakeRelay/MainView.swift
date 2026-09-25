import RelayCore
import SwiftUI

/// One symbol, one line of state, one line of detail, a button only when the user must act.
struct MainView: View {
    let state: AppState
    var onAction: () -> Void = {}
    var onShowCoverage: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize = 56

    var body: some View {
        let look = Look(state)
        // A sibling after the scroll view, not a safe-area inset, so VoiceOver reads it last.
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: look.symbol)
                        .font(.system(size: symbolSize, weight: .semibold))
                        .foregroundStyle(look.tint)
                        .frame(width: symbolSize * 2.6, height: symbolSize * 2.6)
                        .background(look.tint.opacity(0.13), in: .circle)
                        .contentTransition(.symbolEffect(.replace))
                        // Armed: one slow pulse says "alive". Nothing else moves.
                        .symbolEffect(.pulse, options: .repeat(.periodic(delay: 2.5)).speed(0.5), isActive: look.armed && !reduceMotion)
                        .padding(.bottom, 24)
                        .accessibilityHidden(true)
    
                    Button(action: onShowCoverage) {
                        VStack(spacing: 8) {
                            Text(look.title).font(.title.bold()).foregroundStyle(.primary)
                            if let detail = look.detail {
                                Text(detail).font(.body).foregroundStyle(.primary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Muestra los sensores que lo cubren")
                .accessibilityIdentifier("state")
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, minHeight: 520)
            }
            .scrollBounceBehavior(.basedOnSize)
            if let action = look.action {
                Button(action: onAction) {
                    Text(action).font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .accessibilityIdentifier("action")
                // Solid, darkened tint: white on glass or on system red/green fails the 4.5:1 contrast audit.
                .buttonStyle(.borderedProminent)
                .tint(look.tint.mix(with: .black, by: 0.4))
                .padding(.horizontal, 32)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color(.systemBackground))
        .sensoryFeedback(trigger: look.armed) { _, armed in armed ? .success : .warning }
        .onChange(of: look.title) { _, title in
            AccessibilityNotification.Announcement("\(title). \(look.detail ?? "")").post()
        }
    }
}

/// Words and symbol for each state. Usted, per the research (§6); no numbers on screen.
private struct Look {
    var symbol: String
    var tint: Color
    var title: String
    var detail: String?
    var action: String?
    var armed = false

    init(_ state: AppState) {
        switch state {
        case .notSetUp:
            self.init(symbol: "waveform.path.ecg", tint: .indigo, title: String(localized: "Alertas de sismo"),
                      detail: String(localized: "Le avisamos cuando se detecta un sismo cerca de usted."), action: String(localized: "Activar alertas"))
        case .askingPermission:
            self.init(symbol: "bell.badge.fill", tint: .indigo, title: String(localized: "Un paso más"),
                      detail: String(localized: "Permita las notificaciones para que la alerta le llegue al instante."))
        case .covered(.full):
            self.init(symbol: "checkmark.shield.fill", tint: .green, title: String(localized: "Alertas activas"), detail: String(localized: "Cobertura completa"), armed: true)
        case .covered(.partial):
            self.init(symbol: "shield.lefthalf.filled", tint: .green, title: String(localized: "Alertas activas"), detail: String(localized: "Cobertura parcial: algunos sismos pequeños podrían no avisarse."), armed: true)
        case .covered(.limited):
            self.init(symbol: "shield.lefthalf.filled", tint: .orange, title: String(localized: "Alertas activas"),
                      detail: String(localized: "Cobertura limitada: solo le avisaremos de sismos fuertes."), armed: true)
        case .notCovered:
            self.init(symbol: "shield.slash", tint: .secondary, title: String(localized: "Sin cobertura aún"),
                      detail: String(localized: "Su zona todavía no tiene cobertura."))
        case .alert:
            // Shown by AlertView; kept for completeness.
            self.init(symbol: "exclamationmark.triangle.fill", tint: .red, title: String(localized: "Alerta de sismo"))
        case .error(.notificationsOff):
            self.init(symbol: "bell.slash.fill", tint: .red, title: String(localized: "Alertas desactivadas"),
                      detail: String(localized: "Sin permiso no podemos avisarle."), action: String(localized: "Activar"))
        case .error(.timeSensitiveOff):
            self.init(symbol: "exclamationmark.triangle.fill", tint: .orange, title: String(localized: "Las alertas pueden no sonar"),
                      detail: String(localized: "Con Concentración activa, el aviso puede llegar en silencio."), action: String(localized: "Abrir Ajustes"))
        case .error(.locationOff):
            self.init(symbol: "location.slash.fill", tint: .red, title: String(localized: "Falta su ubicación"),
                      detail: String(localized: "La usamos para elegir los sensores cercanos. Su posición exacta no sale del teléfono."), action: String(localized: "Abrir Ajustes"))
        case .error(.notRegistered):
            self.init(symbol: "wifi.exclamationmark", tint: .red, title: String(localized: "Sin conexión con el servidor"),
                      detail: String(localized: "Reintentando. Mientras tanto no recibirá alertas."))
        case .error(.serviceUnreachable):
            // Could be the phone offline, not us: do not claim we are fixing it.
            self.init(symbol: "antenna.radiowaves.left.and.right.slash", tint: .red, title: String(localized: "Servicio interrumpido"),
                      detail: String(localized: "Ahora mismo no podemos avisarle. Revise su conexión a internet."))
        case .error(.receptorsDown):
            self.init(symbol: "antenna.radiowaves.left.and.right.slash", tint: .red, title: String(localized: "Servicio interrumpido"),
                      detail: String(localized: "Ahora mismo no podemos avisarle. Lo estamos arreglando."))
        }
    }

    private init(symbol: String, tint: Color, title: String, detail: String? = nil, action: String? = nil, armed: Bool = false) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.detail = detail
        self.action = action
        self.armed = armed
    }
}

#if DEBUG
#Preview("Cycle (tap)") {
    @Previewable @State var index = 0
    MainView(state: AppState.samples[index].state)
        .onTapGesture { index = (index + 1) % AppState.samples.count }
}
#Preview("Covered, full") { MainView(state: .covered(.full)) }
#Preview("Covered, limited") { MainView(state: .covered(.limited)) }
#Preview("Not covered") { MainView(state: .notCovered) }
#Preview("Service down") { MainView(state: .error(.receptorsDown)) }
#Preview("Large text") { MainView(state: .error(.locationOff)).dynamicTypeSize(.accessibility3) }
#endif
