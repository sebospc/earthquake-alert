import RelayCore
import SwiftUI

struct RootView: View {
    let model: AppModel
    @State private var showingCoverage = false

    var body: some View {
        let state = Self.stateOverride ?? model.state
        let showConsent = Self.stateOverrideName.map { $0 == "consent" } ?? !model.consented
        ZStack {
            // An alert wins even over consent: a phone registered by an older build can still get one.
            if case .alert(let alert) = state {
                AlertView(alert: alert, receivedAt: model.alertReceivedAt ?? .now, onClose: model.dismissAlert)
                    .transition(.opacity)
            } else if showConsent {
                ConsentView(onAccept: model.acceptConsent, serverDeletePending: model.serverDeletePending)
            } else {
                MainView(state: state, onAction: model.primaryAction, onShowCoverage: { showingCoverage = true })
            }
        }
        .animation(.smooth(duration: 0.5), value: state)
        .animation(.smooth(duration: 0.5), value: model.consented)
        .sheet(isPresented: $showingCoverage) {
            CoverageView(followed: model.followed, coverage: model.coverage, lastFix: model.lastFix,
                         testAlert: model.testAlert, onTestAlert: model.sendTestAlert,
                         onWithdrawConsent: {
                             showingCoverage = false
                             model.withdrawConsent()
                         })
        }
    }

    /// `-state covered-full` on launch shows a sample state, `-state consent` the consent screen,
    /// for simulator screenshots and the accessibility audit.
    private static var stateOverrideName: String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "state")
        #else
        nil
        #endif
    }

    private static var stateOverride: AppState? {
        #if DEBUG
        stateOverrideName.flatMap { name in AppState.samples.first { $0.name == name }?.state }
        #else
        nil
        #endif
    }
}
