// ProspectUITests/ProspectFlowUITests.swift
// End-to-end smoke test against a LOCAL API — never production. Opt-in:
//   cd api && npm run dev:local
//   cd ios && TEST_RUNNER_PROSPECT_E2E=1 xcodebuild test -scheme Prospect \
//     -destination 'platform=iOS Simulator,name=<device>' API_BASE_URL=http://localhost:3000 \
//     -only-testing:ProspectUITests
// Creates an admin account, an organization, a program, an event and a prospect.
import XCTest

final class ProspectFlowUITests: XCTestCase {
    // A fresh account each run, so the test never depends on earlier state.
    private let email = "admin+\(Int(Date().timeIntervalSince1970))@prospect.test"
    private let timeout: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PROSPECT_E2E"] == "1",
                          "Opt-in end-to-end test: set TEST_RUNNER_PROSPECT_E2E=1")
        let api = URL(string: "http://localhost:3000/")!
        let reachable = (try? Data(contentsOf: api)) != nil
        try XCTSkipUnless(reachable, "Local API not running on http://localhost:3000")
    }

    @MainActor
    func testSignInAndRegisterAProspect() throws {
        let app = XCUIApplication()
        app.launch()

        // 1. Create an admin account
        let adminTab = app.buttons["Administrateur"]
        XCTAssertTrue(adminTab.waitForExistence(timeout: timeout), "expected the login screen — sign out first")
        adminTab.tap()
        app.buttons["Créer un compte administrateur"].tap()
        let nameField = app.textFields["Prénom Nom"]
        nameField.tap()
        nameField.typeText("Camille Admin")
        let emailField = app.textFields["vous@exemple.com"]
        emailField.tap()
        emailField.typeText(email)
        let passwordField = app.secureTextFields["Mot de passe"]
        passwordField.tap()
        passwordField.typeText("motdepasse-demo")
        app.buttons["Créer mon compte"].tap()

        // 2. New account → create an organization whose events are called "Salon"
        let orgName = app.textFields["Nom (ex. École Horizon)"]
        XCTAssertTrue(orgName.waitForExistence(timeout: timeout))
        orgName.tap()
        orgName.typeText("Organisation démo")
        app.switches["Salon"].firstMatch.tap()
        app.buttons["Créer l'organisation"].tap()

        // 3. Add a program from the organization settings
        let teamTab = app.tabBars.buttons["Équipe"]
        XCTAssertTrue(teamTab.waitForExistence(timeout: timeout))
        teamTab.tap()
        app.buttons["orgSettingsButton"].tap()
        app.buttons["Ajouter un programme"].tap()
        let programName = app.textFields["ex. Informatique"]
        XCTAssertTrue(programName.waitForExistence(timeout: timeout))
        programName.tap()
        programName.typeText("Informatique")
        app.navigationBars.buttons["Enregistrer"].tap()
        XCTAssertTrue(app.staticTexts["Informatique"].waitForExistence(timeout: timeout))

        // 4. Create an event and start it
        app.tabBars.buttons["Prospects"].tap()
        let createEvent = app.buttons["Créer : Salon"]
        if createEvent.waitForExistence(timeout: timeout) {
            createEvent.tap()
            let eventName = app.textFields.firstMatch
            XCTAssertTrue(eventName.waitForExistence(timeout: timeout))
            eventName.tap()
            eventName.typeText("Salon de l'étudiant")
            app.navigationBars.buttons["Créer"].tap()
        }
        let eventMenu = app.buttons["eventMenu"]
        XCTAssertTrue(eventMenu.waitForExistence(timeout: timeout))
        eventMenu.tap()
        app.buttons["Modifier"].tap()
        app.buttons["En cours"].tap()
        app.navigationBars.buttons["Enregistrer"].tap()

        // 5. Register a prospect
        let newProspect = app.buttons["Nouveau prospect"]
        XCTAssertTrue(newProspect.waitForExistence(timeout: timeout))
        newProspect.tap()
        for (placeholder, value) in [
            ("Prénom", "Léa"),
            ("Nom", "Durand"),
            ("email@exemple.com", "lea.durand@exemple.fr"),
            ("+33 6 00 00 00 00", "0612345678"),
        ] {
            let field = app.textFields[placeholder]
            XCTAssertTrue(field.waitForExistence(timeout: timeout), "missing field \(placeholder)")
            field.tap()
            field.typeText(value)
        }
        app.navigationBars.buttons["Enregistrer"].tap()

        XCTAssertTrue(app.staticTexts["Léa Durand"].waitForExistence(timeout: timeout))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Prospect list"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
