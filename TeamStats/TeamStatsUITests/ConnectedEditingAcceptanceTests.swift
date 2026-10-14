import XCTest
import Foundation

/// Small actual local-server editing journeys. Only newly created TEST ONLY
/// games/plays are changed; prior drafts, publication and history are untouched.
@MainActor
final class ConnectedEditingAcceptanceTests: XCTestCase {
    private var app: XCUIApplication!

    override func tearDownWithError() throws {
        guard app != nil else { return }
        if (testRun?.failureCount ?? 0) > 0 {
            capture("Connected editing failure")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Editing failure hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        app.terminate()
    }

    func testNewSharedPossessionDraftAndExplicitCompletion() throws {
        _ = try openVerifiedTeam()
        try tap(app.buttons["Shared games and statistics"])
        try require(app.navigationBars["Shared games"])
        let opponent = "TEST ONLY rendered completion " + UUID().uuidString.prefix(8)
        try tap(app.buttons["Add game"])
        try require(app.navigationBars["Add shared game"])
        try replace(app.textFields["Opponent"], with: opponent)
        XCTAssertTrue(app.buttons["Save game on server"].isEnabled)
        capture("Shared game before keyboard-visible Save")
        try tap(app.buttons["Save game on server"])
        let sheet = app.navigationBars["Add shared game"]
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: sheet)
        guard XCTWaiter.wait(for: [dismissed], timeout: 20) == .completed else {
            capture("Shared game Save did not dismiss sheet")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Shared game Save failure hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            throw EditingUIIssue.missingState
        }
        try require(app.navigationBars["Shared games"])
        try tap(app.staticTexts[opponent].firstMatch)
        try tap(app.buttons["Paired possession sheets"])
        try require(app.navigationBars["Possession sheets"])
        try tap(app.buttons["Start our possessions draft"])
        try tap(app.buttons["Add next our team record"])
        let paint = app.textFields["Our team, record 1, Paint touches"]
        try require(paint)
        XCTAssertTrue(["", "Not entered"].contains(paint.value as? String ?? ""))
        try tap(app.buttons["Increase Our team, record 1, Paint touches"])
        XCTAssertEqual(paint.value as? String, "1")
        XCTAssertTrue(app.staticTexts["Opponent · No record 1"].exists)
        capture("Independent shared record remains incomplete")
        try tap(app.buttons["Save both changed sheets"])
        try require(app.staticTexts["Server confirmed all draft changes."])
        try tap(app.buttons["Complete our possessions"])
        try require(app.navigationBars["Complete dataset"])
        try require(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
            "Submission or publication remains a separate action")).firstMatch)
        let warning = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
            "Blank numeric fields in added possession records will become 0")).firstMatch
        if warning.exists {
            capture("Explicit numeric blank conversion confirmation")
            try tap(app.buttons["Confirm"])
        } else {
            // Honor any previously saved synthetic account preference without changing it.
            try require(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
                "Your saved preference allows blank numeric fields")).firstMatch)
            try tap(app.buttons["Confirm completion"])
        }
        try require(app.staticTexts["Server confirmed dataset completion."])
        try require(app.staticTexts["Completed data is read-only until an edit request is approved."])
        XCTAssertFalse(paint.isEnabled)
        capture("Server confirmed completed shared sheet")
        try back(from: "Possession sheets")
        try tap(app.buttons["Paired possession sheets"])
        try require(app.navigationBars["Possession sheets"])
        try require(paint)
        XCTAssertEqual(paint.value as? String, "1")
        XCTAssertFalse(paint.isEnabled)
        capture("Completed shared record reopened read-only")
    }

    func testNewPlayDrawingAndUnsavedNavigationRecovery() throws {
        let fixture = try openVerifiedTeam()
        try tap(app.buttons["Playbook"])
        try require(app.navigationBars["Playbook"])
        try tap(app.buttons["Create a play"])
        try require(app.navigationBars["Edit play"])
        let title = "TEST ONLY rendered drawing " + UUID().uuidString.prefix(8)
        let name = app.textFields["Play name"]
        try replace(name, with: title)
        if app.buttons["Done"].exists { try tap(app.buttons["Done"]) }
        try tap(app.buttons["Add marker"])
        try tap(app.buttons["Add movement step"])
        try tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Marker, ")).firstMatch)
        guard let firstMarker = app.buttons.matching(identifier: "Marker 1").allElementsBoundByIndex.last else { throw EditingUIIssue.missingState }
        try tap(firstMarker)
        let horizontal = app.sliders["Horizontal position"]
        try reveal(horizontal)
        horizontal.adjust(toNormalizedSliderPosition: 0.8)
        let retainedPosition = horizontal.value as? String
        try tap(app.buttons["Back"])
        try tap(app.buttons["Keep editing"])
        XCTAssertEqual(name.value as? String, title)
        try reveal(horizontal)
        XCTAssertEqual(horizontal.value as? String, retainedPosition)
        capture("Unsent authored movement retained after Back")
        try tap(app.navigationBars["Edit play"].buttons["Save"])
        try require(app.staticTexts["Server confirmed the play draft."])
        try replace(name, with: title + " UNSAVED")
        if app.buttons["Done"].exists { try tap(app.buttons["Done"]) }
        try tap(app.buttons["Back"])
        try tap(app.buttons["Discard unsaved edits"])
        try require(app.navigationBars["Playbook"])
        try tap(app.buttons[title])
        try require(app.navigationBars["Edit play"])
        XCTAssertEqual(name.value as? String, title)
        try tap(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Edit position")).firstMatch)
        try tap(app.buttons["Step 1"])
        try tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Marker, ")).firstMatch)
        guard let savedMarker = app.buttons.matching(identifier: "Marker 1").allElementsBoundByIndex.last else { throw EditingUIIssue.missingState }
        try tap(savedMarker)
        try require(app.sliders["Horizontal position"])
        XCTAssertEqual(app.sliders["Horizontal position"].value as? String, retainedPosition)
        capture("Saved drawing restored after client-only discard")
        try tap(app.buttons["Back"])
        try require(app.navigationBars["Playbook"])
        try require(app.buttons[fixture.publishedPlayTitle])
        // No submission/publication or server conflict is induced in this narrow journey.
    }

    private func openVerifiedTeam() throws -> EditingFixture {
        guard let text = ProcessInfo.processInfo.environment["TEAMSTATS_CONNECTED_UI_FIXTURE"] else {
            throw XCTSkip("Actual synthetic connected navigation fixture is required")
        }
        let fixture = try JSONDecoder().decode(EditingFixture.self, from: Data(text.utf8))
        guard [fixture.teamName, fixture.publishedPlayTitle, fixture.localGameOpponent,
               fixture.sharedGameOpponent].allSatisfy({ $0.hasPrefix("TEST ONLY") }) else {
            throw EditingUIIssue.unsafeFixture
        }
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
        try require(app.staticTexts["Active membership confirmed by server"])
        return fixture
    }

    private func replace(_ field: XCUIElement, with value: String) throws {
        try reveal(field)
        let previous = field.value as? String ?? ""
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        if !previous.isEmpty && previous != "Opponent" && previous != "Play name" {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
        }
        field.typeText(value)
        XCTAssertEqual(field.value as? String, value)
    }

    private func selectTab(_ name: String) throws {
        let button = app.buttons[name].firstMatch
        if !button.exists, app.buttons["Next Page"].exists { app.buttons["Next Page"].tap() }
        try tap(button)
    }

    private func require(_ element: XCUIElement) throws {
        guard element.waitForExistence(timeout: 20) else { throw EditingUIIssue.missingState }
    }

    private func reveal(_ element: XCUIElement) throws {
        for _ in 0..<10 {
            if element.exists && element.isHittable {
                let keyboardTop = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : app.frame.maxY
                let navigation = app.navigationBars.allElementsBoundByIndex.last
                let inToolbar = navigation?.buttons.matching(identifier: element.label).count ?? 0 > 0
                let top = navigation?.frame.maxY ?? app.frame.minY
                let tabs = app.tabBars.firstMatch
                let bottom = min(keyboardTop, tabs.exists ? tabs.frame.minY : app.frame.maxY)
                if inToolbar || (element.frame.minY >= top && element.frame.maxY <= bottom) { return }
            }
            let containers = app.collectionViews.allElementsBoundByIndex + app.scrollViews.allElementsBoundByIndex
            let containing = element.exists ? containers.reversed().first {
                let candidates = $0.descendants(matching: element.elementType)
                return element.identifier.isEmpty
                    ? candidates.matching(NSPredicate(format: "label == %@", element.label)).count > 0
                    : candidates.matching(identifier: element.identifier).count > 0
            } : nil
            let surface: XCUIElement = containing
                ?? app.collectionViews.allElementsBoundByIndex.last(where: { $0.isHittable })
                ?? containers.last(where: { $0.isHittable }) ?? app
            let rect = surface.frame.intersection(app.frame)
            let tabs = app.tabBars.firstMatch
            let keyboardTop = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : app.frame.maxY
            let bottom = min(rect.maxY, keyboardTop, tabs.exists && tabs.isHittable ? tabs.frame.minY : app.frame.maxY) - 24
            let top = max(rect.minY, app.navigationBars.allElementsBoundByIndex.last?.frame.maxY ?? 0) + 24
            let down = element.exists && element.frame.midY < top
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: rect.midX, dy: down ? top : bottom))
            let end = origin.withOffset(CGVector(dx: rect.midX, dy: down ? bottom : top))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
        }
        throw EditingUIIssue.unreachableControl
    }

    private func tap(_ element: XCUIElement) throws { try reveal(element); element.tap() }
    private func back(from title: String) throws {
        let bar = app.navigationBars[title]
        try require(bar)
        try tap(bar.buttons["Back"].exists ? bar.buttons["Back"] : bar.buttons.element(boundBy: 0))
    }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}

private struct EditingFixture: Decodable {
    let syntheticActorUUID: UUID
    let teamName: String
    let publishedPlayTitle: String
    let localGameOpponent: String
    let sharedGameOpponent: String
}
private enum EditingUIIssue: Error { case unsafeFixture, missingState, unreachableControl }
