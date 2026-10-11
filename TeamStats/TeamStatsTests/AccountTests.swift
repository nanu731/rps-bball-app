import XCTest
import Foundation
import Supabase
@testable import TeamStats

@MainActor
final class AccountTests: XCTestCase {
    func testConfigurationRejectsPrivilegedKeysAndInsecureRemoteURLs() throws {
        XCTAssertThrowsError(try AccountConfiguration(url: "http://example.invalid", publicKey: fixtureKey, environment: .nonproduction))
        XCTAssertThrowsError(try AccountConfiguration(url: "https://example.invalid", publicKey: "sb_secret_synthetic_fixture", environment: .nonproduction))
        let privilegedJWT = "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.fixture"
        XCTAssertThrowsError(try AccountConfiguration(url: "https://example.invalid", publicKey: privilegedJWT, environment: .nonproduction))
        XCTAssertThrowsError(try AccountConfiguration(url: "http://127.0.0.1:54321", publicKey: fixtureKey, environment: .nonproduction))
        XCTAssertNoThrow(try AccountConfiguration(url: "http://127.0.0.1:54321", publicKey: fixtureKey, environment: .localTest))
    }

    func testRequestingEmailCodeLeavesAccountPendingUntilVerification() async throws {
        let account = BackendAccount(storage: FixtureAccountStorage(), session: fixtureHTTPSession())
        await account.configure(url: "https://example.invalid", publicKey: fixtureKey, environment: .nonproduction)
        await account.requestCode(method: .email, identifier: "synthetic@example.invalid")
        XCTAssertEqual(account.state, .pendingVerification(.email))
        XCTAssertNil(account.verifiedUserID)
    }
    func testVerifiedEmailSessionSurvivesRestartAndSignOutClearsIt() async throws {
        let storage = FixtureAccountStorage()
        let first = BackendAccount(storage: storage, session: fixtureHTTPSession())
        await first.configure(url: "https://success.invalid", publicKey: fixtureKey, environment: .nonproduction)
        await first.requestCode(method: .email, identifier: "synthetic@example.invalid")
        await first.verifyCode("123456")
        XCTAssertEqual(first.verifiedUserID, fixtureUserID)
        let restarted = BackendAccount(storage: storage, session: fixtureHTTPSession())
        await restarted.restore()
        XCTAssertEqual(restarted.verifiedUserID, fixtureUserID)
        await restarted.signOut()
        XCTAssertEqual(restarted.state, .signedOut)
        let afterSignOut = BackendAccount(storage: storage, session: fixtureHTTPSession())
        await afterSignOut.restore()
        XCTAssertEqual(afterSignOut.state, .signedOut)
    }

    func testRemotePhoneDeliveryIsBlockedAndLocalSyntheticPhoneCanVerify() async throws {
        let remote = BackendAccount(storage: FixtureAccountStorage(), session: fixtureHTTPSession())
        await remote.configure(url: "https://success.invalid", publicKey: fixtureKey, environment: .nonproduction)
        await remote.requestCode(method: .phone, identifier: "+1 (202) 555-0100")
        XCTAssertEqual(remote.issue, .phoneDeliveryDisabled)
        XCTAssertNil(remote.verifiedUserID)
        let local = BackendAccount(storage: FixtureAccountStorage(), session: fixtureHTTPSession())
        await local.configure(url: "http://127.0.0.1:54321", publicKey: fixtureKey, environment: .localTest)
        await local.requestCode(method: .phone, identifier: "+1 (202) 555-0100")
        XCTAssertEqual(local.state, .pendingVerification(.phone))
        await local.verifyCode("123456")
        XCTAssertEqual(local.verifiedUserID, fixtureUserID)
    }

    func testConfirmationOnlyResponseNeverAuthenticates() async throws {
        let account = BackendAccount(storage: FixtureAccountStorage(), session: fixtureHTTPSession())
        await account.configure(url: "https://confirmation.invalid", publicKey: fixtureKey, environment: .nonproduction)
        await account.requestCode(method: .email, identifier: "synthetic@example.invalid")
        await account.verifyCode("123456")
        XCTAssertEqual(account.issue, .noVerifiedSession)
        XCTAssertNil(account.verifiedUserID)
    }

