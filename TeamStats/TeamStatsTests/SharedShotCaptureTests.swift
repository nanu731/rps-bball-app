import XCTest
import Supabase
@testable import TeamStats

@MainActor final class SharedShotCaptureTests: XCTestCase {
    func testPreparedCaptureSurvivesRestartButCheckingAndStaleRepliesStayLocked() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TEST-shot-permit-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = ShotPreparationStore(root: root)
        let scope = ShotDeviceScope(environment: "https://test.example.invalid", actorID: UUID(), teamID: UUID())
        let game = UUID(), session = UUID()
        let entry = ShotPreparedEntry(gameID: game, sessionID: session, title: "TEST ONLY", expiresAt: nil)
        let first = try await store.lock(scope)
        try await store.unlock(scope, token: first, entry: entry)
        let result1 = try await store.entries(scope).count
        XCTAssertEqual(result1, 1)
        let reopened = ShotPreparationStore(root: root)
        let result2 = try await reopened.entries(scope).first?.sessionID
        XCTAssertEqual(result2, session)
        let old = try await store.lock(scope), newer = try await store.lock(scope)
        do { try await store.unlock(scope, token: old, entry: entry); XCTFail("Old reply unlocked newer check") } catch {}
        let result3 = try await reopened.entries(scope).isEmpty
        XCTAssertTrue(result3)
        try await store.unlock(scope, token: newer, entry: entry)
        let result4 = try await reopened.entries(scope).count
        XCTAssertEqual(result4, 1)
        let other = ShotDeviceScope(environment: scope.environment, actorID: UUID(), teamID: scope.teamID)
        let result5 = try await store.entries(other).isEmpty
        XCTAssertTrue(result5)
        let otherEnvironment = ShotDeviceScope(environment: "https://other.example.invalid", actorID: scope.actorID, teamID: scope.teamID)
        let result6 = try await store.entries(otherEnvironment).isEmpty
        XCTAssertTrue(result6)
    }
    func testKnownExpiryAndCorruptPreparationNeverBecomeEmptyEligibleCapture() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TEST-shot-expiry-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = ShotPreparationStore(root: root), scope = ShotDeviceScope(environment: "TEST", actorID: UUID(), teamID: UUID())
        let token = try await store.lock(scope)
        try await store.unlock(scope, token: token, entry: ShotPreparedEntry(gameID: UUID(), sessionID: UUID(), title: "TEST ONLY", expiresAt: Date(timeIntervalSince1970: 1)))
        let result7 = try await store.entries(scope).isEmpty
        XCTAssertTrue(result7)
        let file = try await store.permitURL(scope)
        try Data("corrupt".utf8).write(to: file)
        do { _ = try await store.entries(scope); XCTFail("Corruption was hidden") } catch {}
    }
}

