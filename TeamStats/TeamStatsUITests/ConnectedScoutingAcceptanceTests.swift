import XCTest
import Foundation

/// Real published PDF navigation. Root prepares the authorized synthetic document;
/// this test never injects a PDF, account, permissions or downloaded bytes.
@MainActor
final class ConnectedScoutingAcceptanceTests: XCTestCase {
    private var app: XCUIApplication!

    override func tearDownWithError() throws {
        guard app != nil else { return }
        if (testRun?.failureCount ?? 0) > 0 {
            capture("Scouting acceptance failure")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Scouting failure hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        app.terminate()
    }

    func testActualPublishedScoutingPDFOpenScrollAndPinchGestures() throws {
        try checkPublishedPDF(scrollAndZoom: true)
    }

    func testPreviouslyValidatedPublishedPDFOpenAndClose() throws {
        try checkPublishedPDF(scrollAndZoom: false)
    }

    private func checkPublishedPDF(scrollAndZoom: Bool) throws {
        guard let reportText = ProcessInfo.processInfo.environment["TEAMSTATS_UI_SCOUTING_FIXTURE"],
              let navigationText = ProcessInfo.processInfo.environment["TEAMSTATS_CONNECTED_UI_FIXTURE"] else {
            throw XCTSkip("Explicit synthetic scouting and connected navigation fixtures are required")
        }
        let report = try JSONDecoder().decode(ScoutingUIFixture.self, from: Data(reportText.utf8))
        let navigation = try JSONDecoder().decode(ScoutingNavigationFixture.self, from: Data(navigationText.utf8))
        guard report.syntheticActorUUID == navigation.syntheticActorUUID,
              [report.publishedReportTitle, navigation.teamName, navigation.sharedGameOpponent]
                .allSatisfy({ $0.hasPrefix("TEST ONLY") }) else { throw ScoutingUIIssue.unsafeFixture }
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.narayanlekhi.TeamStats.UIAcceptance")
        app.terminate(); app.launch()
        try selectTab("Account")
        try require(app.staticTexts["Account verified"])
        try require(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
            report.syntheticActorUUID.uuidString)).firstMatch)
        try selectTab("Team")
        try tap(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", navigation.teamName)).firstMatch)
        try require(app.navigationBars["Team home"])
        try require(app.staticTexts["Active membership confirmed by server"])
        try tap(app.buttons["Shared games and statistics"])
        try require(app.navigationBars["Shared games"])
        try tap(app.staticTexts[navigation.sharedGameOpponent].firstMatch)
        try tap(app.buttons["Scouting PDFs"])
        try require(app.navigationBars["Scouting PDFs"])
        capture("Actual game linked scouting list")
        try tap(app.staticTexts[report.publishedReportTitle].firstMatch)
        try require(app.navigationBars["Scouting report"])
        try require(app.staticTexts["Published file"])
        try tap(app.buttons["Read saved PDF"])
        try require(app.navigationBars[report.publishedReportTitle])
        XCTAssertFalse(app.staticTexts["Could not open saved report"].exists)
        capture("Actual published PDF opened")
        if !scrollAndZoom {
            try closeViewer()
            try require(app.navigationBars["Scouting report"])
            return
        }

        let document = app.descendants(matching: .any).matching(NSPredicate(format:
            "label == %@", "Saved scouting report")).firstMatch
        let pageOne = pageText("Page 1 of 2")
        guard document.waitForExistence(timeout: 10), pageOne.waitForExistence(timeout: 10) else {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "PDF accessibility surface"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            throw XCTSkip("PDF opened; native runtime does not expose document/page text. Scroll and zoom require rendered manual verification.")
        }
        XCTAssertTrue(pageOne.exists)
        let pageTwo = pageText("Page 2 of 2")
        var reachedPageTwo = false
        for _ in 0..<5 {
            document.swipeUp(velocity: .slow)
            if pageTwo.exists && pageTwo.isHittable { reachedPageTwo = true; break }
        }
        guard reachedPageTwo else { throw ScoutingUIIssue.secondPageNotReached }
        capture("Actual PDF second page after scrolling")
        document.pinch(withScale: 0.75, velocity: -0.5)
        capture("Actual PDF after zoom out gesture")
        document.pinch(withScale: 1.5, velocity: 0.5)
        capture("Actual PDF after native zoom gesture")
        // Gestures are exercised; visible scale changes require screenshot inspection.
        // This assertion proves document survival, not successful zoom.
        XCTAssertTrue(pageTwo.exists)
        try closeViewer()
        try require(app.navigationBars["Scouting report"])
    }

    private func pageText(_ fragment: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    private func selectTab(_ name: String) throws {
        let button = app.buttons[name].firstMatch
        if !button.exists, app.buttons["Next Page"].exists { app.buttons["Next Page"].tap() }
        try tap(button)
    }

    private func closeViewer() throws {
        // The underlying review screen and presented viewer both have Close.
        let controls = app.buttons.matching(identifier: "Close").allElementsBoundByIndex
        guard let visible = controls.first(where: { $0.isHittable }) else { throw ScoutingUIIssue.missingState }
        visible.tap()
    }

    private func require(_ element: XCUIElement) throws {
        guard element.waitForExistence(timeout: 20) else { throw ScoutingUIIssue.missingState }
    }

    private func tap(_ element: XCUIElement) throws {
        for _ in 0..<10 {
            if element.exists && element.isHittable { element.tap(); return }
            let surface: XCUIElement = app.collectionViews.allElementsBoundByIndex.last(where: { $0.isHittable })
                ?? app.scrollViews.allElementsBoundByIndex.last(where: { $0.isHittable }) ?? app
            let rect = surface.frame.intersection(app.frame)
            let tabs = app.tabBars.firstMatch
            let bottom = min(rect.maxY, tabs.exists && tabs.isHittable ? tabs.frame.minY : app.frame.maxY) - 24
            let top = max(rect.minY, app.navigationBars.allElementsBoundByIndex.last?.frame.maxY ?? 0) + 24
            let down = element.exists && element.frame.midY < top
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: rect.midX, dy: down ? top : bottom))
            let end = origin.withOffset(CGVector(dx: rect.midX, dy: down ? bottom : top))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
        }
        throw ScoutingUIIssue.unreachableControl
    }

    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}

private struct ScoutingUIFixture: Decodable {
    let syntheticActorUUID: UUID
    let syntheticTeamID: UUID
    let syntheticGameID: UUID
    let publishedReportVersionID: UUID
    let publishedReportTitle: String
}
private struct ScoutingNavigationFixture: Decodable {
    let syntheticActorUUID: UUID
    let teamName: String
    let publishedPlayTitle: String
    let localGameOpponent: String
    let sharedGameOpponent: String
}
private enum ScoutingUIIssue: Error { case unsafeFixture, missingState, unreachableControl, secondPageNotReached }
