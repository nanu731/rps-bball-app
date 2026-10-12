import XCTest
import Foundation
import Supabase
@testable import TeamStats

final class PlayGeometryTests: XCTestCase {
    func testInvalidCoordinatesAndDuplicateIdentitiesAreRejected() {
        XCTAssertFalse(CourtPoint(x: .nan, y: 0).isValid)
        XCTAssertFalse(CourtPoint(x: 0.2, y: .infinity).isValid)
        XCTAssertFalse(CourtPoint(x: -0.1, y: 0).isValid)
        XCTAssertFalse(CourtPoint(x: 0, y: 1.1).isValid)
        var diagram = PlayDiagram(); diagram.addMarker(); diagram.addStep()
        XCTAssertNil(diagram.validationMessage)
        diagram.markers.append(diagram.markers[0])
        XCTAssertNotNil(diagram.validationMessage)
    }
    func testAuthoredInterpolationPauseScrubAndReducedMotionPositions() {
        var diagram = PlayDiagram(); diagram.addMarker(); diagram.addStep()
        let id = diagram.markers[0].id
        diagram.move(markerID: id, step: 1, to: CourtPoint(x: 0.9, y: 0.1))
        XCTAssertEqual(diagram.positions(at: 0)[0].point, CourtPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(diagram.positions(at: 0.5)[0].point.x, 0.7, accuracy: 0.0001)
        XCTAssertEqual(diagram.positions(at: 0.5)[0].point.y, 0.3, accuracy: 0.0001)
        XCTAssertEqual(diagram.positions(at: 1)[0].point, CourtPoint(x: 0.9, y: 0.1))
        XCTAssertEqual(diagram.positions(at: 0.5, reducedMotion: true)[0].point, CourtPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(diagram.positions(at: 1, reducedMotion: true)[0].point, CourtPoint(x: 0.9, y: 0.1))
        XCTAssertEqual(diagram.positions(at: 0.5), diagram.positions(at: 0.5))
    }
    func testNewMarkerAndStepKeepStableIdentityWithoutInventedLabels() throws {
        var diagram = PlayDiagram(); diagram.addMarker(); diagram.addStep()
        let first = diagram.markers[0].id
        diagram.addMarker(); diagram.addStep()
        XCTAssertEqual(diagram.markers.map(\.number), [1, 2])
        XCTAssertTrue(diagram.markers.allSatisfy { $0.label.isEmpty })
        XCTAssertEqual(diagram.markers[0].id, first)
        XCTAssertEqual(diagram.steps.map { $0.positions.count }, [2, 2])
        let reloaded = try JSONDecoder().decode(PlayDiagram.self, from: JSONEncoder().encode(diagram))
        XCTAssertEqual(reloaded, diagram)
        diagram.steps[0].positions.removeLast()
        XCTAssertNotNil(diagram.validationMessage)
    }
    func testDraftMayBeEmptyButPublicationNeedsAuthoredMovementAndValidDuration() {
        var diagram = PlayDiagram()
        XCTAssertNil(diagram.validationMessage); XCTAssertFalse(diagram.canPublish)
        diagram.addMarker(); XCTAssertFalse(diagram.canPublish)
        diagram.addStep(); XCTAssertTrue(diagram.canPublish)
        diagram.steps[0].duration = 0
        XCTAssertNotNil(diagram.validationMessage)
        diagram.steps[0].duration = .infinity
        XCTAssertNotNil(diagram.validationMessage)
    }
}

@MainActor final class PlaybookTests: XCTestCase {
    func testDraftSaveSubmissionPublicationAndSuccessorKeepAcceptedHistory() async throws {
        let fixture = PlayFixture(); let model = fixture.model()
        await model.load(); XCTAssertTrue(model.didLoad); XCTAssertTrue(model.published.isEmpty)
        let opened = await model.openDraft(playID: fixture.playID)
        let draft = try XCTUnwrap(opened)
        var diagram = PlayDiagram(); diagram.addMarker(); diagram.addStep()
        let result1 = await model.save(draft, title: "SYNTHETIC PLAY", diagram: diagram)
        XCTAssertTrue(result1)
        let saved = try XCTUnwrap(model.ownDrafts.first)
        XCTAssertEqual(saved.id, draft.id); XCTAssertEqual(saved.revision, 2)
        XCTAssertEqual(saved.diagram, diagram)
        let result2 = await model.transition(saved, action: "submit")
        XCTAssertTrue(result2)
        XCTAssertTrue(model.published.isEmpty)
        let submitted = try XCTUnwrap(model.submissions.first)
        let result3 = await model.transition(submitted, action: "approve")
        XCTAssertTrue(result3)
        let accepted = try XCTUnwrap(model.published.first)
        let openedSuccessor = await model.openDraft(playID: accepted.playID, source: accepted)
        let successor = try XCTUnwrap(openedSuccessor)
        XCTAssertNotEqual(successor.id, accepted.id)
        XCTAssertEqual(successor.basePublishedVersionID, accepted.id)
        XCTAssertEqual(model.published.first?.id, accepted.id)
        XCTAssertEqual(model.history(playID: accepted.playID).count, 1)
    }
    func testStaleSaveRequiresReloadAndNeverReportsPublication() async throws {
        let fixture = PlayFixture(); let model = fixture.model()
        await model.load(); let opened = await model.openDraft(playID: fixture.playID)
        let draft = try XCTUnwrap(opened)
        fixture.failSave = true
        let result4 = await model.save(draft, title: "SYNTHETIC", diagram: draft.diagram)
        XCTAssertFalse(result4)
        XCTAssertEqual(model.issue, .conflict); XCTAssertTrue(model.reloadRequired)
        XCTAssertNil(model.confirmation); XCTAssertTrue(model.published.isEmpty)
        let result5 = await model.save(draft, title: "SYNTHETIC", diagram: draft.diagram)
        XCTAssertFalse(result5)
        XCTAssertEqual(fixture.saveRequests, 1)
        fixture.failSave = false; await model.load()
        XCTAssertTrue(model.didLoad); XCTAssertFalse(model.reloadRequired)
    }
    func testExplicitStaleDraftRecoveryRetainsSavedHistoryAndAcceptedDrawing() async throws {
        let fixture = PlayFixture(); let model = fixture.model()
        await model.load()
        let initialOpened = await model.openDraft(playID: fixture.playID)
        let initial = try XCTUnwrap(initialOpened)
        var diagram = PlayDiagram(); diagram.addMarker(); diagram.addStep()
        let initialSave = await model.save(initial, title: "SYNTHETIC BASE", diagram: diagram)
        XCTAssertTrue(initialSave)
        let initialPublication = await model.transition(try XCTUnwrap(model.ownDrafts.first), action: "publish")
        XCTAssertTrue(initialPublication)
        let accepted = try XCTUnwrap(model.published.first)
        let successorOpened = await model.openDraft(playID: fixture.playID, source: accepted)
        let successor = try XCTUnwrap(successorOpened)
        diagram.move(markerID: diagram.markers[0].id, step: 1, to: CourtPoint(x: 0.8, y: 0.2))
        let successorSave = await model.save(successor, title: "SYNTHETIC AUTHOR SAVED", diagram: diagram)
        XCTAssertTrue(successorSave)
        let saved = try XCTUnwrap(model.ownDrafts.first)
        fixture.publishOtherSuccessor()
        await model.load()
        XCTAssertTrue(model.isStaleDraft(saved))
        let latest = try XCTUnwrap(model.published.first)
        let recovered = await model.recoverDraft(saved, expectedPublishedVersionID: latest.id)
        let resumed = try XCTUnwrap(recovered)
        XCTAssertNotEqual(resumed.id, saved.id)
        XCTAssertEqual(resumed.title, saved.title); XCTAssertEqual(resumed.diagram, saved.diagram)
        XCTAssertEqual(resumed.basePublishedVersionID, latest.id)
        XCTAssertEqual(resumed.recoverySourceVersionID, saved.id)
        let retained = try XCTUnwrap(model.versions.first { $0.id == saved.id })
        XCTAssertEqual(retained.status, .superseded)
        XCTAssertEqual(retained.title, saved.title); XCTAssertEqual(retained.diagram, saved.diagram)
        XCTAssertEqual(retained.basePublishedVersionID, accepted.id)
        XCTAssertEqual(model.published.first?.id, latest.id)
        XCTAssertEqual(model.published.first?.diagram, latest.diagram)
        XCTAssertEqual(model.ownDrafts.count, 1)
        XCTAssertFalse(model.isStaleDraft(resumed))
        let duplicate = await model.recoverDraft(saved, expectedPublishedVersionID: latest.id)
        XCTAssertNil(duplicate); XCTAssertEqual(fixture.recoveryRequests, 1)
    }
    func testCommittedRecoveryLostReplyCanAttachRetainedBuffersAfterReloadWithoutReplaying() async throws {
        _ = try await verifyUncertainRecovery(.lostReply)
    }
    func testCommittedRecoveryFailedFollowUpReadCanAttachRetainedBuffersAfterReloadWithoutReplaying() async throws {
        _ = try await verifyUncertainRecovery(.followUpRead)
    }
    private func verifyUncertainRecovery(_ failure: PlayFixture.RecoveryFailure) async throws -> (PlayFixture, Playbook, PlayRevision) {
        let fixture = PlayFixture(); let model = fixture.model()
        await model.load()
        let initialOpened = await model.openDraft(playID: fixture.playID)
        let initial = try XCTUnwrap(initialOpened)
        var savedDrawing = PlayDiagram(); savedDrawing.addMarker(); savedDrawing.addStep()
        let firstSave = await model.save(initial, title: "SYNTHETIC BASE", diagram: savedDrawing)
        XCTAssertTrue(firstSave)
        let firstPublish = await model.transition(try XCTUnwrap(model.ownDrafts.first), action: "publish")
        XCTAssertTrue(firstPublish)
        let accepted = try XCTUnwrap(model.published.first)
        let successorOpened = await model.openDraft(playID: fixture.playID, source: accepted)
        let successor = try XCTUnwrap(successorOpened)
        savedDrawing.move(markerID: savedDrawing.markers[0].id, step: 1, to: CourtPoint(x: 0.8, y: 0.2))
        let successorSave = await model.save(successor, title: "SYNTHETIC SAVED DRAWING", diagram: savedDrawing)
        XCTAssertTrue(successorSave)
        let retainedSource = try XCTUnwrap(model.ownDrafts.first)
        var retainedUnsavedDrawing = savedDrawing
        retainedUnsavedDrawing.move(markerID: retainedUnsavedDrawing.markers[0].id, step: 1, to: CourtPoint(x: 0.7, y: 0.3))
        fixture.publishOtherSuccessor(); await model.load()
        let latest = try XCTUnwrap(model.published.first)
        fixture.recoveryFailure = failure
        let uncertain = await model.recoverDraft(retainedSource, expectedPublishedVersionID: latest.id)
        XCTAssertNil(uncertain); XCTAssertNil(model.confirmation); XCTAssertTrue(model.reloadRequired)
        XCTAssertThrowsError(try model.recoveredDraft(for: retainedSource))
        fixture.failRead = false
        await model.load()
        XCTAssertTrue(model.didLoad)
        let resumed = try model.recoveredDraft(for: retainedSource)
        XCTAssertEqual(resumed.recoverySourceVersionID, retainedSource.id)
        XCTAssertEqual(resumed.title, retainedSource.title); XCTAssertEqual(resumed.diagram, savedDrawing)
        XCTAssertEqual(model.versions.first { $0.id == retainedSource.id }?.status, .superseded)
        XCTAssertEqual(model.published.first?.id, latest.id)
        XCTAssertEqual(fixture.recoveryRequests, 1)
        // Attaching metadata alone has no side effect; the later explicit Save writes retained buffers.
        let explicitSave = await model.save(resumed, title: "SYNTHETIC RETAINED UNSAVED", diagram: retainedUnsavedDrawing)
        XCTAssertTrue(explicitSave)
        XCTAssertEqual(model.ownDrafts.first?.diagram, retainedUnsavedDrawing)
        XCTAssertEqual(model.versions.first { $0.id == retainedSource.id }?.diagram, savedDrawing)
        XCTAssertEqual(model.published.first?.id, latest.id)
        XCTAssertEqual(model.ownDrafts.count, 1); XCTAssertEqual(fixture.recoveryRequests, 1)
        return (fixture, model, retainedSource)
    }
    func testRecoveredDraftLookupFollowsRepeatedRecoveryAndRejectsMissingAmbiguousOrRevokedAccess() async throws {
        let (fixture, model, retainedSource) = try await verifyUncertainRecovery(.lostReply)
        let firstResumed = try model.recoveredDraft(for: retainedSource)
        fixture.publishOtherSuccessor(); await model.load()
        let currentAccepted = try XCTUnwrap(model.published.first)
        let secondResult = await model.recoverDraft(firstResumed, expectedPublishedVersionID: currentAccepted.id)
        let secondResumed = try XCTUnwrap(secondResult)
        XCTAssertEqual(try model.recoveredDraft(for: retainedSource).id, secondResumed.id)
        XCTAssertEqual(secondResumed.recoverySourceVersionID, firstResumed.id)
        XCTAssertEqual(fixture.recoveryRequests, 2)
        fixture.lineageFailure = .missing
        await model.load()
        XCTAssertTrue(model.didLoad)
        XCTAssertThrowsError(try model.recoveredDraft(for: retainedSource))
        fixture.lineageFailure = .ambiguous
        await model.load()
        XCTAssertTrue(model.didLoad)
        XCTAssertThrowsError(try model.recoveredDraft(for: retainedSource))
        fixture.lineageFailure = .none; fixture.canAuthor = false
        await model.load()
        XCTAssertThrowsError(try model.recoveredDraft(for: retainedSource)) { error in XCTAssertEqual(error as? PlaybookIssue, .denied) }
        XCTAssertEqual(fixture.recoveryRequests, 2)
    }
    func testLoadFailureIsNotAnEmptySuccessfulPlaybookAndRetryRecovers() async {
        let fixture = PlayFixture(); fixture.failRead = true
        let model = fixture.model(); await model.load()
        XCTAssertFalse(model.didLoad); XCTAssertNotNil(model.issue)
        fixture.failRead = false; await model.load()
        XCTAssertTrue(model.didLoad); XCTAssertNil(model.issue); XCTAssertTrue(model.plays.isEmpty)
    }
}

private final class PlayFixture: @unchecked Sendable {
    let fixtureKey = UUID().uuidString
    private let lock = NSRecursiveLock()
    let teamID = UUID(uuidString: "a3000000-0000-4000-8000-000000000001")!
    let userID = UUID(uuidString: "a1000000-0000-4000-8000-000000000001")!
    let playID = UUID(uuidString: "a4000000-0000-4000-8000-000000000001")!
    private var pointer: String?
    private var rows: [[String: Any]] = []
    var failSave = false
    var failRead = false
    var saveRequests = 0
    enum RecoveryFailure { case none, lostReply, followUpRead }
    var recoveryFailure: RecoveryFailure = .none
    var recoveryRequests = 0
    enum LineageFailure { case none, missing, ambiguous }
    var lineageFailure: LineageFailure = .none
    var canAuthor = true
    func publishOtherSuccessor() {
        lock.lock(); defer { lock.unlock() }
        var published = rows.first { $0["id"] as? String == pointer }!
        published["id"] = UUID().uuidString
        published["author_user_id"] = "a1000000-0000-4000-8000-000000000002"
        published["base_published_version_id"] = pointer
        published["title"] = "SYNTHETIC OTHER ACCEPTED"
        rows.append(published); pointer = published["id"] as? String
    }
    @MainActor func model() -> Playbook {
        PlayProtocol.registry.insert(self)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlayProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Play-Fixture": fixtureKey]
        let client = SupabaseClient(supabaseURL: URL(string: "https://fixture.invalid")!, supabaseKey: "synthetic-publishable", options: SupabaseClientOptions(
            auth: .init(storage: PlayFixtureStorage(), emitLocalSessionAsInitialSession: false),
            global: .init(session: URLSession(configuration: configuration), logger: nil)))
        return Playbook(teamID: teamID, authenticatedClient: { client })
    }
    func handle(_ request: URLRequest) throws -> (Data, URLResponse) {
        lock.lock(); defer { lock.unlock() }
        let path = request.url!.path
        let parameters = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Self.readBody(request.httpBodyStream))) as? [String: Any] ?? [:]
        func respond(_ body: Any, status: Int = 200) throws -> (Data, URLResponse) {
            (try JSONSerialization.data(withJSONObject: body), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }
        if path.hasSuffix("team_access") { return try respond(["team_id": teamID.uuidString, "user_id": userID.uuidString, "is_owner": canAuthor, "access_revision": 1, "capabilities": [], "grant_envelopes": []]) }
        if failRead && request.httpMethod == "GET" { return try respond(["code": "42501", "message": "Synthetic denied"], status: 403) }
        if path.hasSuffix("/plays") { return try respond(rows.isEmpty ? [] : [["id": playID.uuidString, "team_id": teamID.uuidString, "published_version_id": pointer as Any? ?? NSNull()]]) }
        if path.hasSuffix("/play_versions") {
            var visible = rows
            if let source = rows.first(where: { $0["status"] as? String == "superseded" }),
               let child = rows.first(where: { $0["recovery_source_version_id"] as? String == source["id"] as? String }) {
                if lineageFailure == .missing { visible.removeAll { $0["id"] as? String == child["id"] as? String } }
                if lineageFailure == .ambiguous { var duplicate = child; duplicate["id"] = UUID().uuidString; visible.append(duplicate) }
            }
            return try respond(visible)
        }
        if path.hasSuffix("play_open_draft") {
            if let draft = rows.first(where: { $0["status"] as? String == "draft" }) { return try respond(draft) }
            let source = rows.first(where: { $0["id"] as? String == parameters["p_source_version_id"] as? String })
            let row: [String: Any] = ["id": UUID().uuidString, "team_id": teamID.uuidString, "play_id": playID.uuidString, "author_user_id": userID.uuidString,
                "revision": 1, "status": "draft", "title": source?["title"] ?? "", "diagram": source?["diagram"] ?? ["markers": [], "steps": []], "base_published_version_id": pointer as Any? ?? NSNull(), "review_reason": ""]
            rows.append(row); return try respond(row)
        }
        if path.hasSuffix("play_recover_draft") {
            recoveryRequests += 1
            let index = rows.firstIndex { $0["id"] as? String == parameters["p_version_id"] as? String }!
            guard rows[index]["status"] as? String == "draft", rows[index]["revision"] as? Int == parameters["p_expected_revision"] as? Int,
                  pointer == parameters["p_expected_published_version_id"] as? String else {
                return try respond(["code": "40001", "message": "Synthetic recovery conflict"], status: 500)
            }
            rows[index]["status"] = "superseded"; rows[index]["revision"] = (rows[index]["revision"] as! Int) + 1
            let superseded = rows[index]
            var resumed = superseded
            resumed["id"] = UUID().uuidString; resumed["status"] = "draft"; resumed["revision"] = 1
            resumed["base_published_version_id"] = pointer
            resumed["recovery_source_version_id"] = superseded["id"]
            rows.append(resumed)
            let failure = recoveryFailure; recoveryFailure = .none
            if failure == .lostReply { throw URLError(.networkConnectionLost) }
            if failure == .followUpRead { failRead = true }
            return try respond(["superseded": superseded, "draft": resumed])
        }
        if path.hasSuffix("play_save_draft") || path.hasSuffix("play_transition") {
            let saving = path.hasSuffix("play_save_draft")
            if saving { saveRequests += 1 }
            if saving && failSave { return try respond(["code": "40001", "message": "Synthetic conflict"], status: 500) }
            let index = rows.firstIndex { $0["id"] as? String == parameters["p_version_id"] as? String }!
            rows[index]["revision"] = (rows[index]["revision"] as! Int) + 1
            if saving { rows[index]["title"] = parameters["p_title"]; rows[index]["diagram"] = parameters["p_diagram"] }
            else {
                let action = parameters["p_action"] as! String
                rows[index]["status"] = action == "submit" ? "submitted" : action == "reject" ? "rejected" : "published"
                if rows[index]["status"] as? String == "published" { pointer = rows[index]["id"] as? String }
            }
            return try respond(rows[index])
        }
        return try respond(["code": "42501", "message": "Synthetic unexpected request"], status: 403)
    }
    private static func readBody(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open(); defer { stream.close() }
        var result = Data(); var bytes = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable { let size = stream.read(&bytes, maxLength: bytes.count); if size <= 0 { break }; result.append(contentsOf: bytes.prefix(size)) }
        return result
    }
}
private final class PlayRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var fixtures: [String: PlayFixture] = [:]
    func insert(_ fixture: PlayFixture) { lock.lock(); defer { lock.unlock() }; fixtures[fixture.fixtureKey] = fixture }
    func get(_ key: String) -> PlayFixture? { lock.lock(); defer { lock.unlock() }; return fixtures[key] }
}
private final class PlayProtocol: URLProtocol, @unchecked Sendable {
    static let registry = PlayRegistry()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let key = request.value(forHTTPHeaderField: "X-Play-Fixture"), let fixture = Self.registry.get(key) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        do {
            let (data, response) = try fixture.handle(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
private struct PlayFixtureStorage: AuthLocalStorage {
    func store(key: String, value: Data) throws {}
    func retrieve(key: String) throws -> Data? { nil }
    func remove(key: String) throws {}
}