extension SharedShotCaptureTests {
    private func fixture() throws -> (ShotDeviceScope, ShotCaptureDocument, ShotPreparationStore) {
        let scope = ShotDeviceScope(environment: "https://synthetic.example.invalid", actorID: UUID(), teamID: UUID())
        let doc = ShotCaptureDocument(schemaVersion: 1, id: UUID(), context: ShotCaptureContext(gameID: UUID(), teamID: scope.teamID, actorID: scope.actorID, assignmentRevision: 1), players: [], journal: [])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TEST-shared-shot-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (scope, doc, ShotPreparationStore(root: root))
    }
    private func state(_ doc: ShotCaptureDocument, scope: ShotDeviceScope, revision: Int = 3) throws -> AnyJSON {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let object = try JSONSerialization.jsonObject(with: encoder.encode(doc))
        return try JSONDecoder().decode(AnyJSON.self, from: JSONSerialization.data(withJSONObject: [
            "team_id": scope.teamID.uuidString, "game_id": doc.context.gameID.uuidString, "session_id": doc.id.uuidString,
            "recorder_user_id": scope.actorID.uuidString, "assignment_revision": 1, "state_revision": revision,
            "snapshot_id": UUID().uuidString, "document": object, "coverage_claim": "unknown", "status": "draft",
            "can_record": true, "can_review": false, "can_publish": false
        ]))
    }
    func testLostReplyFreezesExactJournalAndRecoversWithoutAnotherMutation() async throws {
        let (scope, doc, store) = try fixture()
        var remote = doc, writes = 0
        var receipt: AnyJSON = .null
        let model = SharedShotCapture(scope: scope, gameID: doc.context.gameID, title: "TEST ONLY", store: store, request: { name, args in
            if name == "shots_state" { return try self.state(remote, scope: scope) }
            if name == "shots_score_read" { throw URLError(.unsupportedURL) }
            if name == "shots_receipt" { return receipt }
            XCTAssertEqual(name, "shots_save"); writes += 1
            let text = try XCTUnwrap(args["p_document_text"]?.stringValue)
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            remote = try decoder.decode(ShotCaptureDocument.self, from: Data(text.utf8))
            receipt = .object(["batch_id": args["p_batch_id"]!, "operation": .string("save"), "actor_user_id": .string(scope.actorID.uuidString), "team_id": .string(scope.teamID.uuidString), "game_id": .string(doc.context.gameID.uuidString), "document_digest": .string(ShotDeviceScope.digest(text))])
            throw URLError(.networkConnectionLost)
        }, isCurrent: { true })
        await model.refresh()
        let recorder = try XCTUnwrap(model.recorder)
        await recorder.change { _ = try $0.startFreeThrows(team: .opponent, playerID: nil, attempts: 2) }
        let entered = try XCTUnwrap(recorder.visibleDocument)
        await model.save(entered, recovery: false)
        XCTAssertEqual(writes, 1); XCTAssertNotNil(model.pending); XCTAssertNil(model.state)
        await model.sendPending() // Receipt absence was not established: no blind replay.
        XCTAssertEqual(writes, 1)
        await model.recoverReceipt()
        XCTAssertNil(model.pending); XCTAssertEqual(writes, 1)
        let pending = try await store.pending(at: store.outboxURL(scope, game: doc.context.gameID))
        XCTAssertNil(pending)
        XCTAssertEqual(remote, entered)
    }
    func testForgedReceiptCannotClearFrozenCommandAndAccountChangeConcealsLateReply() async throws {
        let (scope, doc, store) = try fixture()
        var current = true
        var writes = 0
        let model = SharedShotCapture(scope: scope, gameID: doc.context.gameID, title: "TEST ONLY", store: store, request: { name, args in
            if name == "shots_state" { return try self.state(doc, scope: scope) }
            if name == "shots_receipt" { return .object(["batch_id": args["p_batch_id"]!, "operation": .string("save"), "actor_user_id": .string(UUID().uuidString)]) }
            if name == "shots_score_read" { throw URLError(.unsupportedURL) }
            writes += 1; throw URLError(.timedOut)
        }, isCurrent: { current })
        await model.refresh(); await model.save(doc, recovery: false)
        await model.recoverReceipt(); XCTAssertNotNil(model.pending); XCTAssertNotNil(model.issue)
        current = false
        await model.recoverReceipt()
        XCTAssertFalse(model.isCurrent); XCTAssertEqual(writes, 1)
        XCTAssertNil(model.recorder?.visibleDocument)
        let frozen = try await store.pending(at: store.outboxURL(scope, game: doc.context.gameID))
        XCTAssertNotNil(frozen)
    }
    func testColdPreparedContinuationMakesNoRequestAndKnownCheckLocksRestart() async throws {
        let (scope, doc, store) = try fixture()
        let url = try await store.documentURL(scope, game: doc.context.gameID, session: doc.id)
        try await ShotCaptureDisk.shared.create(doc, at: url)
        let entry = ShotPreparedEntry(gameID: doc.context.gameID, sessionID: doc.id, title: "TEST ONLY", expiresAt: nil)
        let token = try await store.lock(scope); try await store.unlock(scope, token: token, entry: entry)
        var requests = 0
        let model = SharedShotCapture(scope: scope, gameID: doc.context.gameID, title: "TEST ONLY", store: store, request: { _, _ in requests += 1; throw URLError(.notConnectedToInternet) }, isCurrent: { true })
        await model.openPrepared(entry)
        XCTAssertEqual(model.recorder?.visibleDocument, doc); XCTAssertTrue(model.offline)
        await model.recorder?.change { _ = try $0.startFreeThrows(team: .opponent, playerID: nil, attempts: 1) }
        XCTAssertEqual(requests, 0)
        await model.refresh(); XCTAssertEqual(requests, 1); XCTAssertNil(model.recorder?.visibleDocument)
        let reopened = SharedShotCapture(scope: scope, gameID: doc.context.gameID, title: "TEST ONLY", store: store, request: { _, _ in XCTFail("Cold continuation requested network"); return .null }, isCurrent: { true })
        await reopened.openPrepared(entry)
        XCTAssertNil(reopened.recorder)
        let saved = try await ShotCaptureDisk.shared.load(from: url, context: doc.context)
        XCTAssertEqual(saved.revision, 1)
    }
}

