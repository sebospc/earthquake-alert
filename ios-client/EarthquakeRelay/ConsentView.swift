import SwiftUI

/// First run, before any permission prompt and before anything is sent (Ley 1581 art. 9, and the
/// "not official" line: Código Penal art. 426). Neutral colors and wording on purpose: nothing here
/// may look like SGC, UNGRD or a government alert.
struct ConsentView: View {
    var onAccept: () -> Void = {}
    /// Consent was withdrawn but the server has not confirmed the delete yet.
    var serverDeletePending = false

    // The user hosts both documents; the drafts are in docs/research/legal-colombia.md §4.
    // Replace before TestFlight (see TESTFLIGHT.md).
    static let privacyNoticeURL = URL(string: "https://example.com/sismo/privacidad")!
    static let termsURL = URL(string: "https://example.com/sismo/terminos")!

    var body: some View {
        // A sibling after the scroll view, not a safe-area inset, so VoiceOver reads it last.
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Antes de empezar").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("consentTitle")
                if serverDeletePending {
                    Text("Aún no pudimos borrar su registro del servidor. Seguimos intentando; hasta entonces podría llegarle alguna alerta.")
                        .font(.body.weight(.semibold))
                }
                    Text("Para avisarle guardamos el identificador de notificaciones de su iPhone y una zona aproximada de unos 11 km. Su posición exacta nunca sale del teléfono.")
                    Text("Esta app no es un sistema oficial ni del Estado. Puede fallar o llegar tarde, y no reemplaza las indicaciones de las autoridades.")
                    VStack(alignment: .leading, spacing: 12) {
                        Link("Aviso de privacidad", destination: Self.privacyNoticeURL)
                        Link("Términos de uso", destination: Self.termsURL)
                    }
                    .font(.body.weight(.semibold))
                    .tint(Color.blue.mix(with: .black, by: 0.25))
                }
                .font(.body)
                .padding(.horizontal, 32)
                .padding(.top, 48)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            Button(action: onAccept) {
                Text("Acepto").font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .accessibilityIdentifier("accept")
            .buttonStyle(.borderedProminent)
            .tint(Color.blue.mix(with: .black, by: 0.25))
            .padding(.horizontal, 32)
            .padding(.bottom, 12)
        }
        .background(Color(.systemBackground))
    }
}

#if DEBUG
#Preview { ConsentView() }
#Preview("Delete pending") { ConsentView(serverDeletePending: true) }
#Preview("Large text") { ConsentView().dynamicTypeSize(.accessibility3) }
#endif
