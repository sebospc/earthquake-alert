import Foundation
import XCTest

/// Every string the phone can show exists in every shipped language, and every push loc-key the
/// contract lists is in the app's catalog (APNs looks loc-keys up in the app's Localizable table;
/// a missing one shows the raw key on the lock screen).
final class LocalizationCatalogTests: XCTestCase {
    static let shippedLanguages = ["es", "en", "pt-BR"]
    static let iosClient = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../..").standardized
    static let catalogs = ["EarthquakeRelay/Localizable.xcstrings", "EarthquakeRelay/InfoPlist.xcstrings",
                           "RelayCore/Sources/RelayCore/Localizable.xcstrings"]

    private struct Catalog: Decodable {
        struct Entry: Decodable {
            struct Localization: Decodable {
                struct StringUnit: Decodable { let value: String }
                let stringUnit: StringUnit?
                let variations: [String: [String: Localization]]?
            }
            let shouldTranslate: Bool?
            let localizations: [String: Localization]?
        }
        let sourceLanguage: String
        let strings: [String: Entry]
    }

    private func load(_ path: String) throws -> Catalog {
        try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: Self.iosClient.appending(path: path)))
    }

    func testEveryStringHasEveryShippedLanguage() throws {
        for path in Self.catalogs {
            let catalog = try load(path)
            XCTAssertEqual(catalog.sourceLanguage, "es", path)
            for (key, entry) in catalog.strings where entry.shouldTranslate != false {
                for language in Self.shippedLanguages where language != catalog.sourceLanguage {
                    let localization = entry.localizations?[language]
                    let value = localization?.stringUnit?.value ?? (localization?.variations == nil ? nil : "plural")
                    XCTAssertFalse(value?.isEmpty ?? true, "\(path): \"\(key)\" has no \(language)")
                }
            }
        }
    }

    func testEveryContractLocKeyIsInTheAppCatalogInEveryLanguage() throws {
        let contract = try String(contentsOf: Self.iosClient.appending(path: "../docs/ios-contract.md"), encoding: .utf8)
        let keys = Self.locKeys(in: contract)
        XCTAssertGreaterThanOrEqual(keys.count, 13, "ios-contract.md \"Localized text\" table not found or changed shape")
        let catalog = try load("EarthquakeRelay/Localizable.xcstrings")
        for key in keys {
            guard let entry = catalog.strings[key] else {
                XCTFail("loc-key \(key) missing from the app catalog: iOS would show \"\(key)\" on the lock screen")
                continue
            }
            for language in Self.shippedLanguages {
                XCTAssertFalse(entry.localizations?[language]?.stringUnit?.value.isEmpty ?? true, "loc-key \(key) has no \(language)")
            }
        }
    }

    /// Backticked UPPER_SNAKE keys in the table under the "Localized text" heading.
    static func locKeys(in contract: String) -> [String] {
        guard let heading = contract.range(of: #"(?m)^#+ Localized text\s*$"#, options: .regularExpression) else { return [] }
        let section = contract[heading.upperBound...].components(separatedBy: "\n#").first ?? ""
        let rows = section.split(separator: "\n").filter { $0.hasPrefix("|") }
        var seen = Set<String>()
        return rows.flatMap { row in row.matches(of: /`([A-Z][A-Z0-9_]+)`/).map { String($0.output.1) } }
            .filter { seen.insert($0).inserted }
    }

    func testLocKeyParserReadsTheTable() {
        let sample = "### Localized text\n\n| push | `title-loc-key` | `loc-key` |\n|---|---|---|\n| alert | `ALERT_TITLE` | `ALERT_BODY` |\n| late | `ALERT_TITLE` | `LATE_BODY` |\n\n- `NOT_A_ROW`\n\n### Alert\n| `NOT_THIS` | y |\n"
        XCTAssertEqual(Self.locKeys(in: sample), ["ALERT_TITLE", "ALERT_BODY", "LATE_BODY"])
    }
}
