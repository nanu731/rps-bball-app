import XCTest
@testable import TeamStats

@MainActor final class ShotCaptureTests: XCTestCase {
    func testMixedFreeThrowsStayPendingThenPersistOneMakeAndOneMiss() throws {
        let player = ShotCapturePlayer(id: "TEST-temporary-player", name: "TEST ONLY player", number: "90", temporary: true)
        var capture = try ShotCaptureDocument.local(gameID: UUID(), players: [player])
        let series = try capture.startFreeThrows(team: .our, playerID: player.id, attempts: 2)
        XCTAssertEqual(try capture.totals(team: .our).pending, 2)
        XCTAssertEqual(try capture.totals(team: .our).missedFreeThrows, 0)
        try capture.answerFreeThrow(seriesID: series, index: 1, outcome: .made)
        try capture.answerFreeThrow(seriesID: series, index: 2, outcome: .missed)
        let totals = try capture.totals(team: .our)
        XCTAssertEqual(totals.madeFreeThrows, 1)
        XCTAssertEqual(totals.missedFreeThrows, 1)
        XCTAssertEqual(totals.pending, 0)
        XCTAssertEqual(totals.points, 1)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TEST-shot-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let file = folder.appendingPathComponent("capture.json")
        try ShotCaptureStorage.create(capture, at: file)
        let reopened = try ShotCaptureStorage.load(from: file, context: capture.context)
        XCTAssertEqual(reopened, capture)
        XCTAssertEqual(try reopened.events().first?.id, series)
    }
    func testFieldGoalAttributionCorrectionsAndRepeatedUndoKeepHistory() throws {
        let player = ShotCapturePlayer(id: "TEST-local", name: "TEST ONLY", number: "91", temporary: true)
        var capture = try ShotCaptureDocument.local(gameID: UUID(), players: [player])
        let shotID = try capture.startFieldGoal(team: .our, playerID: player.id,
            location: ShotLocation(x: 0.2, y: 0.7), basket: .top)
        XCTAssertEqual(try capture.totals(team: .our).pending, 1)
        var shot = try XCTUnwrap(capture.events().first)
        shot.value = 3; shot.outcome = .made
        try capture.correct(shot)
        _ = try capture.startFreeThrows(team: .opponent, playerID: nil, attempts: 2)
        XCTAssertEqual(try capture.totals(team: .our).points, 3)
        XCTAssertEqual(try capture.totals(team: .opponent).pending, 2)
        try capture.undo()
        XCTAssertEqual(try capture.events().map(\.id), [shotID])
        try capture.undo()
        XCTAssertEqual(try capture.totals(team: .our).points, 0)
        XCTAssertEqual(try capture.totals(team: .our).pending, 1)
        try capture.undo()
        XCTAssertTrue(try capture.events().isEmpty)
        XCTAssertEqual(capture.journal.count, 6)
        XCTAssertEqual(capture.journal.compactMap(\.undoOf).count, 3)
        XCTAssertThrowsError(try capture.undo())
    }

    func testCourtCoordinatesRoundTripAcrossDisplaySizesWithoutChangingBasketOrigin() throws {
        let transform = ShotCourtTransform(flipped: true)
        let canonical = ShotLocation(x: 0.2, y: 0.7)
        let displayed = transform.display(canonical)
        XCTAssertEqual(displayed.x, 0.8, accuracy: 0.000001)
        XCTAssertEqual(displayed.y, 0.3, accuracy: 0.000001)
        for size in [(400.0, 800.0), (1000.0, 500.0)] {
            let reopened = try transform.capture(x: displayed.x * size.0, y: displayed.y * size.1, width: size.0, height: size.1)
            XCTAssertEqual(reopened.x, canonical.x, accuracy: 0.000001)
            XCTAssertEqual(reopened.y, canonical.y, accuracy: 0.000001)
        }
        let attackingBottom = ShotCourtTransform.attackRelative(canonical, basket: .bottom)
        XCTAssertEqual(attackingBottom.x, 0.8, accuracy: 0.000001)
        XCTAssertEqual(attackingBottom.y, 0.3, accuracy: 0.000001)
        XCTAssertThrowsError(try transform.capture(x: 1, y: 1, width: 0, height: 10))
        XCTAssertThrowsError(try transform.capture(x: .infinity, y: 1, width: 100, height: 100))
        XCTAssertThrowsError(try transform.capture(x: -1, y: 1, width: 100, height: 100))
    }

