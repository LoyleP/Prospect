// ProspectUITests/CreateSessionUITests.swift
// First launch, organizer side: the three-page "Create a session" flow ends with the session running.
import XCTest

final class CreateSessionUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func snap(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testCreatingASessionInThreePages() {
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-debugScenario", "fresh", "-debugHideOverlay"]
        app.launch()

        XCTAssertTrue(app.buttons["organize"].waitForExistence(timeout: 15))
        app.buttons["organize"].tap()

        let organizer = app.textFields["organizerName"]
        XCTAssertTrue(organizer.waitForExistence(timeout: 5))
        organizer.tap(); organizer.typeText("Camille")
        let session = app.textFields["sessionName"]
        session.tap(); session.typeText("Open day")
        snap("1-basics")
        app.buttons["continueOrganize"].tap()

        XCTAssertTrue(app.staticTexts["Programs"].waitForExistence(timeout: 5))
        app.buttons["Add"].tap()
        let programName = app.textFields.firstMatch
        XCTAssertTrue(programName.waitForExistence(timeout: 5))
        programName.typeText("Computer Science")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Computer Science"].waitForExistence(timeout: 5))
        snap("2-programs")
        app.buttons["continueOrganize"].tap()

        XCTAssertTrue(app.staticTexts["Targets"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Computer Science"].exists, "the new program can get a target")
        snap("3-targets")
        app.buttons["continueOrganize"].tap()

        XCTAssertTrue(app.staticTexts["Open day"].waitForExistence(timeout: 10), "the session is created and shown")
        snap("4-running")
    }
}
