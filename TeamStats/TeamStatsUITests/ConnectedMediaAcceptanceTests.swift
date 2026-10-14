import XCTest
import Foundation

/// Actual rendered media controls over previously authorized synthetic local bytes.
/// Root alone stops/restores services; this test never injects Auth or media state.
@MainActor
final class ConnectedMediaAcceptanceTests: XCTestCase {
    private var app: XCUIApplication!

    override func tearDownWithError() throws {
        guard app != nil else { return }
        if (testRun?.failureCount ?? 0) > 0 {
            capture("Media acceptance failure")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Media failure hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        app.terminate()
    }

    func testActualRetainedVideoControls() throws {
        let fixture = try fixture()
        coldLaunch()
        try selectTab("Account")
        try require(app.staticTexts["Account verified"])
        try require(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
            fixture.syntheticActorUUID.uuidString)).firstMatch)
        try openSavedClip(fixture)
        try exerciseVideoControls()
        try tap(app.buttons["Close"])
        try require(app.navigationBars["Saved clips"])
        capture("Retained clip still listed after playback")
    }

    func testExplicitKeepControlAndSavedClipNavigation() throws {
        let clip = try fixture()
        guard let text = ProcessInfo.processInfo.environment["TEAMSTATS_CONNECTED_UI_FIXTURE"] else {
            throw XCTSkip("Explicit synthetic connected navigation fixture is required")
        }
        let navigation = try JSONDecoder().decode(MediaNavigationFixture.self, from: Data(text.utf8))
        guard navigation.syntheticActorUUID == clip.syntheticActorUUID,
              navigation.teamName.hasPrefix("TEST ONLY"), navigation.publishedPlayTitle.hasPrefix("TEST ONLY") else {
            throw MediaUIIssue.unsafeFixture
        }
        coldLaunch()
        try selectTab("Account")
        try require(app.staticTexts["Account verified"])
        try require(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", clip.syntheticActorUUID.uuidString)).firstMatch)
        try selectTab("Team")
        try tap(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", navigation.teamName)).firstMatch)
        try require(app.navigationBars["Team home"])
        try tap(app.buttons["Playbook"])
        try tap(app.buttons[navigation.publishedPlayTitle])
        try tap(app.buttons["Practice clips"])
        try require(app.navigationBars["Practice clips"])
        try tap(app.staticTexts[clip.publishedClipTitle].firstMatch)
        try require(app.staticTexts["Published file"])
        capture("Explicit retention before Keep action")
        try tap(app.buttons["Keep on this device"])
        try require(app.navigationBars[clip.publishedClipTitle])
        XCTAssertFalse(app.staticTexts["Playback could not start. The saved file is preserved."].exists)
        capture("Explicit Keep opened verified saved clip")
        let choices = app.buttons.matching(identifier: "Close").allElementsBoundByIndex
        guard let close = choices.first(where: { $0.isHittable }) else { throw MediaUIIssue.missingControl }
        close.tap()
        let recordClose = app.buttons.matching(identifier: "Close").allElementsBoundByIndex
        if let close = recordClose.first(where: { $0.isHittable }) { close.tap() }
        try openSavedClip(clip)
        capture("Explicitly retained clip remains reachable in Saved clips")
    }

    func testColdStartupWithBackendUnavailableUsesRetainedClip() async throws {
        try await checkColdStartupRetainedClip(exerciseControls: true)
    }

    // Separate startup/cache evidence from the runtime's native AVKit-control
    // exposure. The full playback check above remains an independent test.
    func testColdStartupWithBackendUnavailableOpensRetainedViewer() async throws {
        try await checkColdStartupRetainedClip(exerciseControls: false)
    }

    private func checkColdStartupRetainedClip(exerciseControls: Bool) async throws {
        let fixture = try fixture()
        // This must be the exact local API configured by the actual app-host setup.
        // An environment flag alone is not accepted as evidence of unavailability.
        guard let value = ProcessInfo.processInfo.environment["TEAMSTATS_UI_OFFLINE_API_ROOT"],
              let root = URL(string: value), root.host == "127.0.0.1", root.scheme == "http",
              root.user == nil, root.password == nil, root.query == nil, root.fragment == nil,
              root.path.isEmpty || root.path == "/" else {
            throw XCTSkip("Root-controlled unavailable local API precondition is not supplied")
        }
        try await requireBackendUnavailable(root)
        coldLaunch()
        try selectTab("Account")
        try require(app.staticTexts["Account request needs attention"], timeout: 45)
        XCTAssertFalse(app.staticTexts["Account verified"].exists)
        let configuredRoot = app.textFields["Server root URL"]
        for _ in 0..<8 {
            if configuredRoot.exists { break }
            app.collectionViews.firstMatch.swipeUp()
        }
        try require(configuredRoot)
        guard let savedRoot = configuredRoot.value as? String,
              URL(string: savedRoot) == root else { throw MediaUIIssue.offlinePreconditionUnavailable }
        try openSavedClip(fixture)
        try require(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
            "Previously authorized device copy. Current team access could not be checked")).firstMatch)
        capture("Cold startup retained clip with unknown current rights")
        if exerciseControls { try exerciseVideoControls() }
        try await requireBackendUnavailable(root)
        try tap(app.buttons["Close"])
        try require(app.navigationBars["Saved clips"])
    }

    func testSignOutConcealsPreviouslyRetainedClip() throws {
        let fixture = try fixture()
        coldLaunch()
        try selectTab("Account")
        try require(app.staticTexts["Account verified"])
        try require(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
            fixture.syntheticActorUUID.uuidString)).firstMatch)
        try openSavedClip(fixture)
        try tap(app.buttons["Close"])
        try selectTab("Account")
        try tap(app.buttons["Sign out"])
        try require(app.staticTexts["Sign out and close shared screens?"])
        capture("Synthetic sign-out confirmation")
        let signOutChoices = app.buttons.matching(identifier: "Sign out").allElementsBoundByIndex
        guard let confirmation = signOutChoices.first(where: { $0.isHittable }) else {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Sign-out confirmation hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            throw MediaUIIssue.missingControl
        }
        try tap(confirmation)
        try selectTab("Saved clips")
        try require(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@",
            "Saved clips are locked")).firstMatch)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@",
            fixture.publishedClipTitle)).firstMatch.exists)
        capture("Sign-out conceals retained synthetic clip")
    }

    private func fixture() throws -> ConnectedMediaFixture {
        guard let text = ProcessInfo.processInfo.environment["TEAMSTATS_UI_MEDIA_FIXTURE"] else {
            throw XCTSkip("Explicit synthetic retained-media fixture is not configured")
        }
        let fixture = try JSONDecoder().decode(ConnectedMediaFixture.self, from: Data(text.utf8))
        guard fixture.publishedClipTitle.hasPrefix("TEST ONLY") else { throw MediaUIIssue.unsafeFixture }
        continueAfterFailure = false
        return fixture
    }

    private func coldLaunch() {
        app = XCUIApplication(bundleIdentifier: "com.narayanlekhi.TeamStats.UIAcceptance")
        app.terminate(); app.launch()
    }

    private func openSavedClip(_ fixture: ConnectedMediaFixture) throws {
        try selectTab("Saved clips")
        try require(app.navigationBars["Saved clips"])
        let candidates = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", fixture.publishedClipTitle))
        try require(candidates.firstMatch)
        guard candidates.count == 1 else { throw MediaUIIssue.ambiguousClipTitle }
        capture("Previously retained synthetic clip")
        try tap(candidates.firstMatch)
        try require(app.navigationBars[fixture.publishedClipTitle])
        XCTAssertFalse(app.staticTexts["Playback could not start. The saved file is preserved."].exists)
    }

    private func selectTab(_ name: String) throws {
        let button = app.buttons[name].firstMatch
        if !button.exists, app.buttons["Next Page"].exists { app.buttons["Next Page"].tap() }
        try tap(button)
    }

    private func exerciseVideoControls() throws {
        // These are system AVKit controls. If the runtime does not expose them,
        // fail with its actual hierarchy rather than guessing a custom player state.
        if !app.buttons["Play"].exists {
            try tap(app.otherElements["Video"].firstMatch)
        }
        try require(app.buttons["Play"])
        let timeline = try nativeTimeline()
        guard let initial = timeline.value as? String, !initial.isEmpty else {
            throw MediaUIIssue.nativeTimelineUnavailable
        }
        try tap(app.buttons["Play"])
        try require(app.buttons["Pause"], timeout: 5)
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", initial), object: timeline)
        guard XCTWaiter.wait(for: [advanced], timeout: 5) == .completed else { throw MediaUIIssue.playbackDidNotAdvance }
        capture("Actual native video advancing")
        try tap(app.buttons["Pause"])
        guard let before = timeline.value as? String, !before.isEmpty else {
            throw MediaUIIssue.nativeTimelineUnavailable
        }
        timeline.adjust(toNormalizedSliderPosition: 0.65)
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", before), object: timeline)
        guard XCTWaiter.wait(for: [moved], timeout: 5) == .completed else { throw MediaUIIssue.scrubDidNotMove }
        try require(app.buttons["Play"])
        capture("Actual native video paused and scrubbed")
        try tap(app.buttons["Play"])
        try require(app.buttons["Pause"], timeout: 5)
        try tap(app.buttons["Pause"])
    }

    private func nativeTimeline() throws -> XCUIElement {
        let timelineCandidates = app.sliders.matching(NSPredicate(format:
            "label MATCHES[c] %@", ".*(playback|timeline|scrub|progress|time).*") )
        let timeline: XCUIElement
        if timelineCandidates.count == 1 { timeline = timelineCandidates.firstMatch }
        else if app.sliders.count == 1 { timeline = app.sliders.firstMatch }
        else { throw MediaUIIssue.nativeTimelineUnavailable }
        try require(timeline)
        return timeline
    }

    private func requireBackendUnavailable(_ root: URL) async throws {
        var request = URLRequest(url: root.appendingPathComponent("auth/v1/settings"))
        request.timeoutInterval = 5
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        do { _ = try await session.data(for: request) }
        catch let error as URLError {
            guard [.cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet,
                   .timedOut].contains(error.code) else { throw MediaUIIssue.offlinePreconditionUnavailable }
            return
        }
        catch { throw MediaUIIssue.offlinePreconditionUnavailable }
        throw MediaUIIssue.backendStillReachable
    }

    private func require(_ element: XCUIElement, timeout: TimeInterval = 20) throws {
        guard element.waitForExistence(timeout: timeout) else {
            XCTFail("Expected actual media state did not appear")
            throw MediaUIIssue.missingControl
        }
    }

    private func tap(_ element: XCUIElement) throws {
        try require(element)
        for _ in 0..<8 {
            if element.isHittable { element.tap(); return }
            let surface: XCUIElement = app.collectionViews.allElementsBoundByIndex.last(where: { $0.isHittable })
                ?? app.scrollViews.allElementsBoundByIndex.last(where: { $0.isHittable }) ?? app
            surface.swipeUp()
        }
        throw MediaUIIssue.missingControl
    }

    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}

private struct MediaNavigationFixture: Decodable {
    let syntheticActorUUID: UUID
    let teamName: String
    let publishedPlayTitle: String
}

private struct ConnectedMediaFixture: Decodable {
    let syntheticActorUUID: UUID
    let syntheticTeamID: UUID
    let syntheticPlayID: UUID
    let publishedClipVersionID: UUID
    let publishedClipTitle: String
}
private enum MediaUIIssue: Error {
    case unsafeFixture, ambiguousClipTitle, missingControl, nativeTimelineUnavailable
    case playbackDidNotAdvance, scrubDidNotMove, offlinePreconditionUnavailable, backendStillReachable
}
