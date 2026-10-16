// ProspectUITests/LanguageUITests.swift
// The language picker on the first screen: English by default, one tap to French and back.
// Runs in a Debug build (the `-debugScenario fresh` launch argument gives a clean first screen).
import XCTest

final class LanguageUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testPickingFrenchThenEnglishFromTheFirstScreen() {
        let app = XCUIApplication()
        // `-appLanguage en` forces the starting language, so a previous run's choice can't leak in.
        app.launchArguments = ["-appLanguage", "en", "-debugScenario", "fresh", "-debugHideOverlay"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Collect your prospects"].waitForExistence(timeout: 15), "English is the default")

        app.buttons["languageMenu"].tap()
        app.buttons["Français"].tap()
        XCTAssertTrue(app.staticTexts["Collectez vos prospects"].waitForExistence(timeout: 8), "the whole screen switches to French")
        XCTAssertTrue(app.buttons["Créer une session"].exists || app.staticTexts["Créer une session"].exists)

        app.buttons["languageMenu"].tap()
        app.buttons["English"].tap()
        XCTAssertTrue(app.staticTexts["Collect your prospects"].waitForExistence(timeout: 8), "and back to English")
    }
}
