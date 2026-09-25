import RelayCore
import SwiftUI

@main
struct EarthquakeRelayApp: App {
    var body: some Scene {
        WindowGroup {
            MainView(state: Self.launchState)
        }
    }

    // ponytail: fixed state until the notification and location decisions land (docs/research/ios-techniques.md).
    private static var launchState: AppState {
        #if DEBUG
        // `-state covered` on launch, for simulator screenshots.
        if let name = UserDefaults.standard.string(forKey: "state"),
           let sample = AppState.samples.first(where: { $0.name == name }) {
            return sample.state
        }
        #endif
        return .notSetUp
    }
}
