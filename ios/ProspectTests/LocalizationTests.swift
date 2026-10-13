// ProspectTests/LocalizationTests.swift
// The language switch: English by default, French on request, plurals by each language's own rule, and a
// catalog in which no entry is missing a translation or has mismatched placeholders.
import XCTest
@testable import Prospect

final class LocalizationTests: XCTestCase {
    override func setUp() { Language.current = .en }
    override func tearDown() { Language.current = .en }

    func testEnglishIsTheDefaultAndFrenchIsOneSwitchAway() {
        XCTAssertEqual(L("Cancel"), "Cancel")
        Language.current = .fr
        XCTAssertEqual(L("Cancel"), "Annuler")
        Language.current = .en
        XCTAssertEqual(L("Cancel"), "Cancel")
    }

    func testInterpolatedStringsKeepTheirValues() {
        XCTAssertEqual(L("\("Hugo"): nothing new (already imported)."), "Hugo: nothing new (already imported).")
        Language.current = .fr
        XCTAssertEqual(L("\("Hugo"): nothing new (already imported)."), "Hugo : rien de nouveau (déjà importé).")
    }

    func testPluralsFollowEachLanguagesRule() {
        XCTAssertEqual(L("\(0) prospects"), "0 prospects")
        XCTAssertEqual(L("\(1) prospects"), "1 prospect")
        XCTAssertEqual(L("\(2) prospects"), "2 prospects")
        Language.current = .fr
        XCTAssertEqual(L("\(0) prospects"), "0 prospect", "French counts zero as singular")
        XCTAssertEqual(L("\(1) prospects"), "1 prospect")
        XCTAssertEqual(L("\(2) prospects"), "2 prospects")
        XCTAssertEqual(L("\(3) added"), "3 ajoutés")
    }

    func testNounLabelAndFormats() {
        XCTAssertEqual(prospectsNoun(0), "prospects")
        XCTAssertEqual(prospectsNoun(1), "prospect")
        Language.current = .fr
        XCTAssertEqual(prospectsNoun(0), "prospect")
        XCTAssertEqual(prospectsNoun(2), "prospects")
        XCTAssertEqual(Language.percent(50), "50 %")
        XCTAssertEqual(Language.hour(9), "9 h")
        Language.current = .en
        XCTAssertEqual(Language.percent(50), "50%")
        XCTAssertEqual(Language.hour(9), "9:00")
    }

    func testStageNamesShowTheChosenLanguageButStayStoredTheSame() {
        XCTAssertEqual(Statut.curieux.shortLabel, "Discovery")
        XCTAssertEqual(Statut.curieux.rawValue, "Curieux", "stored values never change with the language")
        Language.current = .fr
        XCTAssertEqual(Statut.curieux.shortLabel, "Découverte")
        XCTAssertEqual(Statut.curieux.rawValue, "Curieux")
    }

    @MainActor
    func testSwitchingLanguageOnTheAppStateRebuildsEverythingInTheNewLanguage() {
        let state = AppState.preview(.organizerFull)
        XCTAssertEqual(state.language, .en)
        let epoch = state.epoch
        state.setLanguage(.fr)
        XCTAssertEqual(state.language, .fr)
        XCTAssertEqual(Language.current, .fr)
        XCTAssertEqual(state.epoch, epoch + 1, "the UI tree is rebuilt")
        XCTAssertEqual(state.programName(nil), "Sans programme")
        state.setLanguage(.fr)
        XCTAssertEqual(state.epoch, epoch + 1, "choosing the same language again does nothing")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "appLanguage"), "fr", "the choice is remembered")
    }

    func testErrorsAreTranslated() {
        XCTAssertEqual(ExchangeError.unknownEvent.errorDescription, "This event doesn't exist on this phone.")
        Language.current = .fr
        XCTAssertEqual(ExchangeError.unknownEvent.errorDescription, "Cet événement n'existe pas sur ce téléphone.")
    }

    /// Reads the catalog from the source tree: every entry needs English and French, with the same placeholders.
    func testCatalogHasNoGapsAndMatchingPlaceholders() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Prospect/Localizable.xcstrings")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: [String: Any]])
        XCTAssertGreaterThan(strings.count, 150)

        func values(_ localization: [String: Any]) -> [String] {
            if let unit = localization["stringUnit"] as? [String: Any], let v = unit["value"] as? String { return [v] }
            if let plural = (localization["variations"] as? [String: Any])?["plural"] as? [String: [String: Any]] {
                return plural.values.compactMap { ($0["stringUnit"] as? [String: Any])?["value"] as? String }
            }
            return []
        }
        func placeholders(_ s: String) -> [String] {
            let regex = try! NSRegularExpression(pattern: "%(lld|@)")
            return regex.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { String(s[Range($0.range, in: s)!]) }
        }

        for (key, entry) in strings.sorted(by: { $0.key < $1.key }) {
            let locs = try XCTUnwrap(entry["localizations"] as? [String: [String: Any]], key)
            let en = values(try XCTUnwrap(locs["en"], "\(key): no English"))
            let fr = values(try XCTUnwrap(locs["fr"], "\(key): no French"))
            XCTAssertFalse(en.isEmpty || fr.isEmpty, "\(key): empty translation")
            // Plural forms may drop the number; otherwise both languages must use the same placeholders.
            if en.count == 1 && fr.count == 1 {
                XCTAssertEqual(placeholders(en[0]).sorted(), placeholders(fr[0]).sorted(), "\(key): placeholders differ")
            }
        }
    }
}
