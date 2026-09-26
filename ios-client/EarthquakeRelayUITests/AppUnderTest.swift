import XCTest

extension XCUIApplication {
    /// The app in the language the run asks for, so one suite covers every language:
    /// `TEST_RUNNER_UI_TEST_LANGUAGE=en xcodebuild test ...` (xcodebuild drops the prefix).
    /// Values: `es` (default), `es-CL`, `en`, `pt-BR`, `tr`, `double` (Xcode's double-length pseudolanguage on
    /// Spanish, for truncation). Always explicit: otherwise the app follows the simulator's language.
    static func underTest(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = languageArguments + extraArguments
        return app
    }

    static var languageArguments: [String] {
        switch ProcessInfo.processInfo.environment["UI_TEST_LANGUAGE"] {
        case "es-CL": ["-AppleLanguages", "(es-CL)", "-AppleLocale", "es_CL"]
        case "en": ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        case "pt-BR": ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        case "tr": ["-AppleLanguages", "(tr)", "-AppleLocale", "tr_TR"]
        case "double": ["-AppleLanguages", "(es)", "-AppleLocale", "es_CO", "-NSDoubleLocalizedStrings", "YES"]
        default: ["-AppleLanguages", "(es)", "-AppleLocale", "es_CO"]
        }
    }
}