extension SharedShotCaptureTests {
    func testAnotherGameCannotReviveEarlierPreparationAndOutboxReservationIsExclusive() async throws {
        let (scope, doc, store) = try fixture()
        let a = ShotPreparedEntry(gameID: doc.context.gameID, sessionID: doc.id, title: "TEST ONLY A", expiresAt: nil)
        let b = ShotPreparedEntry(gameID: UUID(), sessionID: UUID(), title: "TEST ONLY B", expiresAt: nil)
        let first = try await store.lock(scope); try await store.unlock(scope, token: first, entry: a)
        _ = try await store.lock(scope) // A denied/interrupted check leaves it locked.
        let second = try await store.lock(scope); try await store.unlock(scope, token: second, entry: b)
        let available = try await store.entries(scope)
        XCTAssertEqual(available, [b])
        let url = try await store.outboxURL(scope, game: a.gameID)
        let command = ShotFrozenCommand(batch: UUID(), rpc: "shots_save", arguments: [:], payloadDigest: nil)
        let other = ShotFrozenCommand(batch: UUID(), rpc: "shots_save", arguments: [:], payloadDigest: nil)
        try await store.reserve(command, at: url)
        do { try await store.reserve(other, at: url); XCTFail("Another command replaced the first") } catch {}
        do { try await store.clear(expected: other.batch, at: url); XCTFail("Wrong receipt cleared the first") } catch {}
        let frozen = try await store.pending(at: url)
        XCTAssertEqual(frozen?.batch, command.batch)
        try await store.clear(expected: command.batch, at: url)
    }
}

extension SharedShotCaptureTests {
    func testRapidCommandsCannotReserveTwoBatches() async throws {
        let (scope, doc, store) = try fixture()
        var writes = 0
        let model = SharedShotCapture(scope: scope, gameID: doc.context.gameID, title: "TEST ONLY", store: store, request: { name, _ in
            if name == "shots_state" { return try self.state(doc, scope: scope) }
            if name == "shots_score_read" { throw URLError(.unsupportedURL) }
            writes += 1; await Task.yield(); throw URLError(.timedOut)
        }, isCurrent: { true })
        await model.refresh()
        async let first: Void = model.save(doc, recovery: false)
        async let second: Void = model.save(doc, recovery: false)
        _ = await (first, second)
        XCTAssertEqual(writes, 1)
        let frozen = try await store.pending(at: store.outboxURL(scope, game: doc.context.gameID))
        XCTAssertEqual(frozen?.batch, model.pending?.batch)
    }
}

extension SharedShotCaptureTests {
    func testDefinitiveConflictCanBeRetainedWithoutLosingCommandOrJournal() async throws {
        let (scope, doc, store) = try fixture()
        let model = SharedShotCapture(scope: scope, gameID: doc.context.gameID, title: "TEST ONLY", store: store, request: { name, _ in
            if name == "shots_state" { return try self.state(doc, scope: scope) }
            throw PostgrestError(code: "PT409", message: "SYNTHETIC conflict")
        }, isCurrent: { true })
        await model.refresh(); await model.save(doc, recovery: false)
        XCTAssertTrue(model.rejectedCommand)
        let batch = try XCTUnwrap(model.pending?.batch)
        await model.archiveRejected()
        XCTAssertNil(model.pending)
        let root = try await store.directory()
        let retained = root.appendingPathComponent("shot-retained-command-\(batch).json")
        let prior = try await store.pending(at: retained)
        XCTAssertEqual(prior?.batch, batch)
        let file = try await store.documentURL(scope, game: doc.context.gameID, session: doc.id)
        XCTAssertEqual(try ShotCaptureStorage.load(from: file, context: doc.context), doc)
    }
    func testAnotherTeamCheckConcealsMountedPreparedCapture() async throws {
        let (scope, doc, store) = try fixture()
        let url = try await store.documentURL(scope, game: doc.context.gameID, session: doc.id)
        try await ShotCaptureDisk.shared.create(doc, at: url)
        let entry = ShotPreparedEntry(gameID: doc.context.gameID, sessionID: doc.id, title: "TEST ONLY", expiresAt: nil)
        let token = try await store.lock(scope); try await store.unlock(scope, token: token, entry: entry)
        let model = SharedShotCapture(scope: scope, gameID: doc.context.gameID, title: "TEST ONLY", store: store, request: { _, _ in .null }, isCurrent: { true })
        await model.openPrepared(entry); XCTAssertTrue(model.canRecord)
        _ = ShotDeviceGate.shared.lock(scope); _ = try await store.lock(scope)
        XCTAssertFalse(model.contentCurrent); XCTAssertNil(model.recorder?.visibleDocument)
        do { _ = try await store.prepared(entry, scope: scope); XCTFail("Locked preparation activated") } catch {}
    }
}

