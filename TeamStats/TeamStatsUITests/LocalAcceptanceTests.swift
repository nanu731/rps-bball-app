import XCTest

/// Real native interactions in a separate app/container. Every saved game is labeled synthetic.
@MainActor
final class LocalAcceptanceTests: XCTestCase {
    private var app: XCUIApplication!
    private let first = "temporary-roster-v1-a"
    private let second = "temporary-roster-v1-b"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.narayanlekhi.TeamStats.UIAcceptance")
        XCTAssertEqual(ProcessInfo.processInfo.environment["DEVELOPER_DIR"], "/Applications/Xcode.app/Contents/Developer")
        app.activate()
        selectTab("Local drafts")
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0 {
            capture("Failure")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Failure hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        app.terminate()
    }

    func testScoringModesSaveAndRelaunch() {
        let game = createGame("scoring")
        tap(app.buttons["Single-player entry"])
        let points = field("\(first).points")
        XCTAssertEqual(contents(points), "")
        replace(points, with: "4")
        replace(field("\(first).threesMade"), with: "7")
        XCTAssertTrue(text(containing: "Partial lower bound:").exists)
        XCTAssertTrue(text(containing: "at least 21").exists)
        capture("Partial scoring warning")
        replace(field("\(first).threesMade"), with: "")
        XCTAssertFalse(text(containing: "Points don’t align with made baskets.").exists)
        replace(field("\(first).twosMade"), with: "0")
        replace(field("\(first).threesMade"), with: "0")
        replace(field("\(first).freeThrowsMade"), with: "0")
        XCTAssertTrue(text(containing: "Exact mismatch:").exists)
        replace(field("\(first).points"), with: "0")
        XCTAssertFalse(text(containing: "Points don’t align with made baskets.").exists)
        // The points field is at the top; switch modes without saving this explicit zero.
        tap(app.buttons["Roster table"])
        XCTAssertEqual(contents(field("\(first).points")), "0")
        replace(field("\(first).points"), with: "4")
        replace(field("\(second).points"), with: "1")
        replace(field("\(second).twosMade", axis: .horizontal), with: "2", axis: .horizontal)
        if app.keyboards.firstMatch.exists { hideKeyboard() }
        reveal(text(containing: "Points don’t align with made baskets."))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Temporary Player 1", "Exact mismatch:")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Temporary Player 2", "Partial lower bound:")).firstMatch.exists)
        XCTAssertTrue(text(containing: "Exact mismatch:").exists)
        XCTAssertTrue(text(containing: "Partial lower bound:").exists)
        capture("Multiple affected players")
        tap(app.buttons["Single player"])
        XCTAssertFalse(text(containing: "Partial lower bound:").exists)
        XCTAssertTrue(text(containing: "Exact mismatch:").exists)
        tap(app.buttons["Save draft"])
        XCTAssertTrue(text(containing: "Draft saved on this device.").waitForExistence(timeout: 5))
        tap(app.buttons["Done"])
        app.terminate(); app.launch()
        openGame(game)
        tap(app.buttons["Single-player entry"])
        XCTAssertEqual(contents(field("\(first).points")), "4")
        XCTAssertEqual(contents(field("\(first).threesMade")), "0")
        tap(app.buttons["Done"])
        tap(app.buttons["Local game summary"])
        XCTAssertTrue(text(containing: "Local draft — incomplete and unreviewed").waitForExistence(timeout: 5))
        capture("Saved local summary")
    }

    func testPaintCountersClearingInvalidAndKeyboardSave() {
        let game = createGame("paint touches")
        tap(app.buttons["Player paint-touch drafts"])
        let id = "paint-touches.\(first)"
        let count = field(id)
        XCTAssertEqual(contents(count), "")
        XCTAssertFalse(app.buttons[id + ".decrease"].isEnabled)
        tap(app.buttons[id + ".increase"])
        XCTAssertEqual(contents(count), "1")
        tap(app.buttons[id + ".decrease"])
        XCTAssertEqual(contents(count), "0")
        XCTAssertFalse(app.buttons[id + ".decrease"].isEnabled)
        replace(count, with: "-1")
        XCTAssertFalse(app.buttons["Save draft"].isEnabled)
        XCTAssertFalse(app.buttons[id + ".increase"].isEnabled)
        replace(count, with: "")
        XCTAssertEqual(contents(count), "")
        XCTAssertTrue(app.buttons["Save draft"].isEnabled)
        replace(count, with: "3")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(app.buttons["Save draft"].isHittable)
        capture("Paint keyboard Save")
        tap(app.buttons["Save draft"])
        XCTAssertTrue(text(containing: "Draft saved locally").waitForExistence(timeout: 5))
        tap(app.buttons["Done"])
        app.terminate(); app.launch(); openGame(game)
        tap(app.buttons["Player paint-touch drafts"])
        XCTAssertEqual(contents(field(id)), "3")
        replace(field(id), with: "4")
        tap(app.buttons["Save draft"]); tap(app.buttons["Done"])
        tap(app.buttons["Player paint-touch drafts"])
        XCTAssertEqual(contents(field(id)), "4")
        capture("Reopened edited paint draft")
    }

    func testIndependentPossessionsScrollingAndSave() {
        let game = createGame("paired possessions")
        tap(app.buttons["Possession draft entry"])
        tap(app.buttons["Add next: Our team"])
        XCTAssertTrue(text(containing: "Opponent possession 1 not added.").exists)
        XCTAssertEqual(contents(field("ours.1.paintTouches")), "")
        tap(app.buttons["ours.1.paintTouches.increase"])
        XCTAssertEqual(contents(field("ours.1.paintTouches")), "1")
        tap(app.buttons["ours.1.paintTouches.decrease"])
        XCTAssertEqual(contents(field("ours.1.paintTouches")), "0")
        replace(field("ours.1.paintTouches"), with: "")
        hideKeyboard()
        tap(app.buttons["Add next: Opponent"], axis: .horizontal)
        replace(field("opponent.1.paintTouches", axis: .horizontal), with: "2", axis: .horizontal)
        hideKeyboard()
        // Reach the bottom field of the right column, while retaining independent record numbering.
        replace(field("opponent.1.freeThrowsMissed"), with: "0")
        XCTAssertTrue(app.buttons["Save draft"].isHittable)
        capture("Opponent bottom field and Save")
        tap(app.buttons["Save draft"]); tap(app.buttons["Done"])
        app.terminate(); app.launch(); openGame(game)
        tap(app.buttons["Possession draft entry"])
        XCTAssertEqual(contents(field("ours.1.paintTouches")), "")
        XCTAssertEqual(contents(field("opponent.1.paintTouches", axis: .horizontal)), "2")
        XCTAssertEqual(contents(field("opponent.1.freeThrowsMissed")), "0")
        capture("Reopened paired possessions")
    }

    func testUnsavedNavigationAndUnconfiguredDestinations() {
        tap(app.buttons["Add game"])
        let unsavedName = "TEST ONLY unsaved " + UUID().uuidString
        replace(app.textFields["Opponent"], with: unsavedName)
        tap(app.buttons["Cancel"])
        XCTAssertTrue(app.buttons["Keep editing"].waitForExistence(timeout: 5))
        tap(app.buttons["Keep editing"])
        XCTAssertTrue(app.textFields["Opponent"].exists)
        XCTAssertEqual(contents(app.textFields["Opponent"]), unsavedName)
        tap(app.buttons["Cancel"]); tap(app.buttons["Discard unsaved details"])
        XCTAssertTrue(app.textFields["Opponent"].waitForNonExistence(timeout: 5))
        selectTab("Team")
        XCTAssertTrue(app.buttons["Open Account"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Manage team"].exists)
        capture("Signed-out Team")
        selectTab("Saved clips")
        XCTAssertTrue(app.navigationBars["Saved clips"].waitForExistence(timeout: 5))
        XCTAssertTrue(text(containing: "Saved clips are locked while signed out").exists)
        capture("Signed-out Saved clips")
        selectTab("Account")
        XCTAssertTrue(app.navigationBars["Account"].waitForExistence(timeout: 5))
        XCTAssertTrue(text(containing: "Account server not configured").exists)
        capture("Unconfigured Account")
    }

    func testLocalDraftsContrastAndDescriptions() throws {
        capture("Local drafts before native accessibility audit")
        var obscuredLabels = Set<String>()
        func audit() throws {
            try app.performAccessibilityAudit(for: [.contrast, .sufficientElementDescription]) { issue in
                guard issue.auditType == .contrast, let element = issue.element,
                      element.elementType == .staticText, self.app.tabBars.firstMatch.exists else { return false }
                let bar = self.app.tabBars.firstMatch.frame
                let navigation = self.app.navigationBars["Local games"]
                let frame = element.frame
                let bottomEdge = frame.minY < bar.minY && frame.maxY > bar.minY
                let topEdge = frame.minY < navigation.frame.maxY && frame.maxY > navigation.frame.maxY
                guard bottomEdge || topEdge,
                      navigation.staticTexts.matching(identifier: element.label).count == 0,
                      self.app.tabBars.staticTexts.matching(identifier: element.label).count == 0 else { return false }
                // Retained failures identify native top/bottom bar fading. This
                // filter excludes only partially covered content, never bar controls.
                obscuredLabels.insert(element.label)
                return true
            }
        }
        try audit()
        let labelsToReveal = obscuredLabels
        for label in labelsToReveal {
            let element = app.staticTexts[label].firstMatch
            for _ in 0..<6 {
                let top = app.navigationBars["Local games"].frame.maxY
                if element.exists && element.frame.maxY < app.tabBars.firstMatch.frame.minY && element.frame.minY > top { break }
                let downward = element.exists && element.frame.minY < top
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: downward ? 0.35 : 0.75))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: downward ? 0.6 : 0.5))
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
            }
            XCTAssertTrue(element.exists)
            XCTAssertLessThan(element.frame.maxY, app.tabBars.firstMatch.frame.minY)
            XCTAssertGreaterThan(element.frame.minY, app.navigationBars["Local games"].frame.maxY)
            capture("Previously faded row now fully visible")
            try audit()
        }
    }

    private func selectTab(_ name: String) {
        let button = app.buttons[name].firstMatch
        if !button.exists, app.buttons["Next Page"].exists { app.buttons["Next Page"].tap() }
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }

    private enum Axis { case vertical, verticalUp, horizontal }

    private func reveal(_ element: XCUIElement, axis: Axis = .vertical,
                        file: StaticString = #filePath, line: UInt = #line) {
        for attempt in 0..<12 {
            if element.exists && element.isHittable {
                if element.elementType != .textField { return }
                let keyboardTop = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : app.frame.maxY
                let save = app.buttons["Save draft"]
                let bottom = min(keyboardTop, save.exists && save.isHittable ? save.frame.minY : app.frame.maxY)
                let formTop = app.collectionViews.allElementsBoundByIndex.last?.frame.minY ?? 0
                let rect = element.frame
                // A partly visible field is hittable, but its trailing typing point
                // can lie outside an iPad sheet. Use that sheet's actual viewport.
                let navigation = app.navigationBars.allElementsBoundByIndex.last?.frame ?? app.frame
                if rect.minY >= formTop && rect.maxY <= bottom && rect.minX >= navigation.minX && rect.maxX <= navigation.maxX { return }
            }
            let containers = app.collectionViews.allElementsBoundByIndex + app.scrollViews.allElementsBoundByIndex
            let exists = element.exists
            let containing = exists ? containers.reversed().first {
                let candidates = $0.descendants(matching: element.elementType)
                if !element.identifier.isEmpty { return candidates.matching(identifier: element.identifier).count > 0 }
                return candidates.matching(NSPredicate(format: "label == %@", element.label)).count > 0
            } : nil
            // A lazy Form may not expose its offscreen fields yet. Prefer its collection
            // instead of scrolling the separate, always-visible entry header.
            let fallback = axis != .horizontal ? app.collectionViews.allElementsBoundByIndex.last(where: { $0.isHittable }) : nil
            let surface: XCUIElement = containing ?? fallback ?? containers.last(where: { $0.isHittable }) ?? app
            let rect = surface.frame.intersection(app.frame)
            let keyboardTop = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : app.frame.maxY
            let save = app.buttons["Save draft"]
            let tabs = app.tabBars.firstMatch
            let bottom = min(rect.maxY, keyboardTop, save.exists && save.isHittable ? save.frame.minY : app.frame.maxY, tabs.exists && tabs.isHittable ? tabs.frame.minY : app.frame.maxY) - 16
            let navigationBottom = app.navigationBars.allElementsBoundByIndex.last?.frame.maxY ?? 0
            let top = max(rect.minY, navigationBottom) + 16
            let origin = app.coordinate(withNormalizedOffset: .zero)
            if axis == .horizontal {
                let rightward = element.exists && element.frame.midX < app.frame.midX
                let start = origin.withOffset(CGVector(dx: rightward ? rect.minX + 20 : rect.maxX - 20, dy: (top + bottom) / 2))
                let end = origin.withOffset(CGVector(dx: rightward ? rect.maxX - 20 : rect.minX + 20, dy: (top + bottom) / 2))
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
            } else {
                let downward = element.exists ? element.frame.midY < top : axis == .verticalUp || attempt >= 6
                // Collection frames extend under the software keyboard; drag only in
                // their visible viewport, never across keyboard keys or Save.
                let start = origin.withOffset(CGVector(dx: rect.midX, dy: downward ? top : bottom))
                let distance = min(100, (bottom - top) * 0.65)
                let end = origin.withOffset(CGVector(dx: rect.midX, dy: downward ? top + distance : bottom - distance))
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
            }
        }
        XCTFail("Requested control is not reachable after bounded native scrolling", file: file, line: line)
    }

    private func tap(_ element: XCUIElement, axis: Axis = .vertical) {
        reveal(element, axis: axis); element.tap()
    }

    private func field(_ id: String, axis: Axis = .vertical) -> XCUIElement {
        let element = app.textFields[id]
        reveal(element, axis: id.hasSuffix(".points") && axis == .vertical ? .verticalUp : axis)
        return element
    }

    private func contents(_ field: XCUIElement) -> String {
        let value = field.value as? String ?? ""
        return ["Not entered", "Unentered"].contains(value) ? "" : value
    }

    private func hideKeyboard() {
        // iPad exposes both a keyboard dismissal key and the app footer action.
        let actions = app.buttons.matching(identifier: "Hide keyboard").allElementsBoundByIndex
        guard let action = actions.first(where: { $0.isHittable }) else {
            XCTFail("No visible keyboard dismissal action"); return
        }
        action.tap()
    }

    private func replace(_ field: XCUIElement, with value: String, axis: Axis = .vertical) {
        if app.keyboards.firstMatch.exists && app.buttons["Hide keyboard"].exists {
            hideKeyboard()
        }
        reveal(field, axis: axis)
        // LabeledContent exposes the whole row; its editable control is on the trailing side.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let old = contents(field)
        if !old.isEmpty { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
        if !value.isEmpty { field.typeText(value) }
        XCTAssertEqual(contents(field), value)
    }

    private func text(containing value: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", value)).firstMatch
    }

    private func createGame(_ purpose: String) -> String {
        tap(app.buttons["Add game"])
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        let name = "TEST ONLY UI \(purpose) " + UUID().uuidString
        replace(app.textFields["Opponent"], with: name)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(app.buttons["Save"].isHittable)
        tap(app.buttons["Save"]); openGame(name)
        return name
    }

    private func openGame(_ name: String) {
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 15))
        tap(app.staticTexts[name].firstMatch)
        XCTAssertTrue(app.buttons["Single-player entry"].waitForExistence(timeout: 5))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