    func testCodeValidationFailureCanBeRetriedWithoutLosingPendingChallenge() async throws {
        let account = BackendAccount(storage: FixtureAccountStorage(), session: fixtureHTTPSession())
        await account.configure(url: "https://success.invalid", publicKey: fixtureKey, environment: .nonproduction)
        await account.requestCode(method: .email, identifier: "synthetic@example.invalid")
        await account.verifyCode("bad")
        XCTAssertEqual(account.issue, .invalidCode)
        XCTAssertEqual(account.pendingMethod, .email)
        await account.verifyCode("123456")
        XCTAssertEqual(account.verifiedUserID, fixtureUserID)
    }

    func testProviderFailureRemainsErrorAndDoesNotAuthenticate() async throws {
        let account = BackendAccount(storage: FixtureAccountStorage(), session: fixtureHTTPSession())
        await account.configure(url: "https://failure.invalid", publicKey: fixtureKey, environment: .nonproduction)
        await account.requestCode(method: .email, identifier: "synthetic@example.invalid")
        XCTAssertEqual(account.state, .error)
        XCTAssertEqual(account.issue, .provider)
        XCTAssertNil(account.verifiedUserID)
        XCTAssertFalse(account.isBusy)
    }

    func testServerRejectedRestoredSessionDoesNotExposeAuthenticatedClient() async throws {
        let storage = FixtureAccountStorage()
        let original = BackendAccount(storage: storage, session: fixtureHTTPSession())
        await original.configure(url: "https://success.invalid", publicKey: fixtureKey, environment: .nonproduction)
        await original.requestCode(method: .email, identifier: "synthetic@example.invalid")
        await original.verifyCode("123456")
        let rejected = BackendAccount(storage: storage, session: fixtureHTTPSession(mode: "revoked"))
        await rejected.restore()
        XCTAssertEqual(rejected.state, .error)
        XCTAssertNil(rejected.verifiedUserID)
        do {
            _ = try await rejected.authenticatedClient()
            XCTFail("A rejected session must not supply an authenticated command client")
        } catch { XCTAssertEqual(error as? AccountIssue, .noVerifiedSession) }
    }

    func testSecureSessionWriteFailureCannotReportAuthenticatedSuccess() async throws {
        let storage = FixtureAccountStorage(failSessionWrites: true)
        let account = BackendAccount(storage: storage, session: fixtureHTTPSession())
        await account.configure(url: "https://success.invalid", publicKey: fixtureKey, environment: .nonproduction)
        await account.requestCode(method: .email, identifier: "synthetic@example.invalid")
        await account.verifyCode("123456")
        XCTAssertEqual(account.issue, .storage)
        XCTAssertNil(account.verifiedUserID)
    }

    func testFailedServerRevocationStillSignsOutOnDeviceAndReportsLimit() async throws {
        let storage = FixtureAccountStorage()
        let account = BackendAccount(storage: storage, session: fixtureHTTPSession(mode: "logoutFailure"))
        await account.configure(url: "https://success.invalid", publicKey: fixtureKey, environment: .nonproduction)
        await account.requestCode(method: .email, identifier: "synthetic@example.invalid")
        await account.verifyCode("123456")
        await account.signOut()
        XCTAssertEqual(account.state, .signedOut)
        XCTAssertEqual(account.issue, .signOutRemoteFailure)
        let restarted = BackendAccount(storage: storage, session: fixtureHTTPSession())
        await restarted.restore()
        XCTAssertEqual(restarted.state, .signedOut)
    }

    func testKeychainSupportsMissingOverwriteRemoveAndNamespaceIsolation() throws {
        let storage = SecureSessionStorage(service: "TeamStats.account.tests." + UUID().uuidString)
        let other = SecureSessionStorage(service: "TeamStats.account.tests." + UUID().uuidString)
        defer { try? storage.remove(key: "synthetic"); try? other.remove(key: "synthetic") }
        XCTAssertNil(try storage.retrieve(key: "synthetic"))
        XCTAssertNoThrow(try storage.remove(key: "synthetic"))
        try storage.store(key: "synthetic", value: Data("fixture-one".utf8))
        try storage.store(key: "synthetic", value: Data("fixture-two".utf8))
        XCTAssertEqual(try storage.retrieve(key: "synthetic"), Data("fixture-two".utf8))
        XCTAssertNil(try other.retrieve(key: "synthetic"))
        try storage.remove(key: "synthetic")
        XCTAssertNil(try storage.retrieve(key: "synthetic"))
    }

