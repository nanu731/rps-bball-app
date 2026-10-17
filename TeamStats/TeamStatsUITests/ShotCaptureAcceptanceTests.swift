import XCTest

/// Synthetic journeys in the isolated app; never touches an original installation.
@MainActor
final class ShotCaptureAcceptanceTests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.narayanlekhi.TeamStats.ShotAcceptance")
    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0 {
            let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Shot acceptance failure"; image.lifetime = .keepAlways; add(image)
            let tree = XCTAttachment(string: app.debugDescription); tree.name = "Synthetic failure tree"; tree.lifetime = .keepAlways; add(tree)
        }
    }
    private var gameName = ""
    private func openCapture() {
        continueAfterFailure = false
        app.launch()
        let tab = app.buttons["Local drafts"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5)); tab.tap()
        app.buttons["Add game"].tap()
        let field = app.textFields["Opponent"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap()
        gameName = "TEST ONLY shot capture \(UUID().uuidString.prefix(5))"
        field.typeText(gameName)
        app.buttons["Save"].tap()
        let game = app.staticTexts[gameName]
        XCTAssertTrue(game.waitForExistence(timeout: 5)); game.tap()
        let recorder = app.buttons["Shot recorder"]
        XCTAssertTrue(recorder.waitForExistence(timeout: 5)); recorder.tap()
    }
    func testCourtPendingResultFreeThrowsAndUndo() { runFlow() }
    func testLargerTextCaptureAndRelaunch() {
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        runFlow()
    }
    private func reveal(_ element: XCUIElement, upward: Bool = true) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            if upward { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.isHittable)
    }
    private func runFlow() {
        openCapture()
        XCTAssertTrue(app.staticTexts["Local shot draft"].waitForExistence(timeout: 5))
        let court = app.otherElements["shot.court"]
        XCTAssertTrue(court.waitForExistence(timeout: 5))
        court.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.3)).tap()
        XCTAssertTrue(app.staticTexts["Pending field goal"].waitForExistence(timeout: 5))
        let opponent = app.segmentedControls["shot.team"].buttons["Opponent"]
        reveal(opponent, upward: false); opponent.tap()
        // Changing the next-entry selection cannot reattribute the already pending shot.
        app.buttons["shot.result.3.made"].tap()
        XCTAssertTrue(app.staticTexts["3 points · Make"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Saved on this device"].waitForExistence(timeout: 5))
        reveal(court, upward: false)
        court.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.65)).tap()
        app.buttons["shot.result.2.missed"].tap()
        XCTAssertTrue(app.staticTexts["2 points · Miss"].firstMatch.waitForExistence(timeout: 5))
        let freeThrows = app.buttons["Free throws"]
        reveal(freeThrows, upward: false); freeThrows.tap()
        app.buttons["2 attempts"].tap()
        app.buttons["Start free throws"].tap()
        app.buttons["shot.ft.1.made"].tap()
        XCTAssertTrue(app.staticTexts["FT1/2 · Make"].waitForExistence(timeout: 5))
        app.buttons["shot.ft.2.missed"].tap()
        XCTAssertTrue(app.staticTexts["FT2/2 · Miss"].waitForExistence(timeout: 5))
        let undo = app.buttons["Undo last change"]
        reveal(undo); undo.tap()
        XCTAssertTrue(app.staticTexts["FT2/2 · Pending"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Saved on this device"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        app.buttons["Local drafts"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts[gameName].waitForExistence(timeout: 5)); app.staticTexts[gameName].tap()
        app.buttons["Shot recorder"].tap()
        XCTAssertTrue(app.staticTexts["1/2 made · 1 pending"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["3 points · Make"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["2 points · Miss"].firstMatch.exists)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Synthetic shot capture"; image.lifetime = .keepAlways; add(image)
    }
    func testFreeThrowCountCorrectionKeepsEarlierAttemptsReachable() {
        openCapture()
        app.buttons["Free throws"].tap()
        let count = app.textFields["Other positive whole-number attempts"]
        count.tap(); count.typeText(XCUIKeyboardKey.delete.rawValue + "11")
        app.buttons["Start free throws"].tap()
        app.buttons["Next attempts"].tap()
        XCTAssertTrue(app.staticTexts["FT11/11 · Pending"].waitForExistence(timeout: 5))
        let correction = app.textFields["Correct number of attempts"]
        correction.tap(); correction.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2) + "2")
        app.buttons["Update attempt count"].tap()
        XCTAssertTrue(app.staticTexts["FT1/2 · Pending"].waitForExistence(timeout: 5))
        correction.tap(); correction.typeText(XCUIKeyboardKey.delete.rawValue + "x")
        XCTAssertFalse(app.buttons["Update attempt count"].isEnabled)
        XCTAssertTrue(app.staticTexts["Count correction not saved. Enter a positive whole number without removing answered attempts."].exists)
    }

    func testSoftwareKeyboardFreeThrowStartRemainsReachable() throws {
        openCapture()
        app.buttons["Free throws"].tap()
        let count = app.textFields["Other positive whole-number attempts"]
        count.tap(); count.typeText(XCUIKeyboardKey.delete.rawValue + "2")
        guard app.keyboards.firstMatch.waitForExistence(timeout: 3) else {
            throw XCTSkip("Software keyboard not visible with current Simulator keyboard configuration")
        }
        let start = app.buttons["Start free throws"]
        XCTAssertTrue(start.isHittable)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Keyboard-visible FT start"; image.lifetime = .keepAlways; add(image)
        start.tap()
        XCTAssertTrue(app.staticTexts["FT1/2 · Pending"].waitForExistence(timeout: 5))
    }

}
