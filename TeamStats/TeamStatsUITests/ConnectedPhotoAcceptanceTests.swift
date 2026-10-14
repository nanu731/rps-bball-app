import XCTest
import Foundation

/// One actual photo/recognition/review Cancel and Apply journey. Root supplies an observed
/// unique synthetic asset label; no guessed asset selection, stat Save or deletion.
@MainActor
final class ConnectedPhotoAcceptanceTests: XCTestCase {
    private var app: XCUIApplication!
    private var mayCaptureApp = true
    private let player = "temporary-roster-v1-a"

    override func tearDownWithError() throws {
        guard app != nil else { return }
        if (testRun?.failureCount ?? 0) > 0 && mayCaptureApp {
            capture("Photo Cancel failure")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Photo failure hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        // Only the isolated process ends. Unsaved values are never persisted;
        // the synthetic Photos asset and every saved record remain in place.
        app.terminate()
    }

    func testObserveSyntheticPhotoPickerLabel() throws {
        guard let raw = ProcessInfo.processInfo.environment["TEAMSTATS_UI_PHOTO_FIXTURE"] else {
            throw XCTSkip("Explicit synthetic game fixture required")
        }
        let fixture = try JSONDecoder().decode(PhotoUIFixture.self, from: Data(raw.utf8))
        guard fixture.gameOpponent.hasPrefix("TEST ONLY"), fixture.recognizedLine == "7" else {
            throw PhotoUIIssue.unsafeFixture
        }
        app = XCUIApplication(bundleIdentifier: "com.narayanlekhi.TeamStats.UIAcceptance")
        app.terminate(); app.launch()
        try openPaintDraft(fixture.gameOpponent)
        try tap(app.buttons.matching(identifier: "Review photo for this player").firstMatch)
        mayCaptureApp = false
        try tap(app.buttons["Choose photo"])
        let images = app.images.matching(NSPredicate(format: "label CONTAINS %@", "2037"))
        guard images.firstMatch.waitForExistence(timeout: 15), images.count == 1 else {
            throw XCTSkip("Imported synthetic future-dated image has no unique observed label; no photo selected")
        }
        let label = XCTAttachment(string: images.firstMatch.label)
        label.name = "Observed synthetic photo asset label"; label.lifetime = .keepAlways; add(label)
        // Observe only. A separate guarded journey selects the confirmed image.
    }

    func testActualPhotoCancelAndApplyRemainUnsaved() throws {
        guard let raw = ProcessInfo.processInfo.environment["TEAMSTATS_UI_PHOTO_FIXTURE"] else {
            throw XCTSkip("Root must add the synthetic image and provide its observed unique Photos picker label")
        }
        let fixture = try JSONDecoder().decode(PhotoUIFixture.self, from: Data(raw.utf8))
        guard fixture.gameOpponent.hasPrefix("TEST ONLY"), fixture.recognizedLine == "7",
              !fixture.pickerAssetLabel.isEmpty, !fixture.pickerAssetLabel.contains("TODO") else {
            throw PhotoUIIssue.unsafeFixture
        }
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.narayanlekhi.TeamStats.UIAcceptance")
        app.terminate(); app.launch()
        try openPaintDraft(fixture.gameOpponent)
        let count = app.textFields["paint-touches.\(player)"]
        try reveal(count)
        let saved = contents(count)
        guard saved != "7" else {
            throw XCTSkip("Use an existing TEST ONLY game whose saved paint value differs from7 to prove Apply does not auto-save")
        }
        let unsaved = saved == "5" ? "6" : "5"
        try replace(count, with: unsaved)
        let hide = app.buttons.matching(identifier: "Hide keyboard").allElementsBoundByIndex.first(where: { $0.isHittable })
        if let hide { hide.tap() }
        try prepareReviewedPhoto(fixture)
        try tap(app.navigationBars["Review photo"].buttons["Cancel"])
        let discard = app.alerts["Discard photo review?"]
        try require(discard)
        XCTAssertTrue(discard.buttons["Keep editing"].exists)
        try tap(discard.buttons["Discard reviewed proposals"])
        try require(app.navigationBars["Player paint touches"])
        XCTAssertEqual(contents(count), unsaved, "Cancel must retain the existing unsaved entry value")
        XCTAssertTrue(app.staticTexts["Unsaved changes"].exists)
        capture("Photo Cancel preserves the unsaved paint draft")
        try prepareReviewedPhoto(fixture)
        try tap(app.buttons["photoReview.apply"])
        try require(app.navigationBars["Player paint touches"])
        XCTAssertEqual(contents(count), "7", "Apply changes only the current draft buffer")
        XCTAssertTrue(app.staticTexts["Unsaved changes"].exists)
        capture("Actual reviewed photo Apply remains an unsaved draft")
        app.terminate(); app.launch()
        try openPaintDraft(fixture.gameOpponent)
        XCTAssertEqual(contents(app.textFields["paint-touches.\(player)"]), saved,
                       "Neither Cancel nor Apply may auto-save statistics")
        capture("Saved paint value remains unchanged after cold reopen")
    }

    private func prepareReviewedPhoto(_ fixture: PhotoUIFixture) throws {
        try tap(app.buttons.matching(identifier: "Review photo for this player").firstMatch)
        try require(app.navigationBars["Review photo"])
        try require(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@",
            fixture.gameOpponent, "Temporary Player 1")).firstMatch)
        mayCaptureApp = false // Do not capture an unverified shared Photos library.
        try tap(app.buttons["Choose photo"])
        let assets = app.images.matching(identifier: fixture.pickerAssetLabel)
        guard assets.firstMatch.waitForExistence(timeout: 10), assets.count == 1 else {
            throw XCTSkip("No unique synthetic asset matches the root-observed Photos image label; do not select another photo")
        }
        guard assets.firstMatch.isHittable else {
            throw XCTSkip("Root-observed synthetic asset is not currently visible; do not scroll/select unknown photos")
        }
        assets.firstMatch.tap()
        let add = app.buttons.matching(identifier: "Add").allElementsBoundByIndex.first(where: { $0.isHittable })
        if let add { add.tap() }
        try require(app.navigationBars["Review photo"])
        let recognized = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@",
            fixture.recognizedLine, "Review a value from this line")).firstMatch
        guard recognized.waitForExistence(timeout: 30), recognized.isHittable else {
            throw XCTSkip("Synthetic photo selection/OCR did not expose its expected count; Cancel/Apply acceptance remains unverified")
        }
        mayCaptureApp = true
        capture("Actual device recognized synthetic standalone count")
        try tap(recognized)
        let apply = app.buttons["photoReview.apply"]
        try reveal(apply)
        XCTAssertFalse(apply.isEnabled, "An unmapped/unconfirmed proposal must not apply")
        let fieldPicker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Existing field")).firstMatch
        try tap(fieldPicker)
        try tap(app.buttons["Game-total paint touches"])
        let reviewed = app.textFields["Reviewed value for Game-total paint touches"]
        try require(reviewed)
        XCTAssertEqual(contents(reviewed), "7")
        let confirmation = app.switches["I checked this field and value against the photo"]
        try tap(confirmation)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: apply)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        capture("Reviewed mapping is confirmed but not applied")
    }

    private func openPaintDraft(_ opponent: String) throws {
        let tab = app.buttons["Local drafts"].firstMatch
        if !tab.exists, app.buttons["Next Page"].exists { app.buttons["Next Page"].tap() }
        try tap(tab)
        try tap(app.staticTexts[opponent].firstMatch)
        try tap(app.buttons["Player paint-touch drafts"])
        try require(app.navigationBars["Player paint touches"])
    }
    private func contents(_ field: XCUIElement) -> String {
        let value = field.value as? String ?? ""
        return ["Unentered", "Not entered"].contains(value) ? "" : value
    }
    private func replace(_ field: XCUIElement, with value: String) throws {
        try reveal(field)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let prior = contents(field)
        if !prior.isEmpty { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: prior.count)) }
        field.typeText(value)
        XCTAssertEqual(contents(field), value)
    }
    private func require(_ element: XCUIElement, timeout: TimeInterval = 15) throws {
        guard element.waitForExistence(timeout: timeout) else { throw PhotoUIIssue.missingControl }
    }
    private func reveal(_ element: XCUIElement) throws {
        for attempt in 0..<10 {
            let footer = app.otherElements["local-draft-save-controls"].firstMatch
            let footerTop = footer.exists ? footer.frame.minY : app.frame.maxY
            if element.exists && element.isHittable {
                if element.elementType != .textField || element.frame.maxY <= footerTop { return }
            }
            let paintBar = app.navigationBars["Player paint touches"]
            let paint = paintBar.exists && paintBar.isHittable
                ? app.scrollViews.allElementsBoundByIndex.last(where: { $0.isHittable }) : nil
            let surface = paint ?? app.collectionViews.allElementsBoundByIndex.last(where: { $0.isHittable })
                ?? app.scrollViews.allElementsBoundByIndex.last(where: { $0.isHittable }) ?? app!
            let top = max(surface.frame.minY, app.navigationBars.allElementsBoundByIndex.last?.frame.maxY ?? 0) + 24
            let tabs = app.tabBars.firstMatch
            let bottom = min(surface.frame.maxY,
                app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : app.frame.maxY,
                footerTop, tabs.exists && tabs.frame.minY > top ? tabs.frame.minY : app.frame.maxY) - 24
            guard bottom > top else { throw PhotoUIIssue.missingControl }
            let down = element.exists ? element.frame.midY < top : attempt >= 5
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: surface.frame.midX, dy: down ? top : bottom))
            let end = origin.withOffset(CGVector(dx: surface.frame.midX, dy: down ? bottom : top))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
        }
        if mayCaptureApp {
            capture("Unreachable photo-flow control")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Photo-flow control hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        throw PhotoUIIssue.missingControl
    }
    private func tap(_ element: XCUIElement) throws { try reveal(element); element.tap() }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
private struct PhotoUIFixture: Decodable {
    let gameOpponent: String
    let pickerAssetLabel: String
    let recognizedLine: String
}
private enum PhotoUIIssue: Error { case unsafeFixture, missingControl }
