import Foundation
import XCTest
@testable import RelayCore

final class PushTextTests: XCTestCase {
    private let alertPush: [AnyHashable: Any] = [
        "aps": ["alert": ["title": "Alerta de sismo", "body": "Sismo M4.8 cerca de su zona. Protéjase ahora.",
                          "title-loc-key": "ALERT_TITLE", "loc-key": "ALERT_BODY_MAGNITUDE", "loc-args": ["4.8"]]],
        "kind": "alert", "magnitude": 4.8,
    ]

    /// The app's real catalog, as the NSE's `Bundle.main.localizedString` would read it.
    private func catalog(_ language: String) throws -> (String) -> String? {
        let url = LocalizationCatalogTests.iosClient.appending(path: "EarthquakeRelay/Localizable.xcstrings")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: [String: Any]])
        return { key in
            let localization = (strings[key]?["localizations"] as? [String: Any])?[language] as? [String: Any]
            return (localization?["stringUnit"] as? [String: Any])?["value"] as? String
        }
    }

    func testCatalogTextWithThePhonesDecimalSeparator() throws {
        let spanish = try XCTUnwrap(PushText.resolve(userInfo: alertPush, locale: Locale(identifier: "es_CO"), localizedFormat: catalog("es")))
        XCTAssertEqual(spanish.title, "Alerta de sismo")
        XCTAssertEqual(spanish.body, "Sismo M4,8 cerca de su zona. Protéjase ahora.")

        let english = try XCTUnwrap(PushText.resolve(userInfo: alertPush, locale: Locale(identifier: "en_US"), localizedFormat: catalog("en")))
        XCTAssertEqual(english.title, "Earthquake Alert")
        XCTAssertEqual(english.body, "Sismo M4.8 cerca de su zona. Protéjase ahora.", "safety wording stays Spanish until languages.md")
    }

    func testCatalogWithoutTheKeyFallsBackToTheSpanishPayloadNeverTheRawKey() throws {
        let stripped: (String) -> String? = { key in key == "ALERT_BODY_MAGNITUDE" ? nil : try? self.catalog("en")(key) }
        let text = try XCTUnwrap(PushText.resolve(userInfo: alertPush, locale: Locale(identifier: "en_US"), localizedFormat: stripped))
        XCTAssertEqual(text.title, "Earthquake Alert")
        XCTAssertEqual(text.body, "Sismo M4.8 cerca de su zona. Protéjase ahora.")

        let empty = try XCTUnwrap(PushText.resolve(userInfo: alertPush, locale: .current, localizedFormat: { _ in nil }))
        XCTAssertEqual(empty.title, "Alerta de sismo")
        XCTAssertFalse(empty.body.contains("ALERT_"))
    }

    func testTranslationWithTheWrongPlaceholderFallsBackInsteadOfCrashing() throws {
        let broken: (String) -> String? = { $0 == "ALERT_BODY_MAGNITUDE" ? "Quake M%d nearby" : "Earthquake Alert" }
        let text = try XCTUnwrap(PushText.resolve(userInfo: alertPush, locale: .current, localizedFormat: broken))
        XCTAssertEqual(text.body, "Sismo M4.8 cerca de su zona. Protéjase ahora.")
        XCTAssertEqual(PushText.placeholders(in: "%1$@ y %2$@, 100%%"), 2)
    }

    func testLateAlertKeepsTheMinutesArgument() throws {
        let late: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Aviso de sismo atrasado", "body": "El sismo ocurrió hace 3 min. Ya no es un aviso anticipado.",
                              "title-loc-key": "LATE_ALERT_TITLE", "loc-key": "LATE_ALERT_BODY", "loc-args": ["3"]]],
            "kind": "alert", "magnitude": 5.2, "late": true,
        ]
        let text = try XCTUnwrap(PushText.resolve(userInfo: late, locale: Locale(identifier: "es_CO"), localizedFormat: catalog("es")))
        XCTAssertEqual(text.body, "El sismo ocurrió hace 3 min. Ya no es un aviso anticipado.")
    }

    func testPushWithoutLocKeysIsLeftAlone() {
        let probe: [AnyHashable: Any] = ["aps": ["alert": ["title": "Prueba de entrega", "body": "Prueba 3 de 50."]], "kind": "probe"]
        XCTAssertNil(PushText.resolve(userInfo: probe, locale: .current, localizedFormat: { _ in "x" }))
    }
}
