import Foundation
import XCTest
@testable import TeamStats

final class AccountHTTPTests: XCTestCase {
    func testIdentityReadRecoversWithRetryAfterButDenialsNeverRetry() async throws {
        let fixture = HTTPFixture(statuses: [429, 200], retryAfter: "1")
        let start = ContinuousClock.now
        let (_, response) = try await AccountHTTP.send(fixture.request(), session: fixture.session, budget: .seconds(3), jitter: { 0 })
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(fixture.sends, 2)
        XCTAssertGreaterThanOrEqual(start.duration(to: .now), .seconds(1))
        for status in [401, 403] {
            let denied = HTTPFixture(statuses: [status, 200])
            let (_, response) = try await AccountHTTP.send(denied.request(), session: denied.session)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, status)
            XCTAssertEqual(denied.sends, 1)
        }
    }

    func testTransientReadRetriesAreCappedAndLongRetryAfterDoesNotRetryEarly() async {
        for fixture in [HTTPFixture(statuses: [503, 503, 503, 200]), HTTPFixture(statuses: [429, 200], retryAfter: "999999")] {
            do { _ = try await AccountHTTP.send(fixture.request(), session: fixture.session, budget: .seconds(1), jitter: { 0 }); XCTFail("Expected unavailable") }
            catch { XCTAssertTrue(error is AccountHTTP.Failure) }
            XCTAssertEqual(fixture.sends, fixture.retryAfter == nil ? 3 : 1)
        }
    }

    func testServerDateMakesRetryAfterHonestDespiteDeviceClockDifference() async {
        let fixture = HTTPFixture(statuses: [429,200], retryAfter: "Mon, 01 Jan 2001 01:00:00 GMT", serverDate: "Mon, 01 Jan 2001 00:00:00 GMT")
        do { _ = try await AccountHTTP.send(fixture.request(), session: fixture.session, budget: .seconds(2), jitter: { 0 }); XCTFail("Must not retry earlier than server guidance") }
        catch { XCTAssertTrue(error is AccountHTTP.Failure) }
        XCTAssertEqual(fixture.sends,1)
    }

    func testMutationServerFailureAndRedirectAreSingleAttempt() async {
        for status in [503, 307] {
            let fixture = HTTPFixture(statuses: [status, 200])
            do { _ = try await AccountHTTP.send(fixture.request(method: "POST"), session: fixture.session); XCTFail("Expected unavailable") }
            catch { XCTAssertTrue(error is AccountHTTP.Failure) }
            XCTAssertEqual(fixture.sends, 1)
        }
    }

    func testDeadlineStopsAnUnfinishedReplyWithoutRetry() async {
        let fixture = HTTPFixture(statuses: [])
        let start = ContinuousClock.now
        do { _ = try await AccountHTTP.send(fixture.request(), session: fixture.session, budget: .milliseconds(40)); XCTFail("Expected timeout") }
        catch { XCTAssertTrue(error is AccountHTTP.Failure) }
        XCTAssertLessThan(start.duration(to: .now), .seconds(1))
        XCTAssertEqual(fixture.sends, 1)
    }

    func testCancellationDuringBackoffStopsFurtherRequests() async throws {
        let fixture = HTTPFixture(statuses: [429, 200], retryAfter: "20")
        let task = Task { try await AccountHTTP.send(fixture.request(), session: fixture.session) }
        for _ in 0..<100 where fixture.sends == 0 { try await Task.sleep(for: .milliseconds(5)) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(fixture.sends, 1)
    }

    func testOversizedReplyIsUnavailableWithoutAnotherAttempt() async {
        let fixture = HTTPFixture(statuses: [200], bytes: Data(repeating: 1, count: 100))
        do { _ = try await AccountHTTP.send(fixture.request(), session: fixture.session, maximum: 4); XCTFail("Expected size rejection") }
        catch { XCTAssertTrue(error is AccountHTTP.Failure) }
        XCTAssertEqual(fixture.sends, 1)
    }
}

private final class HTTPFixture: @unchecked Sendable {
    let id = UUID().uuidString.lowercased()
    let statuses: [Int]
    let retryAfter: String?
    let serverDate: String?
    let bytes: Data
    private let lock = NSLock()
    private var count = 0
    var sends: Int { lock.lock(); defer { lock.unlock() }; return count }
    func next() -> Int? {
        lock.lock(); defer { lock.unlock() }; count += 1
        return statuses.isEmpty ? nil : statuses[min(count-1, statuses.count-1)]
    }
    lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HTTPFixtureProtocol.self]
        HTTPFixtureProtocol.register(self)
        return URLSession(configuration: config)
    }()
    init(statuses: [Int], retryAfter: String? = nil, serverDate: String? = nil, bytes: Data = Data("{}".utf8)) {
        self.statuses = statuses; self.retryAfter = retryAfter; self.serverDate = serverDate; self.bytes = bytes
    }
    func request(method: String = "GET") -> URLRequest {
        var request = URLRequest(url: URL(string: "https://" + id + ".invalid/auth/v1/user")!)
        request.httpMethod = method
        return request
    }
}
private final class HTTPFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var fixtures: [String: HTTPFixture] = [:]
    static func register(_ fixture: HTTPFixture) { lock.lock(); defer { lock.unlock() }; fixtures[fixture.id + ".invalid"] = fixture }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let fixture = Self.fixtures[request.url!.host!]!; Self.lock.unlock()
        guard let status = fixture.next() else { return } // A deliberately unfinished response.
        var headers = ["Content-Length": String(fixture.bytes.count)]
        if let date = fixture.serverDate { headers["Date"] = date }
        if let retry = fixture.retryAfter { headers["Retry-After"] = retry }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: fixture.bytes)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
