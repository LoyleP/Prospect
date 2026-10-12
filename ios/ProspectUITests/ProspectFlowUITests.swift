// ProspectUITests/ProspectFlowUITests.swift
// Smoke test of the first launch, on demo data only (nothing is written to the phone's real store).
// Opt-in, because the UI test runner can hang on some Macs:
//   TEST_RUNNER_PROSPECT_E2E=1 xcodebuild test -scheme Prospect \
//     -destination 'platform=iOS Simulator,name=<device>' -only-testing:ProspectUITests
// Not run as part of the unit tests; last written, not yet run, on Oct 12, 2026.
import XCTest

final class ProspectFlowUITests: XCTestCase {
    private let timeout: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PROSPECT_E2E"] == "1",
                          "Opt-in end-to-end test: set TEST_RUNNER_PROSPECT_E2E=1")
    }

    @MainActor
    func testOrganizerOnboardingReachesTheProspectsTab() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-debugScenario", "fresh"]
        app.launch()

        let organize = app.buttons["organize"]
        XCTAssertTrue(organize.waitForExistence(timeout: timeout), "expected the first-launch choice")
        organize.tap()

        let name = app.textFields["organizerName"]
        XCTAssertTrue(name.waitForExistence(timeout: timeout))
        name.tap()
        name.typeText("Camille Test")
        app.buttons["continueOrganize"].tap()

        XCTAssertTrue(app.buttons["tab-prospects"].waitForExistence(timeout: timeout), "expected the main tabs")
    }
}