    func testStaleOrRewrittenHistoryCannotReplaceSavedCapture() throws {
        let player = ShotCapturePlayer(id: "TEST-storage", name: "TEST ONLY storage", number: "92", temporary: true)
        var capture = try ShotCaptureDocument.local(gameID: UUID(), players: [player])
        let series = try capture.startFreeThrows(team: .our, playerID: player.id, attempts: 2)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TEST-shot-history-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let url = folder.appendingPathComponent("capture.json")
        try ShotCaptureStorage.create(capture, at: url)
        var stale = capture
        try capture.answerFreeThrow(seriesID: series, index: 1, outcome: .made)
        try ShotCaptureStorage.save(capture, to: url, expectedRevision: 1)
        let durable = try Data(contentsOf: url)
        try stale.answerFreeThrow(seriesID: series, index: 1, outcome: .missed)
        XCTAssertThrowsError(try ShotCaptureStorage.save(stale, to: url, expectedRevision: 1))
        XCTAssertEqual(try Data(contentsOf: url), durable)
        try capture.answerFreeThrow(seriesID: series, index: 2, outcome: .missed)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(capture)) as? [String: Any])
        var journal = try XCTUnwrap(object["journal"] as? [[String: Any]])
        journal[0]["recordedAt"] = "2037-01-01T00:00:00Z"; object["journal"] = journal
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let rewritten = try decoder.decode(ShotCaptureDocument.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNoThrow(try rewritten.validate()) // Self-consistent, but changes an already-saved fact.
        XCTAssertThrowsError(try ShotCaptureStorage.save(rewritten, to: url, expectedRevision: 2))
        XCTAssertEqual(try Data(contentsOf: url), durable)
        try ShotCaptureStorage.save(capture, to: url, expectedRevision: 2)
        try ShotCaptureStorage.save(capture, to: url, expectedRevision: 2) // Uncertain receipt: identical change is safe.
        XCTAssertEqual(try ShotCaptureStorage.load(from: url, context: capture.context), capture)
    }

    func testExtremeCountsStaySparseAndInvalidCorrectionsLeaveDraftUntouched() throws {
        let player = ShotCapturePlayer(id: "TEST-counts", name: "TEST ONLY counts", number: "93", temporary: true)
        var capture = try ShotCaptureDocument.local(gameID: UUID(), players: [player])
        for count in [0, -1, Int.max] {
            let before = capture
            XCTAssertThrowsError(try capture.startFreeThrows(team: .our, playerID: player.id, attempts: count))
            XCTAssertEqual(capture, before)
        }
        let series = try capture.startFreeThrows(team: .opponent, playerID: nil, attempts: 2_147_483_647)
        XCTAssertEqual(try capture.events().first?.answers.count, 0)
        XCTAssertEqual(try capture.totals(team: .opponent).pending, 2_147_483_647)
        try capture.answerFreeThrow(seriesID: series, index: 2_147_483_647, outcome: .made)
        XCTAssertEqual(try capture.totals(team: .opponent).pending, 2_147_483_646)
        XCTAssertEqual(try capture.totals(team: .opponent).points, 1)
        var event = try XCTUnwrap(capture.events().first)
        event.freeThrowAttempts = 2
        let before = capture
        XCTAssertThrowsError(try capture.correct(event)) // Never silently drop answered indices.
        XCTAssertEqual(capture, before)
        XCTAssertThrowsError(try capture.answerFreeThrow(seriesID: series, index: 0, outcome: .missed))
        XCTAssertThrowsError(try capture.startFieldGoal(team: .our, playerID: "not-rostered", location: ShotLocation(x: 0.5, y: 0.5), basket: .top))
        XCTAssertThrowsError(try capture.startFieldGoal(team: .opponent, playerID: player.id, location: ShotLocation(x: 0.5, y: 0.5), basket: .top))
        XCTAssertThrowsError(try capture.startFieldGoal(team: .our, playerID: player.id, location: ShotLocation(x: .nan, y: 0), basket: .top))
        XCTAssertEqual(capture, before)
    }

    func testRepeatedAnswerDoesNotCreateAnotherChangeOrAttempt() throws {
        var capture = try ShotCaptureDocument.local(gameID: UUID(), players: [])
        let series = try capture.startFreeThrows(team: .opponent, playerID: nil, attempts: 2)
        try capture.answerFreeThrow(seriesID: series, index: 1, outcome: .made)
        let saved = capture
        try capture.answerFreeThrow(seriesID: series, index: 1, outcome: .made)
        XCTAssertEqual(capture, saved)
        try capture.answerFreeThrow(seriesID: series, index: 1, outcome: nil)
        XCTAssertEqual(try capture.totals(team: .opponent).pending, 2)
        XCTAssertEqual(try capture.totals(team: .opponent).madeFreeThrows, 0)
        let unanswered = capture
        try capture.answerFreeThrow(seriesID: series, index: 1, outcome: nil)
        XCTAssertEqual(capture, unanswered)
    }

    func testFailedSaveRetainsPendingIdentityAndRetryDoesNotDuplicate() async throws {
        let document = try ShotCaptureDocument.local(gameID: UUID(), players: [])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TEST-shot-retry-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let url = folder.appendingPathComponent("capture.json")
        try ShotCaptureStorage.create(document, at: url)
        var fail = true
        var submittedChanges: [UUID] = []
        let recorder = try ShotCaptureRecorder(document: document, url: url, save: { candidate, destination, revision in
            submittedChanges.append(try XCTUnwrap(candidate.journal.last?.id))
            if fail { throw CocoaError(.fileWriteOutOfSpace) }
            try await ShotCaptureDisk.shared.save(candidate, to: destination, expectedRevision: revision)
        })
        await recorder.change { _ = try $0.startFreeThrows(team: .opponent, playerID: nil, attempts: 2) }
        XCTAssertTrue(recorder.needsSave)
        XCTAssertNotNil(recorder.issue)
        let pendingID = try XCTUnwrap(recorder.visibleDocument?.events().first?.id)
        XCTAssertEqual(try ShotCaptureStorage.load(from: url, context: document.context).revision, 0)
        await recorder.change { _ = try $0.startFreeThrows(team: .opponent, playerID: nil, attempts: 3) }
        XCTAssertEqual(submittedChanges.count, 1) // Resolve the first uncertain change before accepting another.
        fail = false
        await recorder.retrySave()
        XCTAssertFalse(recorder.needsSave)
        XCTAssertNil(recorder.issue)
        XCTAssertEqual(submittedChanges.count, 2)
        XCTAssertEqual(submittedChanges.first, submittedChanges.last)
        let recovered = try ShotCaptureStorage.load(from: url, context: document.context)
        XCTAssertEqual(try recovered.events().map(\.id), [pendingID])
        XCTAssertEqual(recovered.revision, 1)
    }

    func testCancellationAfterAtomicWriteRequiresSameChangeReadback() async throws {
        let document = try ShotCaptureDocument.local(gameID: UUID(), players: [])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TEST-shot-cancel-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let url = folder.appendingPathComponent("capture.json")
        try ShotCaptureStorage.create(document, at: url)
        let started = AsyncStream<Void>.makeStream()
        var release: CheckedContinuation<Void, Never>?
        var writes = 0
        let recorder = try ShotCaptureRecorder(document: document, url: url, save: { candidate, destination, revision in
            writes += 1
            try await ShotCaptureDisk.shared.save(candidate, to: destination, expectedRevision: revision)
            if writes == 1 {
                started.continuation.yield(()); started.continuation.finish()
                await withCheckedContinuation { release = $0 }
            }
        })
        let task = Task { await recorder.change { _ = try $0.startFreeThrows(team: .opponent, playerID: nil, attempts: 2) } }
        for await _ in started.stream { break }
        XCTAssertTrue(recorder.isBusy)
        await recorder.change { _ = try $0.startFreeThrows(team: .opponent, playerID: nil, attempts: 3) }
        XCTAssertEqual(writes, 1)
        task.cancel(); release?.resume(); await task.value
        XCTAssertTrue(recorder.needsSave)
        XCTAssertEqual(recorder.savedRevision, 0)
        XCTAssertNotNil(recorder.issue)
        let committed = try ShotCaptureStorage.load(from: url, context: document.context)
        XCTAssertEqual(committed.revision, 1)
        await recorder.retrySave()
        XCTAssertFalse(recorder.needsSave)
        XCTAssertEqual(recorder.visibleDocument, committed)
        XCTAssertEqual(try ShotCaptureStorage.load(from: url, context: document.context), committed)
    }

    func testChangedAccountContextConcealsLateSaveAndPreventsAnotherWrite() async throws {
        let document = try ShotCaptureDocument.local(gameID: UUID(), players: [])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TEST-shot-context-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let url = folder.appendingPathComponent("capture.json")
        try ShotCaptureStorage.create(document, at: url)
        let started = AsyncStream<Void>.makeStream()
        var release: CheckedContinuation<Void, Never>?
        var current = true
        var writes = 0
        let recorder = try ShotCaptureRecorder(document: document, url: url, save: { candidate, destination, revision in
            writes += 1
            try await ShotCaptureDisk.shared.save(candidate, to: destination, expectedRevision: revision)
            started.continuation.yield(()); started.continuation.finish()
            await withCheckedContinuation { release = $0 }
        }, isCurrentContext: { current })
        let task = Task { await recorder.change { _ = try $0.startFreeThrows(team: .opponent, playerID: nil, attempts: 1) } }
        for await _ in started.stream { break }
        current = false
        XCTAssertNil(recorder.visibleDocument)
        release?.resume(); await task.value
        XCTAssertNil(recorder.visibleDocument)
        XCTAssertNil(recorder.savedRevision)
        XCTAssertFalse(recorder.canChange)
        await recorder.retrySave()
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(try ShotCaptureStorage.load(from: url, context: document.context).revision, 1)
    }

    func testCorruptionFutureSchemaAndWrongScopeNeverBecomeAnEmptyCapture() throws {
        var document = try ShotCaptureDocument.local(gameID: UUID(), players: [])
        let series = try document.startFreeThrows(team: .opponent, playerID: nil, attempts: 2)
        try document.answerFreeThrow(seriesID: series, index: 1, outcome: .made)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TEST-shot-recovery-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let url = folder.appendingPathComponent("original.json")
        try ShotCaptureStorage.create(document, at: url)
        let original = try Data(contentsOf: url)
        let copy = folder.appendingPathComponent("restored.json")
        try FileManager.default.copyItem(at: url, to: copy)
        XCTAssertEqual(try ShotCaptureStorage.load(from: copy, context: document.context), document)
        XCTAssertEqual(try document.totals(team: .opponent).pending, 1)
        XCTAssertThrowsError(try ShotCaptureStorage.create(document, at: url))
        let wrongScope = ShotCaptureContext(gameID: UUID(), teamID: nil, actorID: nil, assignmentRevision: nil)
        XCTAssertThrowsError(try ShotCaptureStorage.load(from: url, context: wrongScope))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        var future = object; future["schemaVersion"] = 2
        var duplicate = object
        var changes = try XCTUnwrap(duplicate["journal"] as? [[String: Any]])
        changes[1]["id"] = changes[0]["id"]; duplicate["journal"] = changes
        for (index, candidate) in [future, duplicate].enumerated() {
            let file = folder.appendingPathComponent("invalid-\(index).json")
            let data = try JSONSerialization.data(withJSONObject: candidate)
            try data.write(to: file)
            XCTAssertThrowsError(try ShotCaptureStorage.load(from: file, context: document.context))
            XCTAssertEqual(try Data(contentsOf: file), data)
        }
        let tooLarge = folder.appendingPathComponent("too-large.json")
        try Data(repeating: 32, count: ShotCaptureStorage.maximumBytes + 1).write(to: tooLarge)
        XCTAssertThrowsError(try ShotCaptureStorage.load(from: tooLarge, context: document.context)) {
            XCTAssertEqual($0 as? ShotCaptureIssue, .limit)
        }
        let link = folder.appendingPathComponent("linked.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        XCTAssertThrowsError(try ShotCaptureStorage.load(from: link, context: document.context))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testConcurrentControllersCannotOverwriteEachOthersChanges() async throws {
        let document = try ShotCaptureDocument.local(gameID: UUID(), players: [])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TEST-shot-concurrent-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let url = folder.appendingPathComponent("capture.json")
        try await ShotCaptureDisk.shared.create(document, at: url)
        let first = try ShotCaptureRecorder(document: document, url: url)
        let second = try ShotCaptureRecorder(document: document, url: url)
        async let one: Void = first.change { _ = try $0.startFreeThrows(team: .opponent, playerID: nil, attempts: 1) }
        async let two: Void = second.change { _ = try $0.startFreeThrows(team: .opponent, playerID: nil, attempts: 2) }
        _ = await (one, two)
        XCTAssertEqual([first, second].filter { $0.needsSave }.count, 1)
        XCTAssertEqual([first, second].filter { $0.issue != nil }.count, 1)
        let durable = try await ShotCaptureDisk.shared.load(from: url, context: document.context)
        XCTAssertEqual(durable.revision, 1)
        XCTAssertEqual(try durable.events().count, 1)
    }

    func testFieldGoalCorrectionChangesOnlyExplicitAttributionAndScoring() throws {
        let player = ShotCapturePlayer(id: "TEST-correction", name: "TEST ONLY correction", number: "94", temporary: true)
        var document = try ShotCaptureDocument.local(gameID: UUID(), players: [player])
        let id = try document.startFieldGoal(team: .our, playerID: player.id, location: ShotLocation(x: 0.3, y: 0.6), basket: .top)
        var event = try XCTUnwrap(document.events().first)
        event.value = 2; event.outcome = .made; try document.correct(event)
        XCTAssertEqual(try document.totals(team: .our).points, 2)
        event.team = .opponent; event.playerID = nil; try document.correct(event)
        XCTAssertEqual(try document.totals(team: .our).points, 0)
        XCTAssertEqual(try document.totals(team: .opponent).points, 2)
        event.value = 3; event.outcome = .missed; event.basket = .bottom; try document.correct(event)
        XCTAssertEqual(try document.totals(team: .opponent).missedThrees, 1)
        XCTAssertEqual(try document.totals(team: .opponent).points, 0)
        XCTAssertEqual(try document.events().first?.location, ShotLocation(x: 0.3, y: 0.6))
        let saved = document
        event.value = Int.max
        XCTAssertThrowsError(try document.correct(event))
        XCTAssertEqual(document, saved)
        event.value = nil; event.outcome = .made
        XCTAssertThrowsError(try document.correct(event))
        XCTAssertEqual(document, saved)
        XCTAssertEqual(try document.events().map(\.id), [id])
    }

    func testUnsupportedCompoundEditDoesNotTrapRecorderOrReplaceDurableData() async throws {
        let player = ShotCapturePlayer(id: "TEST-compound", name: "TEST ONLY compound", number: "95", temporary: true)
        let document = try ShotCaptureDocument.local(gameID: UUID(), players: [player])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TEST-shot-compound-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let url = folder.appendingPathComponent("capture.json")
        try ShotCaptureStorage.create(document, at: url)
        let original = try Data(contentsOf: url)
        let recorder = try ShotCaptureRecorder(document: document, url: url)
        await recorder.change { candidate in
            _ = try candidate.startFieldGoal(team: .our, playerID: player.id, location: ShotLocation(x: 0.5, y: 0.5), basket: .top)
            var event = try XCTUnwrap(candidate.events().first)
            event.value = 2; event.outcome = .made; try candidate.correct(event)
        }
        XCTAssertFalse(recorder.needsSave)
        XCTAssertTrue(recorder.canChange)
        XCTAssertNotNil(recorder.issue)
        XCTAssertEqual(recorder.visibleDocument, document)
        XCTAssertEqual(try Data(contentsOf: url), original)
        await recorder.change { _ = try $0.startFreeThrows(team: .opponent, playerID: nil, attempts: 1) }
        XCTAssertNil(recorder.issue)
        XCTAssertFalse(recorder.needsSave)
        XCTAssertEqual(recorder.savedRevision, 1)
    }

    func testStalePendingChangeCanBePreservedBeforeReopeningNewerCapture() async throws {
        let document = try ShotCaptureDocument.local(gameID: UUID(), players: [])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TEST-shot-recovery-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let url = folder.appendingPathComponent("capture.json"), copy = folder.appendingPathComponent("recovery.json")
        try ShotCaptureStorage.create(document, at: url)
        let first = try ShotCaptureRecorder(document: document, url: url)
        let stale = try ShotCaptureRecorder(document: document, url: url)
        await first.change { _ = try $0.startFreeThrows(team: .opponent, playerID: nil, attempts: 1) }
        await stale.change { _ = try $0.startFreeThrows(team: .opponent, playerID: nil, attempts: 2) }
        let pending = try XCTUnwrap(stale.visibleDocument)
        XCTAssertTrue(stale.needsSave)
        await stale.reopenPreservingPending(at: copy)
        XCTAssertFalse(stale.needsSave); XCTAssertTrue(stale.canChange)
        XCTAssertEqual(stale.visibleDocument, first.visibleDocument)
        XCTAssertEqual(try ShotCaptureStorage.load(from: copy, context: document.context), pending)
        XCTAssertEqual(try ShotCaptureStorage.load(from: url, context: document.context), first.visibleDocument)
        XCTAssertEqual(stale.recoveryURL, copy)
    }

    func testByteLimitRejectionDoesNotInstallAnUnrecoverablePendingChange() async throws {
        var document = try ShotCaptureDocument.local(gameID: UUID(), players: [])
        let id = try document.startFreeThrows(team: .opponent, playerID: nil, attempts: 10_000)
        var event = try XCTUnwrap(document.events().first)
        event.answers = (1...10_000).map { ShotFreeThrowAnswer(index: $0, outcome: .made) }
        try document.correct(event)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var rejected: ShotCaptureEvent
        while true {
            var next = document
            event.answers[0].outcome = event.answers[0].outcome == .made ? .missed : .made
            try next.correct(event)
            if try encoder.encode(next).count > ShotCaptureStorage.maximumBytes { rejected = event; break }
            document = next
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TEST-shot-byte-limit-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let url = folder.appendingPathComponent("capture.json")
        try ShotCaptureStorage.create(document, at: url)
        let original = try Data(contentsOf: url)
        let recorder = try ShotCaptureRecorder(document: document, url: url)
        await recorder.change { try $0.correct(rejected) }
        XCTAssertFalse(recorder.needsSave); XCTAssertTrue(recorder.canChange)
        XCTAssertNotNil(recorder.issue); XCTAssertTrue(recorder.visibleDocument == document)
        XCTAssertTrue(try Data(contentsOf: url) == original)
        XCTAssertEqual(try recorder.visibleDocument?.events().first?.id, id)
    }

}
