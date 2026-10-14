import XCTest
import Foundation

/// Rendered navigation using a real local Auth session prepared in this isolated app.
/// No injected permissions, provider requests, data writes or account changes.
@MainActor
final class ConnectedAcceptanceTests: XCTestCase {
    private var app: XCUIApplication!

    override func tearDownWithError() throws {
        guard app != nil else { return }
        if (testRun?.failureCount ?? 0) > 0 {
            capture("Connected journey failure")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Connected failure hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        app.terminate()
    }

    func testVerifiedTeamNavigationAndPublishedMovement() throws {
        guard let text = ProcessInfo.processInfo.environment["TEAMSTATS_CONNECTED_UI_FIXTURE"] else {
            throw XCTSkip("Explicit synthetic connected UI fixture is not configured")
        }
        let fixture = try JSONDecoder().decode(ConnectedUIFixture.self, from: Data(text.utf8))
        guard [fixture.teamName, fixture.publishedPlayTitle, fixture.localGameOpponent,
               fixture.sharedGameOpponent].allSatisfy({ $0.hasPrefix("TEST ONLY") }),
              fixture.localGameOpponent != fixture.sharedGameOpponent else {
            throw ConnectedUIIssue.unsafeFixture
        }
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.narayanlekhi.TeamStats.UIAcceptance")
        app.terminate()
        app.launch()

        try selectTab("Account")
        try require(app.staticTexts["Account verified"])
        try require(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
            fixture.syntheticActorUUID.uuidString)).firstMatch)
        capture("Actual account restored")

        try selectTab("Team")
        try tap(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", fixture.teamName)).firstMatch)
        try require(app.navigationBars["Team home"])
        try require(app.staticTexts["Active membership confirmed by server"])
        try require(app.buttons["Shared games and statistics"])
        try require(app.buttons["Playbook"])
        try require(app.buttons["Team roster"])
        try require(app.buttons["Manage team"])
        capture("Server confirmed team home")

        try tap(app.buttons["Shared games and statistics"])
        try require(app.navigationBars["Shared games"])
        try require(app.staticTexts[fixture.sharedGameOpponent])
        XCTAssertFalse(app.staticTexts[fixture.localGameOpponent].exists,
                       "Local game must not appear in the shared game list")
        capture("Shared games remain separate")
        try goBack(from: "Shared games")

        try tap(app.buttons["Manage team"])
        try require(app.navigationBars["Team administration"])
        try require(app.staticTexts["Owner access confirmed by server"])
        try tap(app.buttons["Roster"])
        try require(app.navigationBars["Roster"])
        try require(app.buttons["Add actual player"])
        capture("Authorized roster controls")
        try goBack(from: "Roster")
        try goBack(from: "Team administration")

        try tap(app.buttons["Team roster"])
        try require(app.navigationBars["Team roster"])
        try require(app.staticTexts.matching(NSPredicate(format:
            "label CONTAINS %@ OR label == %@", "Jersey ", "No active roster entries")).firstMatch)
        XCTAssertFalse(app.buttons["Add actual player"].exists,
                       "Routine roster viewing must not expose the management editor")
        capture("Routine roster view")
        try goBack(from: "Team roster")

        try tap(app.buttons["Playbook"])
        try require(app.navigationBars["Playbook"])
        try tap(app.buttons[fixture.publishedPlayTitle])
        try require(app.staticTexts["Published revision — read-only"])
        try require(app.buttons["Practice clips"])
        let position = app.sliders["Playback position in seconds"]
        try reveal(position)
        let marker = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Marker 1:")).firstMatch
        try reveal(marker)
        let initialMarker = marker.label
        let initialPosition = position.value as? String
        try tap(app.buttons["Next step"])
        XCTAssertNotEqual(position.value as? String, initialPosition,
                          "Next step must advance the authored playback position")
        XCTAssertNotEqual(marker.label, initialMarker, "Authored marker coordinates must move")
        capture("Published authored movement step")
        try tap(app.buttons["Previous step"])
        XCTAssertEqual(position.value as? String, initialPosition)
        XCTAssertEqual(marker.label, initialMarker)
        try tap(app.buttons["Play"])
        try require(app.buttons["Pause"])
        let advancing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", initialPosition ?? ""), object: position)
        XCTAssertEqual(XCTWaiter.wait(for: [advancing], timeout: 3), .completed,
                       "Actual playback must advance the timeline")
        try tap(app.buttons["Pause"])
        capture("Published movement paused")
        try goBack(from: "View play")
        try goBack(from: "Playbook")

        try selectTab("Local drafts")
        try require(app.navigationBars["Local games"])
        try require(app.staticTexts[fixture.localGameOpponent])
        XCTAssertFalse(app.staticTexts[fixture.sharedGameOpponent].exists,
                       "A shared game must not be copied into local drafts")
        capture("Existing local game preserved")
    }

