import XCTest
import Foundation
import Supabase
@testable import TeamStats

// Synthetic SDK/HTTP responses establish transport/state behavior, not Storage/decode rights.
@MainActor
final class PrivateFilesTests: XCTestCase {
    func testEmptyTargetFilteredFileListIsConfirmedByServer() async throws {
        let fixture = NativeFileFixture(mode: .empty), model = try fixture.model()
        await model.load()
        XCTAssertTrue(model.didLoad); XCTAssertNil(model.issue); XCTAssertTrue(model.versions.isEmpty)
        let request = try XCTUnwrap(fixture.requests.first { $0.url?.lastPathComponent == "file_resource_versions" })
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(query.first { $0.name == "file_resources.play_id" }?.value, "eq.\(privateTarget.uuidString)")
        XCTAssertTrue(query.first { $0.name == "select" }?.value?.contains("file_resource_versions_team_id_resource_id_fkey!inner") == true)
    }
    func testHTTP409ConflictDoesNotInventReservationOrAutomaticRetry() async throws {
        let fixture = NativeFileFixture(mode: .conflict), model = try fixture.model()
        await model.load()
        var input = PrivateFileInput(); input.title = "TEST ONLY CONFLICT"
        let result = await model.reserve(data: nativeFileBytes, input: input)
        XCTAssertNil(result); XCTAssertEqual(model.issue, .conflict)
        XCTAssertNil(model.pendingVersion)
        XCTAssertEqual(fixture.commands.filter { $0.0 == "file_reserve" }.count, 1)
    }
    func testLostReservationReplyRetriesExactOperationWithoutInventingSuccess() async throws {
        let fixture = NativeFileFixture(mode: .lostReservation), model = try fixture.model()
        await model.load()
        var input = PrivateFileInput(); input.title = "TEST ONLY CLIP"
        let first = await model.reserve(data: nativeFileBytes, input: input)
        XCTAssertNil(first); XCTAssertNotNil(model.issue)
        let second = await model.retryReservation()
        XCTAssertNotNil(second)
        let commands = fixture.commands.filter { $0.0 == "file_reserve" }
        XCTAssertEqual(commands.count, 2)
        XCTAssertEqual(commands[0].1["p_operation_id"] as? String, commands[1].1["p_operation_id"] as? String)
        XCTAssertEqual(commands[0].1["p_resource_id"] as? String, commands[1].1["p_resource_id"] as? String)
        XCTAssertEqual(model.versions.filter { $0.id == second?.id }.count, 1)
    }
    func testInterruptedUploadBlocksBlindReplayAndExplicitReconcileUpdatesSameRecord() async throws {
        let fixture = NativeFileFixture(mode: .uploadFailure), model = try fixture.model()
        await model.load()
        var input = PrivateFileInput(); input.title = "TEST ONLY CLIP"
        let reserved = await model.reserve(data: nativeFileBytes, input: input)
        let reservation = try XCTUnwrap(reserved)
        let failed = await model.upload(); XCTAssertNil(failed); XCTAssertTrue(model.uploadNeedsReconciliation)
        let replay = await model.upload(); XCTAssertNil(replay); XCTAssertEqual(model.issue, .reconcileRequired)
        XCTAssertEqual(fixture.requests.filter { $0.url?.path.contains("/uploads/") == true }.count, 1)
        let reconciled = await model.reconcile(reservation)
        XCTAssertEqual(reconciled?.id, reservation.id); XCTAssertEqual(reconciled?.status, .ready)
        XCTAssertFalse(model.uploadNeedsReconciliation)
    }
    func testPublicFileFailuresKeepCapacityAndRejectedUploadRecoveryDistinct() async throws {
        let rejected = ["unsupported_type", "encrypted_pdf", "malformed_file", "resource_limit", "unsupported_codec",
            "duration_limit", "dimension_limit", "size_limit", "active_content", "unreadable_content",
            "invalid_request", "unreadable", "invalid_pdf", "active_pdf", "invalid_video", "dimensions_limit", "file_validation_failed"]
        let failedValidation = ["validation_resource_limit", "validator_receipt_mismatch"]
        for code in rejected + failedValidation + ["capacity_unavailable", "private_file_capacity_unknown", "validator_unavailable"] {
            let fixture = NativeFileFixture(), model = try fixture.model()
            await model.load()
            var input = PrivateFileInput(); input.title = "TEST ONLY REJECTED CLIP"
            let reserved = await model.reserve(data: nativeFileBytes, input: input)
            XCTAssertNotNil(reserved)
            fixture.rejectUpload(code)
            let result = await model.upload(); XCTAssertNil(result)
            if rejected.contains(code) || failedValidation.contains(code) {
                XCTAssertEqual(model.issue, rejected.contains(code) ? .invalidFile : .validationFailed, code)
                XCTAssertNil(model.pendingVersion, code)
                XCTAssertFalse(model.hasPendingReservation, code)
                XCTAssertFalse(model.uploadNeedsReconciliation, code)
            } else {
                XCTAssertEqual(model.issue, code == "validator_unavailable" ? .server : .capacity, code)
                XCTAssertTrue(model.uploadNeedsReconciliation, code)
            }
            XCTAssertEqual(fixture.requests.filter { $0.url?.path.contains("/uploads/") == true }.count, 1)
        }
    }
    func testCompletePublishedClipIsIntegrityCheckedAndReusedWithoutAnotherDelivery() async throws {
        let fixture = NativeFileFixture(), model = try fixture.model()
        await model.load()
        let version = try XCTUnwrap(model.published.first)
        let first = await model.retrieve(version, keepOnDevice: true)
        XCTAssertNotNil(first); XCTAssertEqual(try first.map { try Data(contentsOf: $0) }, nativeFileBytes)
        let second = await model.retrieve(version, keepOnDevice: true)
        XCTAssertEqual(second, first)
        XCTAssertEqual(fixture.commands.filter { $0.0 == "file_delivery" }.count, 1)
        XCTAssertEqual(fixture.requests.filter { $0.url?.path.contains("/files/") == true }.count, 1)
    }
    func testFreshServerVisibilityUnlocksPreviouslyDeniedRetainedVersionWithoutDownload() async throws {
        let fixture = NativeFileFixture(), model = try fixture.model()
        await model.load()
        let version = try XCTUnwrap(model.published.first)
        let first = await model.retrieve(version, keepOnDevice: true)
        XCTAssertNotNil(first)
        let scope = try XCTUnwrap(model.clipScope)
        let clip = try XCTUnwrap(model.retention.items(scope: scope, actorID: privateActor).first)
        try model.retention.recordDenial(scope: scope, versionID: version.id)
        XCTAssertThrowsError(try model.offlineURL(clip))
        let rechecked = await model.retrieve(version, keepOnDevice: true)
        XCTAssertEqual(rechecked, first)
        XCTAssertEqual(fixture.commands.filter { $0.0 == "file_delivery" }.count, 1)
    }
    func testCorruptOversizedAndInterruptedDownloadsNeverCreatePlayableCopies() async throws {
        for mode in [NativeFileFixture.Mode.corruptDownload, .oversizedDownload, .interruptedDownload] {
            let fixture = NativeFileFixture(mode: mode), model = try fixture.model()
            await model.load()
            let version = try XCTUnwrap(model.published.first)
            let file = await model.retrieve(version, keepOnDevice: true)
            XCTAssertNil(file); XCTAssertNotNil(model.issue)
            XCTAssertTrue(try model.retainedClips().isEmpty)
        }
    }
    func testKnownDenialConcealsContentAndCannotBecomeEmptySuccessOnFailedRetry() async throws {
        let fixture = NativeFileFixture(), model = try fixture.model()
        await model.load(); XCTAssertFalse(model.versions.isEmpty)
        fixture.changeMode(.denied); await model.load()
        XCTAssertEqual(model.issue, .denied); XCTAssertTrue(model.contentConcealed); XCTAssertFalse(model.didLoad)
        fixture.changeMode(.unavailable); await model.load()
        XCTAssertEqual(model.issue, .server); XCTAssertTrue(model.contentConcealed); XCTAssertTrue(model.versions.isEmpty)
        fixture.changeMode(.standard); await model.load()
        XCTAssertTrue(model.didLoad); XCTAssertFalse(model.contentConcealed)
    }
}
private let privateActor = UUID(uuidString: "b1000000-0000-4000-8000-000000000001")!
private let privateTeam = UUID(uuidString: "b2000000-0000-4000-8000-000000000001")!
private let privateTarget = UUID(uuidString: "b3000000-0000-4000-8000-000000000001")!
private let privateResource = UUID(uuidString: "b4000000-0000-4000-8000-000000000001")!
private let privateVersion = UUID(uuidString: "b5000000-0000-4000-8000-000000000001")!
private let nativeFileBytes = Data("TEST ONLY protocol file bytes".utf8)
private final class NativeFileFixture: @unchecked Sendable {
    enum Mode { case standard, conflict, empty, lostReservation, uploadFailure, corruptDownload, oversizedDownload, interruptedDownload, denied, unavailable }
    let key = UUID().uuidString
    private let lock = NSLock(); private var mode: Mode
    private var allRequests: [URLRequest] = [], allCommands: [(String, [String: Any])] = []
    private var operation = UUID(); private var resource = privateResource
    private var uploadError: String?
    init(mode: Mode = .standard) { self.mode = mode }
    var requests: [URLRequest] { lock.withLock { allRequests } }
    var commands: [(String, [String: Any])] { lock.withLock { allCommands } }
    func rejectUpload(_ code: String) { lock.withLock { uploadError = code } }
    func changeMode(_ value: Mode) { lock.withLock { mode = value } }
    @MainActor func model() throws -> PrivateFiles {
        NativeFileURLProtocol.registry.insert(self)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [NativeFileURLProtocol.self]
        config.httpAdditionalHeaders = ["X-Native-File-Fixture": key]
        let session = URLSession(configuration: config)
        let configuration = try AccountConfiguration(url: "http://127.0.0.1:55431", publicKey: "sb_publishable_synthetic", environment: .localTest)
        let storage = FileFixtureStorage()
        let user = User(id: privateActor, appMetadata: [:], userMetadata: [:], aud: "authenticated", email: "synthetic@example.invalid", createdAt: Date(), emailConfirmedAt: Date(), updatedAt: Date())
        let auth = Session(accessToken: "TEST-ONLY-unverified-token", tokenType: "bearer", expiresIn: 3600, expiresAt: Date().timeIntervalSince1970 + 3600, refreshToken: "TEST-ONLY-refresh", user: user)
        try storage.store(key: "fixture-session", value: AuthClient.Configuration.jsonEncoder.encode(auth))
        let client = SupabaseClient(supabaseURL: configuration.url, supabaseKey: configuration.publicKey,
            options: .init(auth: .init(storage: storage, storageKey: "fixture-session", autoRefreshToken: false), global: .init(session: session, logger: nil)))
        return PrivateFiles(teamID: privateTeam, kind: .practice, targetID: privateTarget, configuration: configuration,
            authenticatedClient: { client }, offlineActor: { privateActor }, session: session,
            retention: ClipRetention(root: FileManager.default.temporaryDirectory.appendingPathComponent("TEST-ONLY-FILE-CACHE-" + UUID().uuidString)))
    }
    func response(_ request: URLRequest) -> (Int, Data, String, Bool) {
        lock.withLock {
            allRequests.append(request)
            let name = request.url!.lastPathComponent
            if mode == .denied { return (403, json(["code": "42501", "error": "access_denied", "message": "PRIVATE diagnostic"]), "application/json", false) }
            if mode == .unavailable { return (503, json(["error": "PRIVATE diagnostic"]), "application/json", false) }
            if request.url!.path.contains("/rpc/") {
                let arguments = (try? JSONSerialization.jsonObject(with: body(request))) as? [String: Any] ?? [:]
                allCommands.append((name, arguments))
                if name == "team_access" { return ok(["team_id": privateTeam.uuidString, "user_id": privateActor.uuidString, "is_owner": true, "access_revision": 1, "capabilities": [], "grant_envelopes": []]) }
                if name == "file_reserve" {
                    if mode == .conflict { return (409, json(["code": "PT409", "message": "PRIVATE conflict detail"]), "application/json", false) }
                    operation = UUID(uuidString: arguments["p_operation_id"] as! String)!; resource = UUID(uuidString: arguments["p_resource_id"] as! String)!
                    if mode == .lostReservation && allCommands.filter({ $0.0 == name }).count == 1 { return (503, json(["error": "PRIVATE uncertain reservation"]), "application/json", false) }
                    return ok(version(status: "uploading", receipt: false))
                }
                if name == "file_delivery" { return ok(["operation_id": arguments["p_operation_id"]!, "version_id": privateVersion.uuidString, "byte_count": nativeFileBytes.count, "sha256": clipDigest(nativeFileBytes), "content_type": "video/mp4"]) }
            }
            if request.url!.path.contains("/uploads/") {
                if let uploadError { return (422, json(["error": uploadError]), "application/json", false) }
                if mode == .uploadFailure && !request.url!.path.hasSuffix("reconcile") { return (503, json(["error": "operation_unconfirmed_reconcile"]), "application/json", false) }
                return ok(version(status: "ready", receipt: true))
            }
            if request.url!.path.contains("/files/") {
                if mode == .corruptDownload { return (200, Data(repeating: 33, count: nativeFileBytes.count), "video/mp4", false) }
                if mode == .oversizedDownload { return (200, nativeFileBytes + Data([1]), "video/mp4", false) }
                return (200, nativeFileBytes, "video/mp4", mode == .interruptedDownload)
            }
            if mode == .empty { return ok([]) }
            if name == "file_resources" { return ok([["id": resource.uuidString, "team_id": privateTeam.uuidString, "kind": "practice", "play_id": privateTarget.uuidString, "game_id": NSNull(), "published_version_id": privateVersion.uuidString, "archived_at": NSNull()]]) }
            return ok([version(status: "published", receipt: true)])
        }
    }
    private func version(status: String, receipt: Bool) -> [String: Any] {
        ["id": privateVersion.uuidString, "team_id": privateTeam.uuidString, "resource_id": resource.uuidString, "author_user_id": privateActor.uuidString,
         "operation_id": operation.uuidString, "revision": 1, "status": status, "title": "TEST ONLY CLIP", "notes": "", "declared_bytes": nativeFileBytes.count,
         "byte_count": receipt ? nativeFileBytes.count as Any : NSNull(), "sha256": receipt ? clipDigest(nativeFileBytes) as Any : NSNull(),
         "content_type": receipt ? "video/mp4" as Any : NSNull(), "base_published_version_id": NSNull(), "review_reason": ""]
    }
    private func body(_ request: URLRequest) -> Data {
        if let bytes = request.httpBody { return bytes }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }; var bytes = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; bytes.append(buffer, count: n) }
        return bytes
    }
    private func json(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }
    private func ok(_ object: Any) -> (Int, Data, String, Bool) { (200, json(object), "application/json", false) }
}
private final class FileFixtureStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock(); private var values: [String: Data] = [:]
    func store(key: String, value: Data) throws { lock.withLock { values[key] = value } }
    func retrieve(key: String) throws -> Data? { lock.withLock { values[key] } }
    func remove(key: String) throws { lock.withLock { values[key] = nil } }
}
private final class NativeFileRegistry: @unchecked Sendable {
    private let lock = NSLock(); private var fixtures: [String: NativeFileFixture] = [:]
    func insert(_ fixture: NativeFileFixture) { lock.withLock { fixtures[fixture.key] = fixture } }
    func get(_ key: String) -> NativeFileFixture? { lock.withLock { fixtures[key] } }
}
private final class NativeFileURLProtocol: URLProtocol, @unchecked Sendable {
    static let registry = NativeFileRegistry()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let fixture = Self.registry.get(request.value(forHTTPHeaderField: "X-Native-File-Fixture") ?? "") else { client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return }
        let (status, body, type, interrupted) = fixture.response(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": type, "Content-Length": String(body.count)])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: interrupted ? body.prefix(3) : body)
        if interrupted { client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)) }
        else { client?.urlProtocolDidFinishLoading(self) }
    }
    override func stopLoading() {}
}