    func testExpiredSessionRefreshSucceedsThroughAuthBeforeAuthentication() async throws {
        let account = BackendAccount(storage: FixtureAccountStorage(), session: fixtureHTTPSession())
        await account.configure(url: "https://expired.invalid", publicKey: fixtureKey, environment: .nonproduction)
        await account.requestCode(method: .email, identifier: "synthetic@example.invalid")
        await account.verifyCode("123456")
        XCTAssertEqual(account.verifiedUserID, fixtureUserID)
    }

    func testRefreshFailureDoesNotExposeExpiredAccountAsAuthenticated() async throws {
        let account = BackendAccount(storage: FixtureAccountStorage(), session: fixtureHTTPSession(mode: "refreshFailure"))
        await account.configure(url: "https://expired.invalid", publicKey: fixtureKey, environment: .nonproduction)
        await account.requestCode(method: .email, identifier: "synthetic@example.invalid")
        await account.verifyCode("123456")
        XCTAssertEqual(account.state, .error)
        XCTAssertNil(account.verifiedUserID)
    }

}

private let fixtureUserID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
private let fixtureKey = "sb_publishable_synthetic_fixture"

// Synthetic transport responses exercise the native account seam. They do not
// establish local/hosted Auth integration or email/SMS delivery evidence.
private final class FixtureAccountStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private let failSessionWrites: Bool
    init(failSessionWrites: Bool = false) { self.failSessionWrites = failSessionWrites }
    func store(key: String, value: Data) throws {
        lock.lock(); defer { lock.unlock() }
        if failSessionWrites && key.hasPrefix("session.v1.") { throw AccountIssue.storage }
        values[key] = value
    }
    func retrieve(key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }; return values[key]
    }
    func remove(key: String) throws {
        lock.lock(); defer { lock.unlock() }; values[key] = nil
    }
}

private func fixtureHTTPSession(mode: String? = nil) -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FixtureAccountURLProtocol.self]
    if let mode { configuration.httpAdditionalHeaders = ["X-Fixture-Mode": mode] }
    return URLSession(configuration: configuration)
}

private final class FixtureAccountURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let mode = request.value(forHTTPHeaderField: "X-Fixture-Mode")
        let denied = mode == "revoked" && request.url?.path.hasSuffix("/user") == true
        let logoutFailure = mode == "logoutFailure" && request.url?.path.hasSuffix("/logout") == true
        let refreshFailure = mode == "refreshFailure" && request.url?.path.hasSuffix("/token") == true
        let failed = request.url?.host == "failure.invalid" || denied || logoutFailure || refreshFailure
        let status = denied ? 401 : (failed ? 503 : 200)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let body: Data
        if failed {
            body = Data("{\"msg\":\"Synthetic denied response\"}".utf8)
        } else if request.url?.path.hasSuffix("/token") == true {
            body = try! AuthClient.Configuration.jsonEncoder.encode(fixtureSession())
        } else if request.url?.host == "confirmation.invalid", request.url?.path.hasSuffix("/verify") == true {
            body = try! AuthClient.Configuration.jsonEncoder.encode(fixtureUser())
        } else if request.url?.path.hasSuffix("/verify") == true {
            var session = fixtureSession()
            if request.url?.host == "expired.invalid" { session.expiresAt = 1_700_000_000; session.expiresIn = 0 }
            body = try! AuthClient.Configuration.jsonEncoder.encode(session)
        } else if request.url?.path.hasSuffix("/user") == true {
            body = try! AuthClient.Configuration.jsonEncoder.encode(fixtureUser())
        } else { body = Data("{}".utf8) }
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func fixtureUser() -> User {
    User(id: fixtureUserID, appMetadata: [:], userMetadata: [:], aud: "authenticated",
         email: "synthetic@example.invalid", createdAt: Date(timeIntervalSince1970: 1_700_000_000),
         emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
         updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
}

private func fixtureSession() -> Session {
    Session(accessToken: "synthetic-access-token-not-a-real-credential", tokenType: "bearer",
            expiresIn: 3600, expiresAt: Date().timeIntervalSince1970 + 3600,
            refreshToken: "synthetic-refresh-token-not-a-real-credential", user: fixtureUser())
}
