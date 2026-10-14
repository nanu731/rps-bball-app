import XCTest
import Foundation

/// Root stages actual local Auth/membership changes between these short journeys.
/// No injected session/authority, server mutation, cache deletion or automatic retention.
@MainActor
final class AccountAccessAcceptanceTests: XCTestCase {
    private var app: XCUIApplication!

    override func tearDownWithError() throws {
        guard app != nil else { return }
        if (testRun?.failureCount ?? 0) > 0 {
            capture("Account access failure")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Account access failure hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        app.terminate()
    }

    func testVerifiedViewerConcealsPreviousActorLibraryAndManagement() throws {
        let fixtures = try launchVerifiedActor(phase: "viewer-before-retain")
        try selectTab("Saved clips")
        try require(app.navigationBars["Saved clips"])
        try require(app.staticTexts["No clips kept on this device"])
        XCTAssertFalse(clipButton(fixtures.media.publishedClipTitle).exists)
        XCTAssertFalse(text(containing: "Saved clips are locked while signed out").exists)
        capture("New verified viewer has a separate empty retained library")
        try selectTab("Team")
        try tap(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", fixtures.navigation.teamName)).firstMatch)
        try require(app.navigationBars["Team home"])
        try require(app.staticTexts["Active membership confirmed by server"])
        try require(app.buttons["Shared games and statistics"])
        try require(app.buttons["Playbook"])
        XCTAssertFalse(app.buttons["Manage team"].exists)
        capture("Active viewer lacks protected management")
    }

    func testKnownRemovedViewerCannotOpenRetainedClip() throws {
        let fixtures = try launchVerifiedActor(phase: "viewer-revoked")
        try selectTab("Saved clips")
        try require(app.navigationBars["Saved clips"])
        let clip = clipButton(fixtures.media.publishedClipTitle)
        try require(clip)
        capture("Previously retained viewer copy before current rights check")
        // Opening performs the actual authenticated team_access request. Root has
        // removed only this controlled viewer through the signed owner command.
        try tap(clip)
        try require(text(containing: "This device copy is locked for the current account or known access restriction"))
        XCTAssertTrue(clip.waitForNonExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars[fixtures.media.publishedClipTitle].exists)
        XCTAssertFalse(app.staticTexts[fixtures.media.publishedClipTitle].exists)
        capture("Known current denial conceals retained viewer resource")
    }

    func testCurrentSyntheticActorSignOutConcealsLibrary() throws {
        let fixtures = try launchVerifiedActor(phase: "signout")
        try tap(app.buttons["Sign out"])
        try require(text(containing: "Sign out and close shared screens?"))
        let candidates = app.buttons.matching(NSPredicate(format: "label == %@", "Sign out")).allElementsBoundByIndex
        guard let confirm = candidates.last(where: { $0.isHittable }) else { throw AccessUIIssue.missingConfirmation }
        confirm.tap()
        try require(app.staticTexts["Signed out"])
        XCTAssertFalse(text(containing: fixtures.navigation.syntheticActorUUID.uuidString).exists)
        try selectTab("Saved clips")
        try require(text(containing: "Saved clips are locked while signed out or after a known account restriction"))
        XCTAssertFalse(clipButton(fixtures.media.publishedClipTitle).exists)
        capture("Actual synthetic sign-out locks retained library without deleting bytes")
    }

    func testRestoredSyntheticOwnerShowsOriginalRetainedClip() throws {
        let fixtures = try launchVerifiedActor(phase: "owner-restored")
        try selectTab("Saved clips")
        try require(app.navigationBars["Saved clips"])
        try require(clipButton(fixtures.media.publishedClipTitle))
        try require(app.staticTexts["Kept on this device"].firstMatch)
        XCTAssertFalse(text(containing: "Saved clips are locked while signed out").exists)
        capture("Freshly restored original actor sees its prior retained copy")
        // Root's byte/manifest guard separately verifies no copy was replaced or deleted.
    }

    private func launchVerifiedActor(phase: String) throws -> (navigation: AccessNavigationFixture, media: AccessMediaFixture) {
        let environment = ProcessInfo.processInfo.environment
        guard environment["TEAMSTATS_UI_ACCESS_PHASE"] == phase,
              let navigationText = environment["TEAMSTATS_CONNECTED_UI_FIXTURE"],
              let mediaText = environment["TEAMSTATS_UI_MEDIA_FIXTURE"] else {
            throw XCTSkip("Explicit root-staged synthetic access phase and fixtures required")
        }
        let navigation = try JSONDecoder().decode(AccessNavigationFixture.self, from: Data(navigationText.utf8))
        let media = try JSONDecoder().decode(AccessMediaFixture.self, from: Data(mediaText.utf8))
        guard navigation.syntheticActorUUID == media.syntheticActorUUID,
              navigation.teamName.hasPrefix("TEST ONLY"), media.publishedClipTitle.hasPrefix("TEST ONLY") else {
            throw AccessUIIssue.unsafeFixture
        }
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.narayanlekhi.TeamStats.UIAcceptance")
        app.terminate(); app.launch()
        try selectTab("Account")
        try require(app.staticTexts["Account verified"])
        try require(text(containing: navigation.syntheticActorUUID.uuidString))
        return (navigation, media)
    }

    private func clipButton(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }
    private func text(containing value: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", value)).firstMatch
    }
    private func selectTab(_ name: String) throws {
        var candidates = app.buttons.matching(identifier: name).allElementsBoundByIndex
        if candidates.isEmpty, app.buttons["Next Page"].exists {
            app.buttons["Next Page"].tap()
            candidates = app.buttons.matching(identifier: name).allElementsBoundByIndex
        }
        // iPad exposes both wrapper and inner tab buttons. Select the hittable inner control.
        guard let button = candidates.last(where: { $0.isHittable }) else {
            throw AccessUIIssue.unreachableControl
        }
        button.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: button)
        guard XCTWaiter.wait(for: [selected], timeout: 5) == .completed else {
            throw AccessUIIssue.missingState
        }
    }
    private func require(_ element: XCUIElement) throws {
        guard element.waitForExistence(timeout: 20) else { throw AccessUIIssue.missingState }
    }
    private func tap(_ element: XCUIElement) throws {
        for _ in 0..<8 {
            if element.exists && element.isHittable { element.tap(); return }
            let surface: XCUIElement = app.collectionViews.allElementsBoundByIndex.last(where: { $0.isHittable })
                ?? app.scrollViews.allElementsBoundByIndex.last(where: { $0.isHittable }) ?? app
            surface.swipeUp(velocity: .slow)
        }
        throw AccessUIIssue.unreachableControl
    }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}

private struct AccessNavigationFixture: Decodable {
    let syntheticActorUUID: UUID
    let teamName: String
    let publishedPlayTitle: String
    let localGameOpponent: String
    let sharedGameOpponent: String
}
private struct AccessMediaFixture: Decodable {
    let syntheticActorUUID: UUID
    let syntheticTeamID: UUID
    let syntheticPlayID: UUID
    let publishedClipVersionID: UUID
    let publishedClipTitle: String
}
private enum AccessUIIssue: Error { case unsafeFixture, missingState, unreachableControl, missingConfirmation }
