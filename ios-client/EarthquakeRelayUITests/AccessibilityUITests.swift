import XCTest

/// Accessibility Inspector's audit (contrast, Dynamic Type, labels, hit areas) on every screen state,
/// at the default text size and at the largest accessibility size. States come from `-state <name>`
/// (Samples.swift, DEBUG builds only).
final class AccessibilityUITests: XCTestCase {
    private static let states = [
        "consent", "not-set-up", "asking-permission", "covered-full", "covered-partial", "covered-limited", "not-covered",
        "alert", "late-alert", "test-alert", "notifications-off", "time-sensitive-off", "location-off",
        "not-registered", "unreachable", "receptors-down",
    ]

    func testEveryStateAtDefaultTextSize() throws {
        for state in Self.states { try audit(state: state, textSize: nil) }
    }

    func testEveryStateAtLargestTextSize() throws {
        for state in Self.states { try audit(state: state, textSize: "UICTContentSizeCategoryAccessibilityXXXL") }
    }

    /// VoiceOver reads top to bottom: what is going on first, the action last. (A `buttons` query
    /// lists breadth-first, not in reading order, so this compares positions.)
    func testVoiceOverReadsTheStateBeforeTheAction() {
        let consent = launch(state: "consent", textSize: nil)
        assertAbove(consent.staticTexts["consentTitle"], consent.buttons["accept"])

        let main = launch(state: "notifications-off", textSize: nil)
        assertAbove(main.buttons["state"], main.buttons["action"])

        let alert = launch(state: "alert", textSize: nil)
        assertAbove(alert.staticTexts["alertTitle"], alert.buttons["close"])
    }

    private func assertAbove(_ first: XCUIElement, _ second: XCUIElement, line: UInt = #line) {
        XCTAssertTrue(first.waitForExistence(timeout: 5) && second.exists, "missing element", line: line)
        XCTAssertLessThan(first.frame.maxY, second.frame.minY, line: line)
    }

    func testCoverageSheetAtDefaultTextSize() throws { try auditCoverageSheet(textSize: nil) }

    func testCoverageSheetAtLargestTextSize() throws {
        try auditCoverageSheet(textSize: "UICTContentSizeCategoryAccessibilityXXXL")
    }

    private func auditCoverageSheet(textSize: String?) throws {
        let app = launch(state: "covered-full", textSize: textSize)
        app.buttons["state"].tap()
        // Not a row: at the largest size, doubled, the rows start below the fold.
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        sleep(1) // let the sheet finish sliding up, or half-visible rows read as clipped
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
        // At the default size the audit flags the list's lowest rows as "partially unsupported"
        // Dynamic Type: scaled up, they move below the sheet's edge. The largest-size run checks them.
        let ignoring: XCUIAccessibilityAuditType = textSize == nil ? .dynamicType : []
        try audit(app, named: "coverage sheet \(textSize ?? "default")", ignoring: ignoring)
    }

    private func audit(state: String, textSize: String?) throws {
        let app = launch(state: state, textSize: textSize)
        let name = "\(state) \(textSize ?? "default")"
        guard Self.isPseudolanguage else { return try audit(app, named: name) }
        // Doubled text wraps and hyphenates ("interrumpi-do"), and the audit's clipping heuristic
        // reads that as clipped. Truncation is judged from these screenshots instead.
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        try audit(app, named: name, ignoring: .textClipped)
    }

    private static var isPseudolanguage: Bool { ProcessInfo.processInfo.environment["UI_TEST_LANGUAGE"] == "double" }

    /// Every issue fails the test; the name and element say where it is.
    private func audit(_ app: XCUIApplication, named name: String, ignoring: XCUIAccessibilityAuditType = []) throws {
        try app.performAccessibilityAudit(for: XCUIAccessibilityAuditType.all.subtracting(ignoring)) { issue in
            print("AUDIT \(name): \(issue.compactDescription) [\(issue.element?.label ?? "-")]")
            return false
        }
    }

    private func launch(state: String, textSize: String?) -> XCUIApplication {
        let app = XCUIApplication.underTest(["-state", state] + (textSize.map { ["-UIPreferredContentSizeCategoryName", $0] } ?? []))
        app.launch()
        return app
    }
}
