import XCTest

/// Real native interactions in a separate app/container. Every saved game is labeled synthetic.
@MainActor
final class LocalAcceptanceTests: XCTestCase {
    private var app: XCUIApplication!
    private let first = "temporary-roster-v1-a"
    private let second = "temporary-roster-v1-b"
    private var originalReduceMotion: String?

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.narayanlekhi.TeamStats.UIAcceptance")
        XCTAssertEqual(ProcessInfo.processInfo.environment["DEVELOPER_DIR"], "/Applications/Xcode.app/Contents/Developer")
        XCUIDevice.shared.orientation = .portrait
        app.activate()
        let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.app.frame.height > self.app.frame.width
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [portrait], timeout: 8), .completed)
        selectTab("Local drafts")
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0 {
            capture("Failure")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Failure hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        if let originalReduceMotion {
            let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
            settings.activate()
            let motion = settings.switches["REDUCE_MOTION"].firstMatch
            if motion.waitForExistence(timeout: 5) {
                if motion.value as? String != originalReduceMotion {
                    motion.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
                }
                let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", originalReduceMotion), object: motion)
                XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed,
                    "Restore the recorded Reduce Motion preference")
            } else { XCTFail("Reduce Motion restoration control unavailable") }
            let image = XCTAttachment(screenshot: settings.screenshot())
            image.name = "Reduce Motion original preference restored"; image.lifetime = .keepAlways; add(image)
            self.originalReduceMotion = nil
        }
        app.terminate()
    }

    func testScoringModesSaveAndRelaunch() {
        let game = createGame("scoring")
        tap(app.buttons["Single-player entry"])
        let points = field("\(first).points")
        XCTAssertEqual(contents(points), "")
        tap(app.buttons[first + ".points.increase"])
        XCTAssertEqual(contents(points), "1")
        tap(app.buttons[first + ".points.decrease"])
        XCTAssertEqual(contents(points), "0")
        replace(points, with: "-1")
        XCTAssertFalse(app.buttons["Save draft"].isEnabled)
        replace(points, with: "4")
        replace(field("\(first).threesMade"), with: "7")
        XCTAssertTrue(text(containing: "Partial lower bound:").exists)
        XCTAssertTrue(text(containing: "at least 21").exists)
        capture("Partial scoring warning")
        replace(field("\(first).threesMade"), with: "")
        XCTAssertFalse(text(containing: "Check scoring").exists)
        replace(field("\(first).twosMade"), with: "0")
        replace(field("\(first).threesMade"), with: "0")
        replace(field("\(first).freeThrowsMade"), with: "0")
        XCTAssertTrue(text(containing: "Exact mismatch:").exists)
        replace(field("\(first).points"), with: "0")
        XCTAssertFalse(text(containing: "Check scoring").exists)
        // The points field is at the top; switch modes without saving this explicit zero.
        tap(app.buttons["Roster table"])
        XCTAssertEqual(contents(field("\(first).points")), "0")
        replace(field("\(first).points"), with: "4")
        replace(field("\(second).points"), with: "1")
        replace(field("\(second).twosMade", axis: .horizontal), with: "2", axis: .horizontal)
        if app.keyboards.firstMatch.exists { hideKeyboard() }
        reveal(text(containing: "Check scoring"))
        tap(app.buttons["scoring-discrepancy-warning.details"])
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
        tap(app.navigationBars["Box-score draft"].buttons["Done"])
        app.terminate(); app.launch()
        openGame(game)
        tap(app.buttons["Single-player entry"])
        XCTAssertEqual(contents(field("\(first).points")), "4")
        XCTAssertEqual(contents(field("\(first).threesMade")), "0")
        tap(app.navigationBars["Box-score draft"].buttons["Done"])
        tap(app.buttons["Local game summary"])
        XCTAssertTrue(text(containing: "Local draft — incomplete and unreviewed").waitForExistence(timeout: 5))
        capture("Saved local summary")
    }

    func testApprovedBoxScoreViewerAndScrolling() {
        let game = createGame("approved ledger")
        tap(app.buttons["View box score"])
        capture("Approved native saved box score, missing values")
        tap(app.buttons["box-score.expand." + second])
        tap(app.buttons["Edit player stats for Temporary Player 2"])
        XCTAssertTrue(text(containing: "Temporary Player 2").exists)
        replace(field(second + ".points"), with: "0")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(app.frame.contains(app.buttons["Save draft"].frame))
        tap(app.buttons["Save draft"])
        XCTAssertTrue(text(containing: "Draft saved on this device.").waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Box-score draft"].buttons["Done"].isEnabled)
        tap(app.navigationBars["Box-score draft"].buttons["Done"])
        XCTAssertTrue(app.buttons["box-score.expand." + second].exists)
        capture("Approved saved box score, expanded explicit zero")
        tap(app.buttons["Enter stats"])
        tap(app.buttons["Roster table"])
        let last = field(second + ".freeThrowsMissed", axis: .horizontal)
        replace(last, with: "0", axis: .horizontal)
        capture("Native table far-right field, horizontal indicator hidden")
        XCTAssertTrue(app.frame.contains(app.buttons["Save draft"].frame))
        tap(app.buttons["Save draft"])
        tap(app.navigationBars["Box-score draft"].buttons["Done"])
        app.terminate(); app.launch(); selectTab("Local drafts"); openGame(game)
        tap(app.buttons["Whole-roster table entry"])
        XCTAssertEqual(contents(field(second + ".points")), "0")
        XCTAssertEqual(contents(field(second + ".freeThrowsMissed", axis: .horizontal)), "0")
        capture("Reopened native roster ledger")
        if app.keyboards.firstMatch.exists { hideKeyboard() }
        let checkHeading = app.scrollViews["box-score-roster-table"].staticTexts["Points check"].firstMatch
        reveal(checkHeading, axis: .horizontal)
        XCTAssertTrue(checkHeading.isHittable)
        capture("Derived columns reachable at the end of the native ledger")
    }

    func testFloatingKeypadSaveAndReopen() throws {
        try XCTSkipIf(app.frame.width < 600, "Floating numeric keypad diagnosis requires the iPad destination")
        let game = createGame("keypad save diagnosis")
        tap(app.buttons["Single-player entry"])
        replace(field(first + ".points"), with: "0")
        let popup = app.otherElements["PopoverDismissRegion"]
        let hadPopup = popup.exists
        XCTAssertTrue(hadPopup, "This diagnosis requires the iPad floating numeric keypad")
        capture("Before Save with native keypad")
        let save = app.buttons["Save draft"]
        XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(app.frame.contains(save.frame))
        save.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        if hadPopup {
            XCTAssertTrue(popup.waitForNonExistence(timeout: 3))
            XCTAssertTrue(text(containing: "Unsaved changes").exists)
            XCTAssertEqual(contents(app.textFields[first + ".points"]), "0")
            XCTAssertFalse(text(containing: "Draft saved on this device.").exists)
            capture("First tap dismissed system popup, input retained")
            XCTAssertTrue(save.isHittable)
            save.tap()
        }
        XCTAssertTrue(text(containing: "Draft saved on this device.").waitForExistence(timeout: 5))
        capture("Actual save receipt after native keypad dismissal")
        tap(app.navigationBars["Box-score draft"].buttons["Done"])
        app.terminate(); app.launch(); selectTab("Local drafts"); openGame(game)
        tap(app.buttons["Single-player entry"])
        XCTAssertEqual(contents(field(first + ".points")), "0")
        capture("Explicit zero reopened after cold launch")
    }

    func testNativeHeaderPanMovesStatistics() {
        app.terminate(); app.launch(); selectTab("Local drafts")
        _ = createGame("native heading pan")
        tap(app.buttons["Whole-roster table entry"])
        let points = app.textFields[first + ".points"]
        let before = points.frame.minX
        capture("Native table before direct heading swipe")
        app.staticTexts["Offensive rebounds"].swipeLeft(velocity: .slow)
        let after = points.frame.minX
        let geometry = XCTAttachment(string: "Points x before: \(before); after: \(after)")
        geometry.lifetime = .keepAlways; add(geometry)
        capture("Native table after direct heading swipe")
        XCTAssertLessThan(after, before - 20, "A native heading swipe must move statistical columns")
    }

    func testFinalStatColumnsSaveAndReopen() {
        let game = createGame("final column acceptance")
        tap(app.buttons["Whole-roster table entry"])
        replace(field(first + ".freeThrowsMissed", axis: .horizontal), with: "0", axis: .horizontal)
        capture("Final numeric column edited, keyboard Save reachable")
        tap(app.buttons["Save draft"])
        XCTAssertTrue(text(containing: "Draft saved on this device.").waitForExistence(timeout: 5))
        tap(app.navigationBars["Box-score draft"].buttons["Done"])
        app.terminate(); app.launch(); selectTab("Local drafts"); openGame(game)
        tap(app.buttons["Whole-roster table entry"])
        XCTAssertEqual(contents(field(first + ".freeThrowsMissed", axis: .horizontal)), "0")
        let table = app.scrollViews["box-score-roster-table"]
        for label in ["Total rebounds", "Points check"] {
            let heading = table.staticTexts[label].firstMatch
            reveal(heading, axis: .horizontal)
            XCTAssertTrue(heading.exists)
            capture("Final derived column: \(label)")
        }
    }

    func testLedgerWithActualReduceMotion() throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.activate()
        let motion = settings.switches["REDUCE_MOTION"].firstMatch
        if !motion.exists {
            for title in ["Accessibility", "Motion"] {
                var reached = false
                for _ in 0..<8 {
                    let candidates = settings.buttons.matching(identifier: title).allElementsBoundByIndex +
                        settings.cells.matching(identifier: title).allElementsBoundByIndex +
                        settings.staticTexts.matching(identifier: title).allElementsBoundByIndex
                    if let row = candidates.first(where: { $0.isHittable }) { row.tap(); reached = true; break }
                    if title == "Accessibility", let back = settings.navigationBars.buttons.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                        back.tap()
                    } else { settings.swipeUp() }
                }
                guard reached else { throw XCTSkip("Native Settings motion route unavailable; no preference changed") }
            }
        }
        XCTAssertTrue(motion.waitForExistence(timeout: 5))
        let original = motion.value as? String
        guard let original, ["0", "1"].contains(original) else { XCTFail("Unrecognized Reduce Motion state"); return }
        // XCTest event-synthesis aborts can bypass Swift defer; teardown still runs.
        originalReduceMotion = original
        if original == "0" { motion.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        XCTAssertEqual(motion.value as? String, "1")
        let enabled = XCTAttachment(screenshot: settings.screenshot())
        enabled.name = "Actual Reduce Motion enabled"; enabled.lifetime = .keepAlways; add(enabled)
        app.terminate(); app.launch(); selectTab("Local drafts")
        _ = createGame("Reduce Motion ledger")
        tap(app.buttons["Single-player entry"])
        tap(app.buttons[first + ".points.increase"])
        XCTAssertEqual(contents(field(first + ".points")), "1")
        tap(app.buttons[first + ".points.decrease"])
        XCTAssertEqual(contents(field(first + ".points")), "0")
        replace(field(first + ".chargesDrawn"), with: "1")
        capture("Reduce Motion single-player scrolling and keyboard Save")
        tap(app.buttons["Save draft"])
        XCTAssertTrue(text(containing: "Draft saved on this device.").waitForExistence(timeout: 5))
        hideKeyboard()
        tap(app.buttons["Roster table"])
        replace(field(first + ".freeThrowsMissed", axis: .horizontal), with: "1", axis: .horizontal)
        capture("Reduce Motion roster final field and keyboard Save")
        tap(app.buttons["Save draft"])
        XCTAssertTrue(text(containing: "Draft saved on this device.").waitForExistence(timeout: 5))
        hideKeyboard()
        tap(app.navigationBars["Box-score draft"].buttons["Done"])
        tap(app.buttons["View box score"])
        tap(app.buttons["box-score.expand." + first])
        capture("Reduce Motion saved ledger expansion")
    }

    func testApprovedLedgerLandscapeGeometry() throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.activate()
        defer { XCUIDevice.shared.orientation = .portrait; app.activate() }
        XCUIDevice.shared.orientation = .portrait
        let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            settings.frame.height > settings.frame.width
        }, object: settings)
        XCTAssertEqual(XCTWaiter.wait(for: [portrait], timeout: 8), .completed)
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            settings.frame.width > settings.frame.height
        }, object: settings)
        let result = XCTWaiter.wait(for: [landscape], timeout: 8)
        let geometry = XCTAttachment(string: "Settings window: \(settings.frame); requested landscape; device orientation: \(XCUIDevice.shared.orientation.rawValue)")
        geometry.name = "System orientation geometry"; geometry.lifetime = .keepAlways; add(geometry)
        let image = XCTAttachment(screenshot: settings.screenshot())
        image.name = "Actual system rotation baseline"; image.lifetime = .keepAlways; add(image)
        if result != .completed {
            XCUIDevice.shared.orientation = .portrait
            XCUIDevice.shared.press(.home)
            let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            system.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.01))
                .press(forDuration: 0.05, thenDragTo: system.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.65)))
            let controls = XCTAttachment(string: system.debugDescription)
            controls.name = "Rotation-control diagnosis"; controls.lifetime = .keepAlways; add(controls)
            let systemImage = XCTAttachment(screenshot: system.screenshot())
            systemImage.name = "Rotation-control system view"; systemImage.lifetime = .keepAlways; add(systemImage)
        }
        guard result == .completed else {
            throw XCTSkip("System Settings retained portrait geometry after a landscape request; app rotation cannot be accepted")
        }
        app.activate()
        XCUIDevice.shared.orientation = .portrait
        selectTab("Local drafts")
        _ = createGame("actual rotation")
        XCUIDevice.shared.orientation = .landscapeLeft
        let appLandscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.app.frame.width > self.app.frame.height
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [appLandscape], timeout: 8), .completed)
        capture("Actual landscape game ledger geometry")
        tap(app.buttons["Single-player entry"])
        replace(field(first + ".chargesDrawn"), with: "0")
        capture("Actual landscape single-player scrolling and Save")
        tap(app.buttons["Save draft"])
        XCTAssertTrue(text(containing: "Draft saved on this device.").waitForExistence(timeout: 5))
        hideKeyboard()
        tap(app.buttons["Roster table"])
        replace(field(first + ".freeThrowsMissed", axis: .horizontal), with: "0", axis: .horizontal)
        capture("Actual landscape table and final field")
        tap(app.buttons["Save draft"])
        XCTAssertTrue(text(containing: "Draft saved on this device.").waitForExistence(timeout: 5))
        hideKeyboard()
        XCUIDevice.shared.orientation = .portrait
        let appPortrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.app.frame.height > self.app.frame.width
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [appPortrait], timeout: 8), .completed)
        capture("Actual restored portrait table geometry")
    }

    func testApprovedLargeTextRenderedLayout() {
        app.terminate()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); selectTab("Local drafts")
        let game = createGame("maximum notice diagnosis")
        tap(app.buttons["Single-player entry"])
        replace(field(first + ".points"), with: "4")
        replace(field(first + ".threesMade"), with: "7")
        let notice = app.staticTexts["scoring-discrepancy-warning"]
        XCTAssertTrue(notice.exists)
        XCTAssertEqual(notice.label, "Check scoring")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(app.frame.contains(app.buttons["Save draft"].frame))
        capture("Maximum-text keyboard-visible Save")
        // The iPad number pad is a system popup: dismiss it before interacting
        // with the underlying header. Static information needs no activation.
        let hadKeypadPopup = app.otherElements["PopoverDismissRegion"].exists
        dismissKeypadPopup()
        tap(app.buttons["Save draft"])
        XCTAssertTrue(text(containing: "Draft saved on this device.").waitForExistence(timeout: 5))
        if !hadKeypadPopup { XCTAssertTrue(app.keyboards.firstMatch.exists) }
        inspectScrollableScoringNotice(hadKeypadPopup ? "iPad popup dismissed" : "Keyboard visible")
        hideKeyboard()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        inspectScrollableScoringNotice("Keyboard closed")
        replace(field(first + ".points"), with: "4")
        XCTAssertTrue(app.buttons["Save draft"].isEnabled, "Discrepancies remain saveable")
        tap(app.buttons["Save draft"])
        XCTAssertTrue(text(containing: "Draft saved on this device.").waitForExistence(timeout: 5))
        tap(app.navigationBars["Box-score draft"].buttons["Done"])
        app.terminate(); app.launch(); selectTab("Local drafts"); openGame(game)
        tap(app.buttons["Single-player entry"])
        XCTAssertEqual(contents(field(first + ".points")), "4")
        XCTAssertEqual(contents(field(first + ".threesMade")), "7")
    }

    private func inspectScrollableScoringNotice(_ phase: String) {
        let header = app.scrollViews["box-score-entry-header"]
        let parts = [app.staticTexts["scoring-discrepancy-warning"],
                     text(containing: "Entered points and made baskets differ."),
                     text(containing: "Partial lower bound:")]
        XCTAssertTrue(parts.allSatisfy(\.exists))
        XCTAssertTrue(parts[2].label.contains("Temporary Player 1"))
        XCTAssertTrue(parts[2].label.contains("at least 21"))
        func viewport() -> CGRect {
            let frame = header.frame
            let top = max(frame.minY, app.navigationBars["Box-score draft"].frame.maxY)
            return CGRect(x: frame.minX, y: top, width: frame.width, height: frame.maxY - top)
        }
        func pan(up: Bool) {
            let rect = viewport()
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let before = parts[0].frame.minY
            origin.withOffset(CGVector(dx: rect.midX, dy: rect.minY + rect.height * (up ? 0.75 : 0.25)))
                .press(forDuration: 0.05,
                       thenDragTo: origin.withOffset(CGVector(dx: rect.midX, dy: rect.minY + rect.height * (up ? 0.25 : 0.75))),
                       withVelocity: .slow, thenHoldForDuration: 0.2)
            XCTAssertGreaterThan(abs(parts[0].frame.minY - before), 1, "Stop if the header gesture makes no progress")
        }
        for _ in 0..<32 {
            if parts[0].frame.minY >= viewport().minY - 2 { break }
            pan(up: false)
        }
        // Track overlapping visible text bands across native scrolling. A tall
        // static paragraph need not fit in one viewport or have a tap point.
        var coveredThrough = Array(repeating: CGFloat(0), count: parts.count)
        for step in 0..<32 {
            let visible = viewport()
            XCTAssertGreaterThan(visible.height, 20)
            for (index, part) in parts.enumerated() {
                let frame = part.frame
                XCTAssertGreaterThan(frame.width, 0)
                XCTAssertGreaterThan(frame.height, 0)
                XCTAssertGreaterThanOrEqual(frame.minX, visible.minX)
                XCTAssertLessThanOrEqual(frame.maxX, visible.maxX)
                let start = max(0, visible.minY - frame.minY)
                let end = min(frame.height, visible.maxY - frame.minY)
                if end > start, start <= coveredThrough[index] + 2 {
                    coveredThrough[index] = max(coveredThrough[index], end)
                }
            }
            capture("\(phase) scoring text band \(step)")
            if parts.enumerated().allSatisfy({ coveredThrough[$0.offset] >= $0.element.frame.height - 2 }) { return }
            pan(up: true)
        }
        XCTFail("The full scoring notice was not readable through native header scrolling")
    }

    private func dismissKeypadPopup() {
        let popup = app.otherElements["PopoverDismissRegion"]
        guard popup.exists else { return }
        let title = app.navigationBars["Box-score draft"]
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(popup.waitForNonExistence(timeout: 3), "System keypad popup must dismiss without changing the draft")
    }

    func testMaximumTextRosterTraversal() {
        app.terminate()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); selectTab("Local drafts")
        _ = createGame("maximum text roster traversal")
        tap(app.buttons["Whole-roster table entry"])
        capture("Maximum-text first player wrapping")
        for number in 1...5 {
            let name = app.staticTexts["Temporary Player \(number) #\(number)"].firstMatch
            reveal(name)
            XCTAssertTrue(name.isHittable, "Every temporary player's wrapped identity must be reachable")
            capture("Maximum-text roster player \(number) reached")
            let photo = app.buttons["Review photo for Temporary Player \(number)"].firstMatch
            reveal(photo, isInput: true)
            XCTAssertTrue(photo.isHittable)
            capture("Maximum-text player \(number) lower identity and adaptive photo action")
        }
        capture("Maximum-text fifth player wrapping after roster traversal")
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
        XCTAssertTrue(app.frame.contains(app.buttons["Save draft"].frame))
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

    func testLargeTextFieldsAndKeyboardSaveRemainReachable() {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); selectTab("Local drafts")
        let game = createGame("large-text reachability")
        tap(app.buttons["Single-player entry"])
        let fields = ["points", "twosMade", "twosMissed", "threesMade", "threesMissed",
                     "freeThrowsMade", "freeThrowsMissed", "offensiveRebounds", "defensiveRebounds",
                     "assists", "turnovers", "steals", "blocks", "fouls", "chargesDrawn"]
        for name in fields {
            let input = field("\(first).\(name)")
            XCTAssertTrue(input.isHittable)
            XCTAssertLessThanOrEqual(input.frame.width, app.frame.width)
        }
        replace(field("\(first).chargesDrawn"), with: "0")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(app.frame.contains(app.buttons["Save draft"].frame))
        capture("Large-text last field and keyboard-visible Save")
        tap(app.buttons["Save draft"])
        XCTAssertTrue(text(containing: "Draft saved on this device.").waitForExistence(timeout: 5))
        if app.keyboards.firstMatch.exists { hideKeyboard() }
        tap(app.navigationBars["Box-score draft"].buttons["Done"])
        app.terminate(); app.launch(); openGame(game)
        tap(app.buttons["Single-player entry"])
        // Search the long accessibility-size form in its actual field order,
        // rather than treating the final row as a nearby offscreen control.
        for name in fields { _ = field("\(first).\(name)") }
        XCTAssertEqual(contents(field("\(first).chargesDrawn")), "0")
        capture("Large-text saved value after relaunch")
    }

    func testGamePresentationGuideAndExportCancellation() {
        _ = createGame("presentation")
        capture("Native game identity and entry actions")
        tap(app.buttons["Single-player entry"])
        capture("Native grouped scoring and missing inputs")
        tap(app.buttons["Done"])
        tap(app.navigationBars["Game"].buttons["Local games"])
        capture("Native local game list")
        tap(app.buttons["Using TeamStats"])
        XCTAssertTrue(app.navigationBars["Using TeamStats"].exists)
        capture("Revisitable native guide")
        XCTAssertFalse(app.buttons["Cancel"].exists)
        tap(app.buttons["Export saved local drafts"])
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 10))
        capture("User-directed JSON export picker")
        app.buttons["Cancel"].tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["Cancel"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        XCTAssertTrue(app.navigationBars["Using TeamStats"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Export saved local drafts"].isHittable)
        XCTAssertFalse(text(containing: "Saved local-draft copy").exists)
        capture("Guide after export cancellation")
    }

    func testPreviouslySavedSyntheticGamePresentation() throws {
        guard let raw = ProcessInfo.processInfo.environment["TEAMSTATS_CONNECTED_UI_FIXTURE"],
              let fixture = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              let game = fixture["localGameOpponent"] as? String, game.hasPrefix("TEST ONLY") else {
            throw XCTSkip("An existing synthetic game must be named explicitly")
        }
        let row = app.staticTexts[game].firstMatch
        for _ in 0..<30 {
            if row.exists && row.isHittable { break }
            app.collectionViews.firstMatch.swipeUp()
        }
        openGame(game)
        capture("Previously saved synthetic game details")
        tap(app.buttons["Single-player entry"])
        capture("Previously saved synthetic individual entry")
        tap(app.buttons["Roster table"])
        capture("Previously saved synthetic roster table")
        tap(app.buttons["Done"])
        tap(app.buttons["Local game summary"])
        capture("Previously saved synthetic summary")
        // This journey never types or saves: the selected record remains unchanged.
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
        XCTAssertTrue(app.frame.contains(app.buttons["Save draft"].frame))
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

    private func reveal(_ element: XCUIElement, axis: Axis = .vertical, isInput: Bool = false,
                        file: StaticString = #filePath, line: UInt = #line) {
        let table = app.scrollViews["box-score-roster-table"]
        if axis == .horizontal, table.exists {
            for _ in 0..<28 {
                let viewport = table.frame
                let identityEnd = table.staticTexts["Temporary Player 1 #1"].frame.maxX + 4
                let target = element.frame
                if isInput, target.minX >= identityEnd, target.maxX <= viewport.maxX, element.isHittable { return }
                if !isInput, target.midX >= identityEnd, target.midX <= viewport.maxX { return }
                // Anchor to this editor's header, never the saved viewer behind
                // its sheet. Traverse the available viewport, not a short label.
                let heading = table.staticTexts["Player"].firstMatch.frame
                let left = identityEnd + 8
                let right = viewport.maxX - 16
                guard right - left >= 44, viewport.contains(CGPoint(x: right, y: heading.midY)) else { break }
                let towardStart = target.minX < identityEnd
                let origin = app.coordinate(withNormalizedOffset: .zero)
                origin.withOffset(CGVector(dx: towardStart ? left : right, dy: heading.midY))
                    .press(forDuration: 0.05,
                           thenDragTo: origin.withOffset(CGVector(dx: towardStart ? right : left, dy: heading.midY)),
                           withVelocity: .slow, thenHoldForDuration: 0)
                if abs(element.frame.minX - target.minX) < 1 { break }
            }
            XCTFail("Native editor header did not reveal the requested column", file: file, line: line)
            return
        }
        for attempt in 0..<12 {
            if element.exists && element.isHittable {
                if !isInput { return }
                let keyboardTop = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : app.frame.maxY
                let save = app.buttons["Save draft"]
                let footer = app.otherElements["local-draft-save-controls"].firstMatch
                let footerTop = footer.exists ? footer.frame.minY : save.exists && save.isHittable ? save.frame.minY : app.frame.maxY
                let bottom = min(keyboardTop, footerTop)
                let playerForm = app.scrollViews["box-score-player-form"]
                let formTop = playerForm.exists ? playerForm.frame.minY :
                    app.collectionViews.allElementsBoundByIndex.last?.frame.minY ?? 0
                let rect = element.frame
                // A partly visible field is hittable, but its trailing typing point
                // can lie outside an iPad sheet. Use that sheet's actual viewport.
                let navigation = app.navigationBars.allElementsBoundByIndex.last?.frame ?? app.frame
                if rect.minY >= formTop && rect.maxY <= bottom && rect.minX >= navigation.minX && rect.maxX <= navigation.maxX { return }
            }
            let containers = app.collectionViews.allElementsBoundByIndex + app.scrollViews.allElementsBoundByIndex
            // A lazy Form may not expose its offscreen fields yet. Prefer its collection
            // without querying the identity/frame of a virtualized offscreen row.
            let playerForm = app.scrollViews["box-score-player-form"]
            let header = app.scrollViews["box-score-entry-header"]
            let inHeader = element.exists && header.exists && !element.identifier.isEmpty &&
                header.descendants(matching: .any).matching(identifier: element.identifier).count > 0
            let fallback = axis != .horizontal && inHeader ? header :
                axis != .horizontal && playerForm.exists ? playerForm :
                axis != .horizontal ? app.collectionViews.allElementsBoundByIndex.last(where: { $0.isHittable }) : nil
            let surface: XCUIElement = fallback ?? containers.last(where: { $0.isHittable }) ?? app
            let navigation = app.navigationBars.allElementsBoundByIndex.last?.frame ?? app.frame
            let viewport = CGRect(x: navigation.minX, y: app.frame.minY,
                                  width: navigation.width, height: app.frame.height)
            let rect = surface.frame.intersection(viewport)
            let keyboardTop = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : app.frame.maxY
            let save = app.buttons["Save draft"]
            let footer = app.otherElements["local-draft-save-controls"].firstMatch
            let footerTop = footer.exists ? footer.frame.minY : save.exists && save.isHittable ? save.frame.minY : app.frame.maxY
            let tabs = app.tabBars.firstMatch
            let bottom = min(rect.maxY, keyboardTop, footerTop, tabs.exists && tabs.isHittable ? tabs.frame.minY : app.frame.maxY) - 16
            let navigationBottom = app.navigationBars.allElementsBoundByIndex.last?.frame.maxY ?? 0
            let top = max(rect.minY, navigationBottom) + 16
            let origin = app.coordinate(withNormalizedOffset: .zero)
            if axis == .horizontal {
                let delta = element.exists ? element.frame.minX - rect.midX : 0
                let rightward = element.exists ? delta < 0 : attempt >= 10
                let distance = element.exists ? min(abs(delta), rect.width - 40) : rect.width - 40
                // Column headings belong to the same native horizontal scroller;
                // do not start a pan inside an editable text field's selection area.
                let heading = app.staticTexts["Player"].firstMatch
                let y = heading.exists && heading.isHittable ? heading.frame.midY : (top + bottom) / 2
                let start = origin.withOffset(CGVector(dx: rightward ? rect.minX + 20 : rect.maxX - 20, dy: y))
                let end = origin.withOffset(CGVector(dx: rightward ? rect.minX + 20 + distance : rect.maxX - 20 - distance, dy: y))
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
            } else {
                let downward: Bool
                if element.exists && element.frame.minY < top {
                    downward = true
                } else if element.exists && element.frame.maxY > bottom {
                    downward = false
                } else {
                    downward = axis == .verticalUp ? attempt < 6 : attempt >= 6
                }
                // Collection frames extend under the software keyboard; drag only in
                // their visible viewport, never across keyboard keys or Save.
                let start = origin.withOffset(CGVector(dx: rect.midX, dy: downward ? top : bottom))
                // Short drags protect an active field; ordinary navigation can span
                // several screens at maximum text size and needs a full viewport search.
                let available = (bottom - top) * 0.85
                let distance = isInput && app.keyboards.firstMatch.exists ? min(100, available) : available
                let end = origin.withOffset(CGVector(dx: rect.midX, dy: downward ? top + distance : bottom - distance))
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
            }
        }
        XCTFail("Requested control is not reachable after bounded native scrolling", file: file, line: line)
    }

    private func tap(_ element: XCUIElement, axis: Axis = .vertical) {
        if element.label == "Save draft", element.isEnabled, app.frame.contains(element.frame) {
            dismissKeypadPopup()
            // Use the visible control; the caller must still verify an actual save receipt.
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return
        }
        reveal(element, axis: axis); element.tap()
    }

    private func field(_ id: String, axis: Axis = .vertical) -> XCUIElement {
        if app.keyboards.firstMatch.exists { hideKeyboard() }
        let element = app.textFields[id]
        reveal(element, axis: id.hasSuffix(".points") && axis == .vertical ? .verticalUp : axis, isInput: true)
        return element
    }

    private func contents(_ field: XCUIElement) -> String {
        let value = field.value as? String ?? ""
        return ["Not entered", "Unentered"].contains(value) ? "" : value
    }

    private func hideKeyboard() {
        // iPhone exposes the app's keyboard Done; iPad also has Hide keyboard.
        // Exclude navigation Done, which closes the editor rather than the keyboard.
        let navigationFrames = app.navigationBars.allElementsBoundByIndex.map(\.frame)
        let actions = app.buttons.matching(identifier: "Hide keyboard").allElementsBoundByIndex +
            app.buttons.matching(identifier: "Done").allElementsBoundByIndex
        guard let action = actions.first(where: { candidate in
            candidate.isEnabled && app.frame.contains(candidate.frame) &&
                !navigationFrames.contains(where: { $0.intersects(candidate.frame) })
        }) else {
            XCTFail("No visible keyboard dismissal action"); return
        }
        // iPad's floating number pad marks the visible keyboard toolbar unhittable.
        action.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func replace(_ field: XCUIElement, with value: String, axis: Axis = .vertical) {
        if app.keyboards.firstMatch.exists {
            hideKeyboard()
        }
        reveal(field, axis: axis, isInput: true)
        // LabeledContent can stack its label above the input at accessibility sizes.
        // The retained maximum-text snapshot's midpoint hit its label, not the input.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.85)).tap()
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
        reveal(app.buttons["Single-player entry"])
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
