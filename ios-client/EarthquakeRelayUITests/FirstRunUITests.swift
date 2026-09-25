import XCTest

/// First run on a clean install: the consent screen comes first and asks for nothing; "Acepto"
/// leads into the notification and location prompts, then the screen leaves setup.
/// Run after `xcrun simctl uninstall <sim> com.example.earthquakerelay` (privacy reset keeps the
/// notification permission).
final class FirstRunUITests: XCTestCase {
    func testConsentComesBeforeAnyPromptAndLeadsIntoThem() {
        let app = XCUIApplication.underTest()
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        let accept = app.buttons["accept"]
        guard accept.waitForExistence(timeout: 5) else {
            return XCTFail("consent screen not shown: uninstall the app first")
        }
        XCTAssertFalse(springboard.alerts.firstMatch.waitForExistence(timeout: 2), "a permission prompt before consent")
        accept.tap()

        XCTAssertTrue(springboard.alerts.firstMatch.waitForExistence(timeout: 5), "Acepto did not ask for notifications")
        for label in ["Allow", "Permitir", "Allow While Using App", "Permitir al usar la app"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 3) { button.tap() }
        }
        XCTAssertFalse(app.buttons["accept"].waitForExistence(timeout: 2), "still on the consent screen")
        XCTAssertTrue(app.buttons["state"].waitForExistence(timeout: 5), "main screen not shown")
    }
}

/// Needs a local dry-run gateway on localhost:8787 (see DEVICE-TESTS.md, "Before starting").
/// Never point it at a live host.
final class TestAlertUITests: XCTestCase {
    /// The gateway accepted it: "sent", in each language (the pseudolanguage is not checked word by word).
    static let sentLine = ["es": "Enviada. Debería sonar en unos segundos.", "en": "Sent. It should sound in a few seconds.",
                           "pt-BR": "Enviado. Deve tocar em alguns segundos."]

    func testProbarAlertaIsAcceptedByTheGateway() throws {
        let app = XCUIApplication.underTest()
        app.launch()
        let stateLine = app.buttons["state"]
        XCTAssertTrue(stateLine.waitForExistence(timeout: 15), "not registered: is the local gateway running?")
        stateLine.tap()

        let probar = app.buttons["testAlert"]
        XCTAssertTrue(probar.waitForExistence(timeout: 5))
        probar.tap()
        let status = app.staticTexts["testAlertStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        if let expected = Self.sentLine[ProcessInfo.processInfo.environment["UI_TEST_LANGUAGE"] ?? "es"] {
            XCTAssertEqual(status.label, expected)
        }
        XCTAssertFalse(probar.isEnabled, "one test per 10 min")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "cobertura-after-probar"
        shot.lifetime = .keepAlways
        add(shot)
    }
}

/// Withdrawing consent goes back to the consent screen. With a local gateway on :8787 the DELETE
/// lands; without one, the consent screen must say the server was not reached.
final class WithdrawConsentUITests: XCTestCase {
    func testWithdrawGoesBackToTheConsentScreen() {
        let app = XCUIApplication.underTest()
        app.launch()
        if app.buttons["accept"].waitForExistence(timeout: 3) {
            app.buttons["accept"].tap()
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            for label in ["Allow", "Permitir", "Allow While Using App", "Permitir al usar la app"] {
                let button = springboard.buttons[label]
                if button.waitForExistence(timeout: 3) { button.tap() }
            }
        }
        let state = app.buttons["state"]
        XCTAssertTrue(state.waitForExistence(timeout: 10))
        state.tap()

        let withdraw = app.buttons["withdraw"]
        XCTAssertTrue(withdraw.waitForExistence(timeout: 5))
        withdraw.tap()
        // The dialog lists its button twice in the tree; either one confirms.
        let confirm = app.buttons["withdrawConfirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "no confirmation asked")
        confirm.tap()

        XCTAssertTrue(app.buttons["accept"].waitForExistence(timeout: 10), "not back on the consent screen")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
    }
}
