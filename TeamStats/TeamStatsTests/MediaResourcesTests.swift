import XCTest
import Foundation
import Supabase
@testable import TeamStats

@MainActor
final class MediaResourcesTests: XCTestCase {
    func testMediaVersionReadsRestrictSelectedTargetBeforeTransfer() async throws {
        for kind in [MediaResourceKind.practice, .film] {
            let fixture = MediaFixture(mode: .staleDraft); let model = fixture.model(kind: kind)
            await model.load()
            let request = try XCTUnwrap(fixture.versionReadURLs.first)
            let items = URLComponents(url: request, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let query = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, new in new })
            let select = try XCTUnwrap(query["select"])
            XCTAssertTrue(select.contains("media_resources!media_resource_versions_team_id_resource_id_fkey!inner"))
            XCTAssertEqual(query["media_resources.kind"], "eq.\(kind.rawValue)")
            XCTAssertEqual(query[kind == .practice ? "media_resources.play_id" : "media_resources.game_id"], "eq.\(mediaTargetID.uuidString)")
            XCTAssertEqual(query["team_id"], "eq.\(mediaTeamID.uuidString)")
        }
    }
    func testLostResumeAcknowledgmentFindsExactSavedSuccessorAfterReloadWithoutReplay() async throws {
        let fixture = MediaFixture(mode: .lostResumeAck); let model = fixture.model(); await model.load()
        let previous = try XCTUnwrap(model.ownDrafts.first)
        assertMediaNil(await model.resumeDraft(previous))
        XCTAssertEqual(model.issue, .server); XCTAssertTrue(model.reloadRequired)
        await model.load()
        let reloadedPrevious = try XCTUnwrap(model.versions.first { $0.id == previous.id })
        XCTAssertEqual(reloadedPrevious.status, .superseded)
        let successor = try XCTUnwrap(model.recoveredDraft(after: reloadedPrevious))
        XCTAssertEqual(successor.id, mediaResumedID)
        XCTAssertEqual(successor.title, "Saved author proposal")
        XCTAssertEqual(successor.recoverySourceVersionID, previous.id)
        XCTAssertEqual(model.published.first?.id, mediaCurrentID)
        XCTAssertEqual(model.ownDrafts.count, 1)
        XCTAssertEqual(fixture.commands.filter { $0.name == "media_resume_draft" }.count, 1)
        XCTAssertNil(model.recoveredDraft(after: reloadedPrevious, expectedID: UUID(), expectedRevision: successor.revision))
        XCTAssertNil(model.recoveredDraft(after: reloadedPrevious, expectedID: successor.id, expectedRevision: successor.revision + 1))
        assertMediaNil(await model.resumeDraft(reloadedPrevious))
        XCTAssertEqual(fixture.commands.filter { $0.name == "media_resume_draft" }.count, 1)
    }
    func testStaleOrAmbiguousRecoveryLineageCannotAttachRetainedInput() async throws {
        for mode in [MediaFixture.Mode.ambiguousRecovery, .staleRecovery, .missingRecoveryLineage, .chainedRecovery, .cyclicRecovery] {
            let fixture = MediaFixture(mode: mode); let model = fixture.model(); await model.load()
            let previous = try XCTUnwrap(model.ownDrafts.first)
            _ = await model.resumeDraft(previous)
            await model.load()
            let savedPrevious = try XCTUnwrap(model.versions.first { $0.id == previous.id })
            XCTAssertEqual(savedPrevious.status, .superseded)
            XCTAssertNil(model.recoveredDraft(after: savedPrevious))
            XCTAssertEqual(fixture.commands.filter { $0.name == "media_resume_draft" }.count, 1)
        }
    }
    func testLostAcknowledgmentFollowsExactSameAuthorRecoveryChain() async throws {
        let fixture = MediaFixture(mode: .validRecoveryChain); let model = fixture.model(); await model.load()
        let previous = try XCTUnwrap(model.ownDrafts.first)
        assertMediaNil(await model.resumeDraft(previous))
        await model.load()
        let savedPrevious = try XCTUnwrap(model.versions.first { $0.id == previous.id })
        let current = try XCTUnwrap(model.recoveredDraft(after: savedPrevious))
        XCTAssertEqual(current.id.uuidString.lowercased(), "da000000-0000-4000-8000-000000000001")
        XCTAssertEqual(current.recoverySourceVersionID, mediaResumedID)
        XCTAssertEqual(current.authorUserID, previous.authorUserID)
        XCTAssertEqual(model.published.first?.id, mediaCurrentID)
        XCTAssertNil(model.recoveredDraft(after: savedPrevious, expectedID: mediaResumedID, expectedRevision: 1))
        XCTAssertEqual(fixture.commands.filter { $0.name == "media_resume_draft" }.count, 1)
    }
    func testRecoveryAttachmentRequiresCurrentFilmEligibility() async throws {
        let fixture = MediaFixture(mode: .revokedRecovery); let model = fixture.model(kind: .film); await model.load()
        XCTAssertTrue(model.canContribute)
        let previous = try XCTUnwrap(model.ownDrafts.first)
        assertMediaNil(await model.resumeDraft(previous))
        await model.load()
        XCTAssertFalse(model.canContribute)
        let savedPrevious = try XCTUnwrap(model.versions.first { $0.id == previous.id })
        XCTAssertNil(model.recoveredDraft(after: savedPrevious))
        XCTAssertEqual(fixture.commands.filter { $0.name == "media_resume_draft" }.count, 1)
    }
    func testExplicitResumeKeepsSavedProposalHistoryAndCurrentAcceptedLink() async throws {
        let fixture = MediaFixture(mode: .staleDraft); let model = fixture.model(); await model.load()
        let stale = try XCTUnwrap(model.ownDrafts.first)
        XCTAssertTrue(model.hasNewerPublishedLink(stale))
        XCTAssertEqual(stale.title, "Saved author proposal")
        let resumed = try mediaRequired(await model.resumeDraft(stale))
        XCTAssertNotEqual(resumed.id, stale.id)
        XCTAssertEqual(resumed.title, "Saved author proposal")
        XCTAssertEqual(resumed.notes, "Saved author notes")
        XCTAssertEqual(resumed.basePublishedVersionID, mediaCurrentID)
        XCTAssertEqual(model.versions.first(where: { $0.id == stale.id })?.status, .superseded)
        XCTAssertEqual(model.ownDrafts.count, 1)
        XCTAssertEqual(model.published.first?.id, mediaCurrentID)
        XCTAssertFalse(model.hasNewerPublishedLink(resumed))
        XCTAssertEqual(fixture.commands.last?.parameters["p_expected_published_version_id"] as? String, mediaCurrentID.uuidString)
        await model.load()
        XCTAssertTrue(model.didLoad)
        XCTAssertEqual(model.ownDrafts.first?.id, resumed.id)
        XCTAssertEqual(model.unpublished.first?.status, .superseded)
        XCTAssertEqual(model.published.first?.title, "Newer accepted content")
    }
    func testBlankDraftAndAuthorizedHTTPSLinksRemainExplicitInputs() {
        var input = MediaLinkInput()
        XCTAssertTrue(input.validDraft); XCTAssertFalse(input.readyToSubmit)
        input.title = "Synthetic video"
        input.linkURL = "https://video.example.invalid/watch?v=synthetic"
        XCTAssertTrue(input.readyToSubmit)
        for bad in ["http://video.example.invalid/watch", "https://user:secret@video.example.invalid/watch", "https://video.example.invalid/#token=synthetic", "https://video.example.invalid/?access_token=synthetic", "https://video.example.invalid/?%74oken=synthetic", "https://video.example.invalid/%zz", "https://video.example.invalid/with space", "https://video.example.invalid:8443/watch", String(repeating: "x", count: 2049)] {
            input.linkURL = bad
            XCTAssertFalse(input.validDraft, bad)
        }
        input.linkURL = ""; XCTAssertTrue(input.validDraft); XCTAssertFalse(input.readyToSubmit)
        input.title = String(repeating: "x", count: 121); XCTAssertFalse(input.validDraft)
    }
    func testDiscoveryUsesServerStateAndOrdinaryPracticeContribution() async throws {
        let fixture = MediaFixture()
        let model = fixture.model()
        await model.load()
        XCTAssertTrue(model.didLoad); XCTAssertTrue(model.canContribute)
        XCTAssertFalse(model.canPublishOwn); XCTAssertEqual(model.published.count, 0)
        let draft = try mediaRequired(await model.openDraft(resourceID: mediaResourceID))
        XCTAssertEqual(draft.authorUserID, mediaActorID)
        XCTAssertEqual(draft.status, .draft)
        XCTAssertEqual(fixture.commands.last?.name, "media_open_draft")
        XCTAssertEqual(fixture.commands.last?.parameters["p_resource_id"] as? String, mediaResourceID.uuidString)
        let same = try mediaRequired(await model.openDraft(resourceID: mediaResourceID))
        XCTAssertEqual(same.id, draft.id); XCTAssertEqual(model.ownDrafts.count, 1)
    }
    func testSaveSubmitAndReopenDoNotInventPublication() async throws {
        let fixture = MediaFixture()
        let model = fixture.model(); await model.load()
        let draft = try mediaRequired(await model.openDraft(resourceID: mediaResourceID))
        var input = MediaLinkInput(draft); input.title = "Synthetic link"; input.linkURL = "https://video.example.invalid/watch"; input.notes = "Synthetic notes"
        let saved = try mediaRequired(await model.save(draft, input: input))
        XCTAssertEqual(saved.revision, 2); XCTAssertEqual(saved.linkURL, input.linkURL)
        XCTAssertEqual(fixture.commands.last?.parameters["p_expected_revision"] as? Int, 1)
        let submitted = try mediaRequired(await model.transition(saved, action: "submit"))
        XCTAssertEqual(submitted.status, .submitted); XCTAssertTrue(model.published.isEmpty)
        XCTAssertEqual(model.unpublished.count, 1)
        await model.load()
        XCTAssertTrue(model.didLoad); XCTAssertEqual(model.unpublished.first?.id, submitted.id)
        XCTAssertEqual(model.unpublished.first?.notes, "Synthetic notes")
        let invalidEdit = await model.save(submitted, input: input)
        XCTAssertNil(invalidEdit)
    }
    func testInvalidInputBlocksNetworkAndBlankSaveRemainsDraft() async throws {
        let fixture = MediaFixture(); let model = fixture.model(); await model.load()
        let draft = try mediaRequired(await model.openDraft(resourceID: mediaResourceID))
        let count = fixture.commands.count
        var invalid = MediaLinkInput(); invalid.linkURL = "https://example.invalid/?token=synthetic"
        assertMediaNil(await model.save(draft, input: invalid)); XCTAssertEqual(model.issue, .invalidInput)
        XCTAssertEqual(fixture.commands.count, count)
        let blank = try mediaRequired(await model.save(draft, input: MediaLinkInput()))
        XCTAssertEqual(blank.title, ""); XCTAssertEqual(blank.linkURL, "")
        assertMediaNil(await model.transition(blank, action: "submit"))
        XCTAssertEqual(model.issue, .invalidInput)
    }
    func testConflictAndLostResponsesRequireReloadWithoutAutomaticReplay() async throws {
        for mode in [MediaFixture.Mode.conflict, .failure, .malformed] {
            let fixture = MediaFixture(mode: mode); let model = fixture.model(); await model.load()
            let draft = try mediaRequired(await model.openDraft(resourceID: mediaResourceID))
            var input = MediaLinkInput(); input.title = "Synthetic link"; input.linkURL = "https://video.example.invalid/watch"
            assertMediaNil(await model.save(draft, input: input))
            XCTAssertEqual(model.issue, mode == .conflict ? .conflict : mode == .malformed ? .invalidResponse : .server)
            XCTAssertTrue(model.reloadRequired); XCTAssertNil(model.confirmation)
            XCTAssertEqual(fixture.commands.filter { $0.name == "media_save_draft" }.count, 1)
            assertMediaNil(await model.save(draft, input: input))
            XCTAssertEqual(fixture.commands.filter { $0.name == "media_save_draft" }.count, 1)
            await model.load()
            XCTAssertTrue(model.didLoad); XCTAssertFalse(model.reloadRequired)
        }
    }
    func testEmptyDataAndLoadFailureAreDifferentAndRetryRecovers() async {
        let fixture = MediaFixture(mode: .loadFailureOnce); let model = fixture.model()
        await model.load()
        XCTAssertFalse(model.didLoad); XCTAssertEqual(model.issue, .server)
        XCTAssertFalse(model.canContribute); XCTAssertTrue(model.resources.isEmpty)
        await model.load()
        XCTAssertTrue(model.didLoad); XCTAssertNil(model.issue); XCTAssertTrue(model.resources.isEmpty)
    }
    func testFilmPublicationAloneNeverCreatesContributionEligibility() async {
        let fixture = MediaFixture(mode: .filmPublishOnly); let model = fixture.model(kind: .film)
        await model.load()
        XCTAssertFalse(model.canContribute); XCTAssertFalse(model.canPublishOwn)
        assertMediaNil(await model.openDraft(resourceID: mediaResourceID)); XCTAssertEqual(model.issue, .denied)
        XCTAssertTrue(fixture.commands.isEmpty)
    }
    func testInspectorCannotApproveButOwnerCanPublishAcceptedPointer() async throws {
        for owner in [false, true] {
            let fixture = MediaFixture(mode: owner ? .ownerPending : .inspectorPending)
            let model = fixture.model(); await model.load()
            let pending = try XCTUnwrap(model.unpublished.first)
            let result = await model.transition(pending, action: "approve", reason: "Synthetic decision")
            if owner {
                XCTAssertEqual(result?.status, .published)
                XCTAssertEqual(model.published.first?.id, pending.id)
                XCTAssertEqual(fixture.commands.last?.parameters["p_action"] as? String, "approve")
            } else {
                XCTAssertNil(result); XCTAssertEqual(model.issue, .denied); XCTAssertTrue(fixture.commands.isEmpty)
            }
        }
    }
}
private let mediaTeamID = UUID(uuidString: "d1000000-0000-4000-8000-000000000001")!
private let mediaActorID = UUID(uuidString: "d2000000-0000-4000-8000-000000000001")!
private let mediaTargetID = UUID(uuidString: "d3000000-0000-4000-8000-000000000001")!
private let mediaResourceID = UUID(uuidString: "d4000000-0000-4000-8000-000000000001")!
private let mediaCurrentID = UUID(uuidString: "d6000000-0000-4000-8000-000000000001")!
private let mediaPriorID = UUID(uuidString: "d7000000-0000-4000-8000-000000000001")!
private let mediaResumedID = UUID(uuidString: "d8000000-0000-4000-8000-000000000001")!
private let mediaVersionID = UUID(uuidString: "d5000000-0000-4000-8000-000000000001")!
private final class MediaFixture: @unchecked Sendable {
    enum Mode { case standard, conflict, failure, malformed, loadFailureOnce, filmPublishOnly, ownerPending, inspectorPending, staleDraft, lostResumeAck, ambiguousRecovery, staleRecovery, missingRecoveryLineage, chainedRecovery, validRecoveryChain, cyclicRecovery, revokedRecovery }
    struct Command { let name: String; let parameters: [String: Any] }
    let key = UUID().uuidString
    private let mode: Mode
    private let lock = NSLock()
    private var recorded: [Command] = []
    private var versionReads: [URL] = []
    private var revision = 1
    private var status = "draft"
    private var title = ""
    private var url = ""
    private var notes = ""
    private var resumed = false
    private var preservedVersion: [String: Any]?
    private var opened = false
    private var failed = false
    private var kind: MediaResourceKind = .practice
    var commands: [Command] { lock.withLock { recorded } }
    var versionReadURLs: [URL] { lock.withLock { versionReads } }
    init(mode: Mode = .standard) { self.mode = mode }
    @MainActor func model(kind: MediaResourceKind = .practice) -> MediaResources {
        self.kind = kind
        if mode == .ownerPending || mode == .inspectorPending { opened = true; status = "submitted"; title = "Synthetic pending link"; url = "https://video.example.invalid/watch" }
        if mode == .staleDraft || mode == .lostResumeAck || mode == .ambiguousRecovery || mode == .staleRecovery || mode == .missingRecoveryLineage || mode == .chainedRecovery || mode == .validRecoveryChain || mode == .cyclicRecovery || mode == .revokedRecovery { opened = true; title = "Saved author proposal"; url = "https://video.example.invalid/my-proposal"; notes = "Saved author notes" }
        MediaProtocol.registry.insert(self)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MediaProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Media-Fixture": key]
        let client = SupabaseClient(supabaseURL: URL(string: "https://media.invalid")!, supabaseKey: "sb_publishable_synthetic_fixture", options: .init(auth: .init(autoRefreshToken: false), global: .init(session: URLSession(configuration: configuration), logger: nil)))
        return MediaResources(teamID: mediaTeamID, kind: kind, targetID: mediaTargetID, authenticatedClient: { client })
    }
    func response(_ request: URLRequest) -> (Int, Data) {
        lock.withLock {
            let name = request.url!.lastPathComponent
            if name == "team_access" {
                if mode == .loadFailureOnce && !failed { failed = true; return json(["code": "XX000", "message": "SENSITIVE_FIXTURE_PAYLOAD"], status: 500) }
                let capabilities: [String] = mode == .filmPublishOnly ? ["film.publish"] : mode == .inspectorPending ? ["practice.review"] : mode == .revokedRecovery && !resumed ? ["film.upload"] : []
                return json(["team_id": mediaTeamID.uuidString, "user_id": mediaActorID.uuidString, "is_owner": mode == .ownerPending,
                             "access_revision": 1, "capabilities": capabilities, "grant_envelopes": []])
            }
            if request.url!.path.contains("/rpc/") {
                let params = (try? JSONSerialization.jsonObject(with: request.httpBody ?? streamData(request.httpBodyStream))) as? [String: Any] ?? [:]
                recorded.append(Command(name: name, parameters: params))
                if name == "media_open_draft" { opened = true; return json(version()) }
                if name == "media_resume_draft" {
                    var previous = version(); previous["status"] = "superseded"; previous["revision"] = revision + 1
                    preservedVersion = previous; resumed = true; revision = 1
                    if mode == .lostResumeAck || mode == .ambiguousRecovery || mode == .staleRecovery || mode == .missingRecoveryLineage || mode == .chainedRecovery || mode == .validRecoveryChain || mode == .cyclicRecovery || mode == .revokedRecovery { return json(["code": "XX000", "message": "Synthetic lost acknowledgment"], status: 500) }
                    return json(["previous": previous, "draft": version()])
                }
                if name == "media_save_draft" {
                    if mode == .conflict || mode == .failure { return json(["code": mode == .conflict ? "40001" : "XX000", "message": "SENSITIVE_FIXTURE_PAYLOAD"], status: 500) }
                    revision += 1; title = params["p_title"] as? String ?? ""; url = params["p_link_url"] as? String ?? ""; notes = params["p_notes"] as? String ?? ""
                    var value = version()
                    if mode == .malformed { value["team_id"] = UUID().uuidString }
                    return json(value)
                }
                if name == "media_transition" {
                    revision += 1; status = params["p_action"] as? String == "submit" ? "submitted" : "published"
                    return json(version())
                }
            }
            if name == "media_resources" { return json(opened ? [resource()] : []) }
            if name == "media_resource_versions" {
                versionReads.append(request.url!)
                var rows = opened ? [version()] : []
                if mode == .staleDraft || mode == .lostResumeAck || mode == .ambiguousRecovery || mode == .staleRecovery || mode == .missingRecoveryLineage || mode == .chainedRecovery || mode == .validRecoveryChain || mode == .cyclicRecovery || mode == .revokedRecovery {
                    var current = version(); current["id"] = mediaCurrentID.uuidString; current["status"] = "published"; current["title"] = "Newer accepted content"; current["base_published_version_id"] = mediaPriorID.uuidString; current["recovery_source_version_id"] = NSNull(); current["author_user_id"] = "d2000000-0000-4000-8000-000000000002"
                    rows.append(current)
                    if resumed && mode == .ambiguousRecovery {
                        var ambiguous = version(); ambiguous["id"] = "d9000000-0000-4000-8000-000000000001"; rows.append(ambiguous)
                    }
                    if resumed && (mode == .chainedRecovery || mode == .validRecoveryChain || mode == .cyclicRecovery) {
                        rows[0]["status"] = "superseded"
                        var chain = version(); chain["id"] = "da000000-0000-4000-8000-000000000001"; chain["recovery_source_version_id"] = mediaResumedID.uuidString
                        if mode == .chainedRecovery { chain["author_user_id"] = "d2000000-0000-4000-8000-000000000002" }
                        if mode == .cyclicRecovery { chain["status"] = "superseded" }
                        rows.append(chain)
                    }
                    if var preservedVersion {
                        if mode == .cyclicRecovery { preservedVersion["recovery_source_version_id"] = "da000000-0000-4000-8000-000000000001" }
                        rows.append(preservedVersion)
                    }
                }
                return json(rows)
            }
            return json(["code": "XX000", "message": "Unknown fixture request"], status: 500)
        }
    }
    private func resource() -> [String: Any] {
        ["id": mediaResourceID.uuidString, "team_id": mediaTeamID.uuidString, "kind": kind.rawValue,
         "play_id": kind == .practice ? mediaTargetID.uuidString : NSNull(), "game_id": kind == .film ? mediaTargetID.uuidString : NSNull(),
         "published_version_id": (mode == .staleDraft || mode == .lostResumeAck || mode == .ambiguousRecovery || mode == .staleRecovery || mode == .missingRecoveryLineage || mode == .chainedRecovery || mode == .validRecoveryChain || mode == .cyclicRecovery || mode == .revokedRecovery) ? mediaCurrentID.uuidString as Any : status == "published" ? mediaVersionID.uuidString as Any : NSNull()]
    }
    private func version() -> [String: Any] {
        ["id": resumed ? mediaResumedID.uuidString : mediaVersionID.uuidString, "team_id": mediaTeamID.uuidString, "resource_id": mediaResourceID.uuidString,
         "author_user_id": mode == .ownerPending || mode == .inspectorPending ? "d2000000-0000-4000-8000-000000000002" : mediaActorID.uuidString,
         "revision": revision, "status": status, "title": title, "link_url": url, "notes": notes,
         "recovery_source_version_id": resumed && mode != .missingRecoveryLineage ? mediaVersionID.uuidString : NSNull(),
         "base_published_version_id": (mode == .staleDraft || mode == .lostResumeAck || mode == .ambiguousRecovery || mode == .staleRecovery || mode == .missingRecoveryLineage || mode == .chainedRecovery || mode == .validRecoveryChain || mode == .cyclicRecovery || mode == .revokedRecovery) ? (resumed && mode != .staleRecovery ? mediaCurrentID.uuidString : mediaPriorID.uuidString) as Any : NSNull(), "review_reason": ""]
    }
    private func json(_ object: Any, status: Int = 200) -> (Int, Data) { (status, try! JSONSerialization.data(withJSONObject: object)) }
    private func streamData(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }; stream.open(); defer { stream.close() }
        var data = Data(); var bytes = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable { let count = stream.read(&bytes, maxLength: bytes.count); if count <= 0 { break }; data.append(contentsOf: bytes.prefix(count)) }
        return data
    }
}
private final class MediaRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: MediaFixture] = [:]
    func insert(_ fixture: MediaFixture) { lock.withLock { values[fixture.key] = fixture } }
    func fixture(_ key: String?) -> MediaFixture? { lock.withLock { key.flatMap { values[$0] } } }
}
private final class MediaProtocol: URLProtocol, @unchecked Sendable {
    static let registry = MediaRegistry()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "media.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let fixture = Self.registry.fixture(request.value(forHTTPHeaderField: "X-Media-Fixture")) else { client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return }
        let (status, data) = fixture.response(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func mediaRequired<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
    try XCTUnwrap(value, file: file, line: line)
}
private func assertMediaNil(_ value: Any?, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertNil(value, file: file, line: line)
}
