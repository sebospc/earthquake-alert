import RelayCore
import SwiftUI

struct MainView: View {
    let state: AppState
    var onAction: () -> Void = {}

    var body: some View {
        let look = Look(state)
        ZStack {
            look.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                Beacon(symbol: look.symbol, tint: look.tint, pulsing: look.pulsing)
                    .padding(.bottom, 44)

                if let headline = look.headline {
                    Text(headline)
                        .font(.system(size: 76, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .transition(.scale.combined(with: .opacity))
                }
                Text(look.title)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .padding(.bottom, 10)
                Text(look.subtitle)
                    .font(.body)
                    .foregroundStyle(look.foreground.opacity(0.7))
                    .frame(maxWidth: 300)

                Spacer()
                if let action = look.action {
                    Button(action: onAction) {
                        Text(action).font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(look.tint)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(look.foreground)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .animation(.smooth(duration: 0.6), value: state)
        .sensoryFeedback(.warning, trigger: state.isAlert)
    }
}

/// Glyph in a soft disc. Rings ripple out while the state is "live" (covered, alert).
private struct Beacon: View {
    let symbol: String
    let tint: Color
    let pulsing: Bool

    var body: some View {
        ZStack {
            if pulsing {
                PhaseAnimator([false, true]) { expanded in
                    ZStack {
                        ForEach(0..<2, id: \.self) { ring in
                            Circle()
                                .stroke(tint.opacity(0.4), lineWidth: 1.5)
                                .scaleEffect(expanded ? 1.5 + CGFloat(ring) * 0.35 : 1)
                                .opacity(expanded ? 0 : 0.9)
                        }
                    }
                } animation: { expanded in
                    expanded ? .easeOut(duration: 2.2) : .linear(duration: 0)
                }
            }
            Circle().fill(tint.opacity(0.14))
            Image(systemName: symbol)
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 150, height: 150)
    }
}

/// Everything the screen says and paints for one state. Spanish: the users are in Colombia.
private struct Look {
    var symbol: String
    var tint: Color
    var title: String
    var subtitle: String
    var headline: String? = nil
    var action: String? = nil
    var pulsing = false
    var background = Color(.systemBackground)
    var foreground = Color.primary

    init(_ state: AppState) {
        switch state {
        case .notSetUp:
            self.init(symbol: "waveform.path.ecg", tint: .indigo,
                      title: "Alertas de sismo",
                      subtitle: "Te avisamos cuando se detecta un sismo cerca de ti.",
                      action: "Activar alertas")
        case .askingPermission:
            self.init(symbol: "bell.badge.fill", tint: .indigo,
                      title: "Un paso más",
                      subtitle: "Permite las notificaciones para que la alerta te llegue al instante.")
        case .covered:
            self.init(symbol: "checkmark.shield.fill", tint: .green,
                      title: "Alertas activas",
                      subtitle: "Tu zona está cubierta.",
                      pulsing: true)
        case .notCovered:
            self.init(symbol: "mappin.slash", tint: .gray,
                      title: "Sin cobertura aún",
                      subtitle: "Tu zona todavía no tiene cobertura.")
        case .alert(let alert) where alert.late:
            self.init(symbol: "clock.badge.exclamationmark.fill", tint: .white,
                      title: "Aviso de sismo atrasado",
                      subtitle: "Ya no es un aviso anticipado.",
                      headline: alert.magnitudeText,
                      background: Color(red: 0.55, green: 0.3, blue: 0.05), foreground: .white)
        case .alert(let alert):
            self.init(symbol: "exclamationmark.triangle.fill", tint: .white,
                      title: "Protéjase ahora",
                      subtitle: alert.magnitude == nil ? "Posible sismo cerca de tu zona." : "Sismo cerca de tu zona.",
                      headline: alert.magnitudeText, pulsing: true,
                      background: Color(red: 0.86, green: 0.1, blue: 0.12), foreground: .white)
        case .error(.notificationsOff):
            self.init(symbol: "bell.slash.fill", tint: .red,
                      title: "Alertas desactivadas",
                      subtitle: "Actívalas en Ajustes para recibir los avisos.",
                      action: "Abrir Ajustes")
        case .error(.notRegistered):
            self.init(symbol: "arrow.triangle.2.circlepath", tint: .red,
                      title: "Aún no estás registrado",
                      subtitle: "Reintentando. Hasta entonces no recibirás alertas.")
        case .error(.serviceUnreachable):
            // Could be the phone offline, not us: do not claim we are fixing it.
            self.init(symbol: "antenna.radiowaves.left.and.right.slash", tint: .red,
                      title: "Servicio interrumpido",
                      subtitle: "Ahora mismo no podemos avisarte. Revisa tu conexión a internet.")
        case .error(.receptorsDown):
            self.init(symbol: "antenna.radiowaves.left.and.right.slash", tint: .red,
                      title: "Servicio interrumpido",
                      subtitle: "Ahora mismo no podemos avisarte. Lo estamos arreglando.")
        }
    }

    private init(symbol: String, tint: Color, title: String, subtitle: String, headline: String? = nil,
                 action: String? = nil, pulsing: Bool = false,
                 background: Color = Color(.systemBackground), foreground: Color = .primary) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.headline = headline
        self.action = action
        self.pulsing = pulsing
        self.background = background
        self.foreground = foreground
    }
}

private extension AppState {
    var isAlert: Bool { if case .alert = self { true } else { false } }
}

#Preview("Not set up") { MainView(state: .notSetUp) }
#Preview("Asking permission") { MainView(state: .askingPermission) }
#Preview("Covered") { MainView(state: .covered(receptors: 2)) }
#Preview("Not covered") { MainView(state: .notCovered) }
#Preview("Alert") { MainView(state: AppState.sample("alert")) }
#Preview("Late alert") { MainView(state: AppState.sample("late-alert")) }
#Preview("Error") { MainView(state: .error(.receptorsDown)) }
#Preview("Cycle") {
    @Previewable @State var index = 0
    MainView(state: AppState.samples[index].state)
        .onTapGesture { index = (index + 1) % AppState.samples.count }
}
