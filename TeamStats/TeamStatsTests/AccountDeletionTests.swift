import XCTest
import Foundation
import Supabase
@testable import TeamStats

@MainActor
final class AccountDeletionTests: XCTestCase {
    func testLostAndCancelledRepliesRequireReadbackWithoutAnotherWrite() async throws {
        for mode in [DeletionFixture.Mode.lostReply, .cancelledReply] {
            let fixture = DeletionFixture(); let model = fixture.model()
            await model.load(); fixture.setMode(mode)
            await model.submit()
            XCTAssertNil(model.receipt); XCTAssertFalse(model.didLoad)
            XCTAssertEqual(model.issue, .unconfirmed); XCTAssertFalse(model.canSubmit)
            await model.submit()
            XCTAssertEqual(fixture.submitCount, 1)
            fixture.setMode(.success); await model.load()
            XCTAssertEqual(model.receipt?.id, deletionReceiptID)
            XCTAssertTrue(model.didLoad); XCTAssertNil(model.issue)
            XCTAssertEqual(fixture.submitCount, 1)
        }
    }
    func testTaskCancellationAfterCommitRecoversReceiptWithoutReplay() async throws {
        let fixture = DeletionFixture(); let model = fixture.model()
        await model.load(); fixture.setMode(.heldReply)
        let pending = Task { await model.submit() }
        defer { fixture.releaseReply() }
        for _ in 0..<100 where fixture.submitCount == 0 { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(fixture.submitCount, 1)
        pending.cancel()
        XCTAssertTrue(pending.isCancelled)
        fixture.releaseReply()
        await pending.value
        XCTAssertNil(model.receipt); XCTAssertFalse(model.didLoad)
        XCTAssertEqual(model.issue, .unconfirmed)
        fixture.setMode(.success)
        await model.load()
        XCTAssertEqual(model.receipt?.id, deletionReceiptID)
        XCTAssertEqual(fixture.submitCount, 1)
    }
    func testMissingBackendDenialAndMalformedReceiptsNeverClaimSuccess() async {
        for (mode, issue) in [(DeletionFixture.Mode.missing, AccountDeletionIssue.unavailable),
                              (.denied, .denied), (.wrongActor, .invalidResponse),
                              (.badDate, .invalidResponse), (.badID, .invalidResponse)] {
            let fixture = DeletionFixture(); let model = fixture.model()
            await model.load(); fixture.setMode(mode)
            await model.submit()
            XCTAssertNil(model.receipt); XCTAssertFalse(model.didLoad)
            XCTAssertEqual(model.issue, issue); XCTAssertFalse(model.canSubmit)
            XCTAssertEqual(fixture.submitCount, 1)
        }
    }
    func testBusySubmissionAndLateSessionReplyCannotLeakReceipt() async throws {
        let fixture = DeletionFixture()
        var current = true
        let model = fixture.model(isCurrent: { current })
        await model.load(); fixture.setMode(.delayed)
        let pending = Task { await model.submit() }
        for _ in 0..<100 where fixture.submitCount == 0 { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(fixture.submitCount, 1)
        XCTAssertTrue(model.isBusy); XCTAssertNil(model.receipt)
        await model.submit()
        XCTAssertEqual(fixture.submitCount, 1)
        current = false
        await pending.value
        XCTAssertNil(model.receipt); XCTAssertFalse(model.didLoad)
        XCTAssertFalse(model.isCurrentSession)
        fixture.setMode(.success)
        let fresh = fixture.model()
        await fresh.load()
        XCTAssertEqual(fresh.receipt?.id, deletionReceiptID)
        fresh.invalidate()
        XCTAssertNil(fresh.receipt); XCTAssertFalse(fresh.isCurrentSession)
    }
    func testExplicitSubmissionNeedsServerReceiptAndReopeningRecoversSameIdentity() async throws {
        let fixture = DeletionFixture()
        let model = fixture.model()
        await model.load()
        XCTAssertTrue(model.didLoad)
        XCTAssertNil(model.receipt)
        await model.submit()
        let first = try XCTUnwrap(model.receipt)
        XCTAssertEqual(first.id, deletionReceiptID)
        XCTAssertEqual(first.userID, deletionActorID)
        let reopened = fixture.model()
        await reopened.load()
        XCTAssertEqual(reopened.receipt, first)
        await reopened.submit()
        XCTAssertEqual(reopened.receipt, first)
        XCTAssertEqual(fixture.submitCount, 1)
    }
}
private let deletionActorID = UUID(uuidString: "e1000000-0000-4000-8000-000000000001")!
private let deletionReceiptID = UUID(uuidString: "e2000000-0000-4000-8000-000000000001")!
private final class DeletionFixture: @unchecked Sendable {
    enum Mode { case success, lostReply, cancelledReply, missing, denied, wrongActor, badDate, badID, delayed, heldReply }
    private let replyGate = DispatchSemaphore(value: 0)
    func releaseReply() { replyGate.signal() }
    func waitForReplyRelease() { _ = replyGate.wait(timeout: .now() + 2) }
    private var mode: Mode = .success
    func setMode(_ mode: Mode) { lock.withLock { self.mode = mode } }
    private let lock = NSLock()
    private var recorded = false
    private var submissions = 0
    var submitCount: Int { lock.withLock { submissions } }
    @MainActor func model(isCurrent: @escaping () -> Bool = { true }) -> AccountDeletionRequest {
        DeletionProtocol.fixture = self
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DeletionProtocol.self]
        let client = SupabaseClient(supabaseURL: URL(string: "https://deletion.invalid")!,
            supabaseKey: "sb_publishable_synthetic_fixture", options: .init(auth: .init(autoRefreshToken: false),
                global: .init(session: URLSession(configuration: config), logger: nil)))
        return AccountDeletionRequest(userID: deletionActorID, authenticatedClient: { client }, isCurrentSession: isCurrent)
    }
    func response(_ request: URLRequest) -> (Int, Data, Mode) {
        lock.withLock {
            if request.url?.lastPathComponent == "account_request_deletion" {
                submissions += 1
                if mode != .missing && mode != .denied { recorded = true }
            }
            let status = mode == .missing ? 404 : mode == .denied ? 401 : mode == .lostReply ? 500 : 200
            let value: Any = status != 200 ? ["code": mode == .missing ? "PGRST202" : mode == .denied ? "PGRST301" : "XX000", "message": "SENSITIVE_SYNTHETIC_BODY"] : recorded ?
                ["id": mode == .badID ? "invalid" : deletionReceiptID.uuidString,
                 "user_id": mode == .wrongActor ? "e1000000-0000-4000-8000-000000000002" : deletionActorID.uuidString,
                 "requested_at": mode == .badDate ? "invalid" : "2026-10-17T00:00:00.123456+00:00"] as Any : NSNull()
            return (status, try! JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]), mode)
        }
    }
}
private final class DeletionProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var fixture: DeletionFixture?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "deletion.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let fixture = Self.fixture!
        let (status, data, mode) = fixture.response(request)
        if mode == .heldReply { fixture.waitForReplyRelease() }
        if mode == .cancelledReply { client?.urlProtocol(self, didFailWithError: URLError(.cancelled)); return }
        if mode == .delayed { Thread.sleep(forTimeInterval: 0.15) }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