    func testPublishedPlaybackControlsAtCurrentTextSize() throws {
        try openPublishedPlayControls()
    }

    func testPublishedPlaybackControlsAfterRotation() throws {
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }
        XCUIDevice.shared.orientation = .portrait
        try openPublishedPlayControls()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertGreaterThan(app.frame.width, app.frame.height,
                             "Rotation requires an actual landscape window, not only an orientation command")
        try reveal(app.buttons["Replay"])
        capture("Published controls landscape at current appearance and text size")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertLessThan(app.frame.width, app.frame.height,
                          "Returning to portrait must change the actual window shape")
        try reveal(app.buttons["Next step"])
        XCTAssertTrue(app.buttons["Next step"].isHittable)
        try reveal(app.buttons["Replay"])
        XCTAssertTrue(app.buttons["Replay"].isHittable)
        capture("Published controls portrait at current appearance and text size")
    }

    func testReducedMotionDisclosureAndAuthoredSteps() throws {
        // Root enables the real simulator setting through Accessibility Inspector.
        try openPublishedPlayControls()
        try reveal(app.staticTexts["Reduced Motion: discrete authored positions."])
        let marker = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Marker 1:")).firstMatch
        try reveal(marker)
        let origin = marker.label
        try tap(app.buttons["Next step"])
        XCTAssertNotEqual(marker.label, origin)
        try tap(app.buttons["Previous step"])
        XCTAssertEqual(marker.label, origin)
        capture("Actual system Reduce Motion and authored positions")
    }

    private func openPublishedPlayControls() throws {
        guard let text = ProcessInfo.processInfo.environment["TEAMSTATS_CONNECTED_UI_FIXTURE"] else {
            throw XCTSkip("Explicit synthetic connected UI fixture is not configured")
        }
        let fixture = try JSONDecoder().decode(ConnectedUIFixture.self, from: Data(text.utf8))
        guard fixture.teamName.hasPrefix("TEST ONLY"), fixture.publishedPlayTitle.hasPrefix("TEST ONLY") else {
            throw ConnectedUIIssue.unsafeFixture
        }
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.narayanlekhi.TeamStats.UIAcceptance")
        app.terminate(); app.launch()
        try selectTab("Account")
        try require(app.staticTexts["Account verified"])
        try selectTab("Team")
        try tap(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", fixture.teamName)).firstMatch)
        try require(app.navigationBars["Team home"])
        try tap(app.buttons["Playbook"])
        try tap(app.buttons[fixture.publishedPlayTitle])
        try require(app.staticTexts["Published revision — read-only"])
        try reveal(app.buttons["Replay"])
        try reveal(app.buttons["Next step"])
        capture("Adaptive playback controls at current text size")
        try tap(app.buttons["Next step"])
        try tap(app.buttons["Previous step"])
        capture("Adaptive playback controls after native step actions")
    }

    func testActualReduceMotionSettingAndAuthoredSteps() throws {
        guard let text = ProcessInfo.processInfo.environment["TEAMSTATS_CONNECTED_UI_FIXTURE"] else {
            throw XCTSkip("Explicit synthetic connected UI fixture is not configured")
        }
        let fixture = try JSONDecoder().decode(ConnectedUIFixture.self, from: Data(text.utf8))
        guard fixture.teamName.hasPrefix("TEST ONLY"), fixture.publishedPlayTitle.hasPrefix("TEST ONLY") else {
            throw ConnectedUIIssue.unsafeFixture
        }
        // Swift errors and nonfatal assertions reach the deferred restoration below.
        continueAfterFailure = true
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        let initial = try reduceMotionSwitch(in: settings)
        let originalValue = try motionValue(initial)
        XCTContext.runActivity(named: "Recorded initial Reduce Motion switch: \(originalValue)") { activity in
            let recorded = XCTAttachment(string: originalValue)
            recorded.name = "Original Reduce Motion value"; recorded.lifetime = .keepAlways
            activity.add(recorded)
        }
        defer {
            do {
                let control = try reduceMotionSwitch(in: settings)
                try setMotion(control, to: originalValue)
                XCTContext.runActivity(named: "Restored recorded Reduce Motion switch: \(originalValue)") { _ in }
            } catch {
                let screen = XCTAttachment(screenshot: settings.screenshot())
                screen.name = "Reduce Motion restoration failure"; screen.lifetime = .keepAlways; add(screen)
                XCTFail("Could not restore the recorded Reduce Motion setting; inspect retained Settings evidence")
            }
            settings.terminate()
            app?.activate()
        }
        try setMotion(initial, to: "1")
        app = XCUIApplication(bundleIdentifier: "com.narayanlekhi.TeamStats.UIAcceptance")
        app.terminate(); app.launch()
        try selectTab("Account")
        try require(app.staticTexts["Account verified"])
        try require(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
            fixture.syntheticActorUUID.uuidString)).firstMatch)
        try selectTab("Team")
        // A real transient team-load failure is distinct from an empty team list.
        // Use the offered recovery once; never fabricate membership for navigation.
        if app.buttons["Retry"].exists && app.buttons["Retry"].isHittable {
            capture("Actual team-load failure before Retry")
            app.buttons["Retry"].tap()
        }
        try tap(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", fixture.teamName)).firstMatch)
        try require(app.navigationBars["Team home"])
        try tap(app.buttons["Playbook"])
        try tap(app.buttons[fixture.publishedPlayTitle])
        try require(app.staticTexts["Published revision — read-only"])
        try reveal(app.staticTexts["Reduced Motion: discrete authored positions."])
        let marker = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Marker 1")).firstMatch
        try reveal(marker)
        let origin = marker.label
        try tap(app.buttons["Next step"])
        XCTAssertNotEqual(marker.label, origin, "Reduced Motion must reach the authored next position")
        capture("Actual Reduce Motion authored next step")
        try tap(app.buttons["Previous step"])
        XCTAssertEqual(marker.label, origin, "Previous step must restore the authored origin")
        capture("Actual Reduce Motion authored origin")
    }

    func testObserveSystemRotationLock() throws {
        guard ProcessInfo.processInfo.environment["TEAMSTATS_CONNECTED_UI_FIXTURE"] != nil else {
            throw XCTSkip("An authorized isolated-device fixture is required")
        }
        app = XCUIApplication(bundleIdentifier: "com.narayanlekhi.TeamStats.UIAcceptance")
        app.launch()
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        defer { app.activate() }
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.02))
            .press(forDuration: 0.05, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.65)))
        let state = XCTAttachment(string: springboard.debugDescription)
        state.name = "Observed system rotation controls"; state.lifetime = .keepAlways; add(state)
        let image = XCTAttachment(screenshot: springboard.screenshot())
        image.name = "Observed system Control Center"; image.lifetime = .keepAlways; add(image)
        let controls = springboard.buttons.matching(NSPredicate(format:
            "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "orientation", "rotation"))
        guard controls.count == 1 else {
            throw XCTSkip("System rotation lock has no unique observed control; no setting changed")
        }
        let observed = XCTAttachment(string: "\(controls.firstMatch.label); value=\(String(describing: controls.firstMatch.value)); selected=\(controls.firstMatch.isSelected)")
        observed.name = "Observed rotation lock answer"; observed.lifetime = .keepAlways; add(observed)
        // Observation only. Any actual rotation claim still requires changed geometry.
    }

    private func reduceMotionSwitch(in settings: XCUIApplication) throws -> XCUIElement {
        settings.activate()
        let control = settings.switches["Reduce Motion"].firstMatch
        if control.exists { return control }
        // Return through native Back controls if Settings restores a prior detail.
        for _ in 0..<6 {
            if settings.navigationBars["Settings"].exists { break }
            let back = settings.navigationBars.buttons.firstMatch
            guard back.exists && back.isHittable else { break }
            back.tap()
        }
        try settingsRow("Accessibility", in: settings)
        try settingsRow("Motion", in: settings)
        guard control.waitForExistence(timeout: 10) else { throw ConnectedUIIssue.missingState }
        return control
    }

    private func settingsRow(_ title: String, in settings: XCUIApplication) throws {
        for _ in 0..<8 {
            let cell = settings.cells[title].firstMatch
            let item = cell.exists ? cell : settings.staticTexts[title].firstMatch
            if item.exists && item.isHittable { item.tap(); return }
            let surface: XCUIElement = settings.collectionViews.allElementsBoundByIndex.first(where: { $0.isHittable })
                ?? settings.tables.allElementsBoundByIndex.first(where: { $0.isHittable }) ?? settings
            surface.swipeUp()
        }
        throw ConnectedUIIssue.unreachableControl
    }

    private func motionValue(_ control: XCUIElement) throws -> String {
        guard let value = control.value as? String, ["0", "1"].contains(value) else {
            throw ConnectedUIIssue.missingState
        }
        return value
    }

    private func setMotion(_ control: XCUIElement, to value: String) throws {
        if try motionValue(control) != value {
            guard control.isHittable else { throw ConnectedUIIssue.unreachableControl }
            // Settings exposes the whole labeled row as a switch; target its thumb.
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: control)
        guard XCTWaiter.wait(for: [restored], timeout: 5) == .completed else {
            throw ConnectedUIIssue.missingState
        }
    }

    func testReadOnlyGameAndResourceDestinations() throws {
        guard let text = ProcessInfo.processInfo.environment["TEAMSTATS_CONNECTED_UI_FIXTURE"] else {
            throw XCTSkip("Explicit synthetic connected UI fixture is not configured")
        }
        let fixture = try JSONDecoder().decode(ConnectedUIFixture.self, from: Data(text.utf8))
        guard [fixture.teamName, fixture.publishedPlayTitle, fixture.sharedGameOpponent]
            .allSatisfy({ $0.hasPrefix("TEST ONLY") }) else { throw ConnectedUIIssue.unsafeFixture }
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.narayanlekhi.TeamStats.UIAcceptance")
        app.terminate(); app.launch()
        try selectTab("Account")
        try require(app.staticTexts["Account verified"])
        try require(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
            fixture.syntheticActorUUID.uuidString)).firstMatch)
        try selectTab("Team")
        try tap(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", fixture.teamName)).firstMatch)
        try require(app.navigationBars["Team home"])
        try tap(app.buttons["Shared games and statistics"])
        try tap(app.staticTexts[fixture.sharedGameOpponent])
        try require(app.navigationBars[fixture.sharedGameOpponent])
        try tap(app.buttons["Scouting PDFs"])
        try require(app.navigationBars["Scouting PDFs"])
        capture("Actual scouting reports destination")
        try goBack(from: "Scouting PDFs")
        try tap(app.buttons["Hudl shortcuts and owner review"])
        try require(app.navigationBars["Game Film — Hudl"])
        try require(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Hudl")).firstMatch)
        capture("Independent Hudl shortcut guidance")
        try goBack(from: "Game Film — Hudl")
        try tap(app.buttons["View accepted statistics"])
        try require(app.navigationBars["Published statistics"])
        capture("Read-only accepted statistics destination")
    }

    private func selectTab(_ name: String) throws {
        let button = app.buttons[name].firstMatch
        if !button.exists, app.buttons["Next Page"].exists { app.buttons["Next Page"].tap() }
        try tap(button)
    }

    private func require(_ element: XCUIElement) throws {
        guard element.waitForExistence(timeout: 20) else {
            XCTFail("Expected server-confirmed navigation state did not appear")
            throw ConnectedUIIssue.missingState
        }
    }

    private func reveal(_ element: XCUIElement) throws {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            let surfaces = app.collectionViews.allElementsBoundByIndex + app.scrollViews.allElementsBoundByIndex
            // A visible iPad sidebar must not receive drags meant for its detail column.
            let targetX = element.exists ? element.frame.midX : app.frame.midX
            let surface: XCUIElement = surfaces.last(where: {
                $0.isHittable && $0.frame.minX <= targetX && $0.frame.maxX >= targetX
            }) ?? app
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
        XCTFail("Expected native control was not reachable")
        throw ConnectedUIIssue.unreachableControl
    }

    private func tap(_ element: XCUIElement) throws {
        try reveal(element)
        element.tap()
    }

    private func goBack(from title: String) throws {
        let bar = app.navigationBars[title]
        try require(bar)
        let explicitBack = bar.buttons["Back"]
        try tap(explicitBack.exists ? explicitBack : bar.buttons.element(boundBy: 0))
    }

    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}

private struct ConnectedUIFixture: Decodable {
    let syntheticActorUUID: UUID
    let teamName: String
    let publishedPlayTitle: String
    let localGameOpponent: String
    let sharedGameOpponent: String
}
private enum ConnectedUIIssue: Error { case unsafeFixture, missingState, unreachableControl }