extension SharedShotCaptureTests {
    func testSelectingServerHeadRetainsTheEntireConflictingDeviceBranch() async throws {
        let (scope, doc, store) = try fixture()
        var local = doc, server = doc
        _ = try local.startFreeThrows(team: .opponent, playerID: nil, attempts: 2)
        _ = try server.startFieldGoal(team: .opponent, playerID: nil, location: ShotLocation(x: 0.2, y: 0.4), basket: .top)
        let url = try await store.documentURL(scope, game: doc.context.gameID, session: doc.id)
        let copy = url.deletingLastPathComponent().appendingPathComponent("TEST-retained-branch.json")
        try await ShotCaptureDisk.shared.create(local, at: url)
        try await ShotCaptureDisk.shared.preserveAndUseServer(local, server: server, at: url, copy: copy)
        XCTAssertEqual(try ShotCaptureStorage.load(from: copy, context: doc.context), local)
        XCTAssertEqual(try ShotCaptureStorage.load(from: url, context: doc.context), server)
        do { try await ShotCaptureDisk.shared.preserveAndUseServer(local, server: server, at: url, copy: copy); XCTFail("Stale branch replacement") } catch {}
    }
}

extension SharedShotCaptureTests {
    func testFreshAuthorizedViewerDoesNotKeepAnExpiredRecorderDeadline() async throws {
        let (scope, doc, store) = try fixture()
        var viewer = false
        let model = SharedShotCapture(scope: scope, gameID: doc.context.gameID, title: "TEST ONLY", store: store, request: { _, _ in
            var values = try XCTUnwrap(self.state(doc, scope: scope).objectValue)
            values["can_record"] = .bool(!viewer)
            values["recording_valid_until"] = .string("1970-01-01T00:00:01Z")
            if viewer { values["status"] = .string("published") }
            return .object(values)
        }, isCurrent: { true })
        await model.refresh(); XCTAssertFalse(model.contentCurrent)
        viewer = true; await model.refresh()
        XCTAssertTrue(model.contentCurrent); XCTAssertFalse(model.canRecord)
        XCTAssertEqual(model.state?.document, doc)
    }
}

extension SharedShotCaptureTests {
    func testScoreReadCancellationDoesNotUnlockPreparedCapture() async throws {
        let (scope, doc, store) = try fixture()
        var cancel = false
        let model = SharedShotCapture(scope: scope, gameID: doc.context.gameID, title: "TEST ONLY", store: store, request: { name, _ in
            if name == "shots_state" { return try self.state(doc, scope: scope) }
            if cancel { throw CancellationError() }
            throw URLError(.unsupportedURL)
        }, isCurrent: { true })
        await model.refresh(); XCTAssertTrue(model.canRecord)
        cancel = true; await model.refresh()
        XCTAssertFalse(model.contentCurrent); XCTAssertNil(model.recorder?.visibleDocument)
        let entries = try await store.entries(scope); XCTAssertTrue(entries.isEmpty)
        let file = try await store.documentURL(scope, game: doc.context.gameID, session: doc.id)
        XCTAssertEqual(try ShotCaptureStorage.load(from: file, context: doc.context), doc)
    }
    func testIndependentScoreAllowsOneMissingTeamAndDoesNotMutateStatistics() async throws {
        let (scope, doc, store) = try fixture()
        var writes: [String] = [], captured: [String: AnyJSON] = [:]
        let model = SharedShotCapture(scope: scope, gameID: doc.context.gameID, title: "TEST ONLY", store: store, request: { name, args in
            if name == "shots_state" { return try self.state(doc, scope: scope) }
            if name == "shots_score_read" { return .object(["team_id": .string(scope.teamID.uuidString), "game_id": .string(doc.context.gameID.uuidString), "revision": .integer(0), "reference_id": .null, "our_points": .null, "opponent_points": .null, "source_note": .null, "can_confirm": .bool(true)]) }
            writes.append(name); captured = args
            return .object(["batch_id": args["p_batch_id"]!, "operation": .string("score_confirm"), "actor_user_id": .string(scope.actorID.uuidString), "team_id": .string(scope.teamID.uuidString), "game_id": .string(doc.context.gameID.uuidString), "score_revision": .integer(1)])
        }, isCurrent: { true })
        await model.refresh(); await model.confirmScore(our: 0, opponent: nil, source: "TEST ONLY independent score")
        XCTAssertEqual(writes, ["shots_score_confirm"])
        XCTAssertEqual(captured["p_our_points"], .integer(0)); XCTAssertEqual(captured["p_opponent_points"], .null)
        XCTAssertNil(model.pending); XCTAssertNotNil(model.lastConfirmedBatch); XCTAssertTrue(model.feedbackConfirmed)
    }
}
