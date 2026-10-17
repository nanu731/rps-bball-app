import XCTest
import Foundation
import Supabase
@testable import TeamStats

@MainActor
final class AccountTests: XCTestCase {
    func testLostOTPReplyIsNotAutomaticallyReplayed() async throws {
        let session = fixtureHTTPSession(mode: "lostOTP")
        let trace = session.configuration.httpAdditionalHeaders?["X-Fixture-Trace"] as! String
        let account = BackendAccount(storage: FixtureAccountStorage(), session: session)
        await account.configure(url: "https://success.invalid", publicKey: fixtureKey, environment: .nonproduction)
        await account.requestCode(method: .email, identifier: "synthetic@example.invalid")
        XCTAssertEqual(FixtureAccountURLProtocol.otpSends(trace), 1)
        XCTAssertEqual(account.state, .error)
        XCTAssertNil(account.verifiedUserID)
    }
    func testTransientOTPServerFailureIsNotAutomaticallyReplayed() async throws {
        // The pinned SDK adds every one of these statuses to Auth POST retries.
        for status in [408, 500, 502, 503, 504, 520, 521, 522, 523, 524, 530] {
            let session = fixtureHTTPSession(mode: "lostOTP" + String(status))
            let trace = session.configuration.httpAdditionalHeaders?["X-Fixture-Trace"] as! String
            let account = BackendAccount(storage: FixtureAccountStorage(), session: session)
            await account.configure(url: "https://success.invalid", publicKey: fixtureKey, environment: .nonproduction)
            await account.requestCode(method: .email, identifier: "synthetic@example.invalid")
            XCTAssertEqual(FixtureAccountURLProtocol.otpSends(trace), 1, "HTTP" + String(status))
            XCTAssertEqual(account.state, .error)
        }
    }

    func testRotatedRefreshIsPersistedAndConcurrentRequestsShareOneRefresh() async throws {
        let storage = FixtureAccountStorage()
        let session = fixtureHTTPSession(mode: "rotatingRefresh")
        let trace = session.configuration.httpAdditionalHeaders?["X-Fixture-Trace"] as! String
        let account = BackendAccount(storage: storage, session: session)
        await account.configure(url: "https://success.invalid", publicKey: fixtureKey, environment: .nonproduction)
        await account.requestCode(method: .email, identifier: "synthetic@example.invalid")
        await account.verifyCode("123456")
        let client = try await account.authenticatedClient()
        var expired = fixtureSession(); expired.expiresAt = 1; expired.expiresIn = 0
        try storage.replaceStoredSession(expired)
        async let first: [String] = client.from("teams").select("id").retry(enabled: false).execute().value
        async let second: [String] = client.from("teams").select("id").retry(enabled: false).execute().value
        let result = try await (first, second)
        XCTAssertTrue(result.0.isEmpty && result.1.isEmpty)
        XCTAssertEqual(FixtureAccountURLProtocol.sends(trace, path: "/auth/v1/token"), 1)
        XCTAssertEqual(try storage.storedSession()?.refreshToken, "synthetic-rotated-refresh")
    }

    func testReusedRefreshAndForbiddenSessionConcealAuthority() async throws {
        for mode in ["reusedRefresh", "forbidden"] {
            let storage = FixtureAccountStorage()
            let first = BackendAccount(storage: storage, session: fixtureHTTPSession())
            await first.configure(url: "https://success.invalid", publicKey: fixtureKey, environment: .nonproduction)
            await first.requestCode(method: .email, identifier: "synthetic@example.invalid")
            await first.verifyCode("123456")
            if mode == "reusedRefresh" {
                var expired = fixtureSession(); expired.expiresAt = 1; expired.expiresIn = 0
                try storage.replaceStoredSession(expired)
            }
            let restored = BackendAccount(storage: storage, session: fixtureHTTPSession(mode: mode))
            await restored.restore()
            XCTAssertEqual(restored.state, .error)
            XCTAssertNil(restored.verifiedUserID)
            XCTAssertNil(restored.sessionContextID)
            XCTAssertNil(restored.offlineClipActorID)
        }
    }

    func testTokenProviderRefreshDenialClearsContextAndOfflineAuthority() async throws {
        let storage = FixtureAccountStorage()
        let account = BackendAccount(storage: storage, session: fixtureHTTPSession(mode: "reusedRefresh"))
        await account.configure(url: "https://success.invalid", publicKey: fixtureKey, environment: .nonproduction)
        await account.requestCode(method: .email, identifier: "synthetic@example.invalid")
        await account.verifyCode("123456")
        let client = try await account.authenticatedClient()
        var expired = fixtureSession(); expired.expiresAt = 1; expired.expiresIn = 0
        try storage.replaceStoredSession(expired)
        do {
            let _: [String] = try await client.from("teams").select("id").retry(enabled: false).execute().value
            XCTFail("Confirmed refresh denial must not become an empty success")
        } catch { }
        XCTAssertEqual(account.state, .error)
        XCTAssertNil(account.sessionContextID)
        XCTAssertNil(account.offlineClipActorID)
    }

    func testPriorClientCannotUseEitherAccountAfterSignOutAndNewSignIn() async throws {
        let session = fixtureHTTPSession(mode: "accountSwitch")
        let trace = session.configuration.httpAdditionalHeaders?["X-Fixture-Trace"] as! String
        let account = BackendAccount(storage: FixtureAccountStorage(), session: session)
        await account.configure(url: "https://success.invalid", publicKey: fixtureKey, environment: .nonproduction)
        await account.requestCode(method: .email, identifier: "synthetic@example.invalid")
        await account.verifyCode("123456")
        let old = try await account.authenticatedClient()
        await account.signOut()
        await account.requestCode(method: .email, identifier: "synthetic@example.invalid")
        await account.verifyCode("123456")
        do {
            let _: [String] = try await old.from("teams").select("id").retry(enabled: false).execute().value
            XCTFail("Old client must remain fenced")
        } catch { }
        XCTAssertEqual(FixtureAccountURLProtocol.sends(trace, path: "/rest/v1/teams"), 1)
        XCTAssertEqual(account.verifiedUserID, UUID(uuidString: "d7000000-0000-4000-8000-000000000002"))
    }

    func testCancelledIdentityCheckDoesNotPublishLateAuthentication() async throws {
        let storage = FixtureAccountStorage()
        let account = BackendAccount(storage: storage, session: fixtureHTTPSession(mode: "delayedUser"))
        await account.configure(url: "https://success.invalid", publicKey: fixtureKey, environment: .nonproduction)
        await account.requestCode(method: .email, identifier: "synthetic@example.invalid")
        let task = Task { await account.verifyCode("123456") }
        for _ in 0..<100 where !account.isBusy { try await Task.sleep(for: .milliseconds(5)) }
        task.cancel()
        await task.value
        XCTAssertNil(account.verifiedUserID)
        XCTAssertFalse(account.isBusy)
    }

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
    func testEmailRequestIncludesNativeRedirectAndPKCEChallenge() async throws {
        let account = BackendAccount(storage: FixtureAccountStorage(), session: fixtureHTTPSession(mode: "requireEmailRedirect"))
        await account.configure(url: "https://success.invalid", publicKey: fixtureKey, environment: .nonproduction)
        await account.requestCode(method: .email, identifier: "synthetic@example.invalid")
        XCTAssertNil(account.issue)
        XCTAssertEqual(account.state, .pendingVerification(.email))
    }

    func testEmailLinkAuthenticatesAfterAppRestartWithSavedDeviceChallenge() async throws {
        let storage = FixtureAccountStorage()
        let first = BackendAccount(storage: storage, session: fixtureHTTPSession())
        await first.configure(url: "https://success.invalid", publicKey: fixtureKey, environment: .nonproduction)
        await first.requestCode(method: .email, identifier: "synthetic@example.invalid")
        let restarted = BackendAccount(storage: storage, session: fixtureHTTPSession())
        await restarted.handleEmailLink(URL(string: "com.narayanlekhi.teamstats://auth/callback?code=synthetic-pkce-code")!)
        XCTAssertEqual(restarted.verifiedUserID, fixtureUserID)
        XCTAssertNil(restarted.issue)
        let after = BackendAccount(storage: storage, session: fixtureHTTPSession())
        await after.restore()
        XCTAssertEqual(after.verifiedUserID, fixtureUserID)
    }

    func testEmailLinkRejectsWrongRouteBearerTokensAndUnrequestedChallenges() async throws {
        let account = BackendAccount(storage: FixtureAccountStorage(), session: fixtureHTTPSession())
        await account.configure(url: "https://success.invalid", publicKey: fixtureKey, environment: .nonproduction)
        let valid = URL(string: "com.narayanlekhi.teamstats://auth/callback?code=synthetic-pkce-code")!
        await account.handleEmailLink(valid)
        XCTAssertEqual(account.issue, .invalidEmailLink)
        await account.requestCode(method: .email, identifier: "synthetic@example.invalid")
        for url in ["com.narayanlekhi.teamstats://wrong/callback?code=synthetic", "com.narayanlekhi.teamstats://auth/callback#access_token=synthetic", "com.narayanlekhi.teamstats://auth/callback?code=synthetic&code=other"] {
            await account.handleEmailLink(URL(string: url)!)
            XCTAssertEqual(account.issue, .invalidEmailLink)
            XCTAssertNil(account.verifiedUserID)
        }
    }

    func testEmailLinkCannotAuthenticateDifferentContactAndLeavesNoRestorableSession() async throws {
        let storage = FixtureAccountStorage()
        let account = BackendAccount(storage: storage, session: fixtureHTTPSession())
        await account.configure(url: "https://success.invalid", publicKey: fixtureKey, environment: .nonproduction)
        await account.requestCode(method: .email, identifier: "different@example.invalid")
        await account.handleEmailLink(URL(string: "com.narayanlekhi.teamstats://auth/callback?code=synthetic-pkce-code")!)
        XCTAssertEqual(account.issue, .invalidEmailLink)
        XCTAssertNil(account.verifiedUserID)
        let after = BackendAccount(storage: storage, session: fixtureHTTPSession())
        await after.restore()
        XCTAssertEqual(after.state, .signedOut)
    }

    func testSigningOutBeforeEmailLinkInvalidatesPendingDeviceChallenge() async throws {
        let account = BackendAccount(storage: FixtureAccountStorage(), session: fixtureHTTPSession())
        await account.configure(url: "https://success.invalid", publicKey: fixtureKey, environment: .nonproduction)
        await account.requestCode(method: .email, identifier: "synthetic@example.invalid")
        await account.signOut()
        await account.handleEmailLink(URL(string: "com.narayanlekhi.teamstats://auth/callback?code=synthetic-pkce-code")!)
        XCTAssertEqual(account.issue, .invalidEmailLink)
        XCTAssertNil(account.verifiedUserID)
    }

    func testTransientAuthenticatedCheckCanRetryTheExistingSession() async throws {
        let account = BackendAccount(storage: FixtureAccountStorage(), session: fixtureHTTPSession(mode: "transientAfterVerification"))
        await account.configure(url: "https://success.invalid", publicKey: fixtureKey, environment: .nonproduction)
        await account.requestCode(method: .email, identifier: "synthetic@example.invalid")
        await account.verifyCode("123456")
        XCTAssertEqual(account.verifiedUserID, fixtureUserID)
        do { _ = try await account.authenticatedClient(); XCTFail("The transient failed check must not authorize a command") }
        catch { XCTAssertEqual(account.issue, .provider) }
        XCTAssertNil(account.verifiedUserID)
        XCTAssertEqual(account.sessionContextID, fixtureUserID)
        do {
            _ = try await account.authenticatedClient()
            XCTAssertEqual(account.verifiedUserID, fixtureUserID)
        } catch { XCTFail("An explicit retry must recheck the existing session without a new sign-in") }
        XCTAssertEqual(account.sessionContextID, fixtureUserID)
        await account.signOut()
        XCTAssertNil(account.sessionContextID)
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

    func testFailedNewContactRequestCannotVerifyOldChallenge() async throws {
        let account = BackendAccount(storage: FixtureAccountStorage(), session: fixtureHTTPSession())
        await account.configure(url: "https://success.invalid", publicKey: fixtureKey, environment: .nonproduction)
        await account.requestCode(method: .email, identifier: "synthetic@example.invalid")
        XCTAssertEqual(account.pendingMethod, .email)
        await account.requestCode(method: .phone, identifier: "+12025550100")
        XCTAssertEqual(account.issue, .phoneDeliveryDisabled)
        XCTAssertNil(account.pendingMethod)
        await account.verifyCode("123456")
        XCTAssertEqual(account.issue, .noPendingCode)
        XCTAssertNil(account.verifiedUserID)
    }

    func testInitialSecureStorageFailureCanRecoverByExplicitRetry() async throws {
        let storage = FixtureAccountStorage()
        let first = BackendAccount(storage: storage, session: fixtureHTTPSession())
        await first.configure(url: "https://success.invalid", publicKey: fixtureKey, environment: .nonproduction)
        await first.requestCode(method: .email, identifier: "synthetic@example.invalid")
        await first.verifyCode("123456")
        storage.rejectReads(true)
        let restarted = BackendAccount(storage: storage, session: fixtureHTTPSession())
        await restarted.restoreIfNeeded()
        XCTAssertEqual(restarted.issue, .storage)
        XCTAssertNil(restarted.configuration)
        storage.rejectReads(false)
        await restarted.restore()
        XCTAssertEqual(restarted.verifiedUserID, fixtureUserID)
        XCTAssertNil(restarted.issue)
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

    func testConcurrentVerificationDoesNotBecomeConfirmedDenial() async throws {
        let account = BackendAccount(storage: FixtureAccountStorage(), session: fixtureHTTPSession(mode: "delayedUser"))
        await account.configure(url: "https://success.invalid", publicKey: fixtureKey, environment: .nonproduction)
        await account.requestCode(method: .email, identifier: "synthetic@example.invalid")
        await account.verifyCode("123456")
        let first = Task { try await account.authenticatedClient() }
        for _ in 0..<100 where !account.isBusy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(account.isBusy)
        do {
            _ = try await account.authenticatedClient()
            XCTFail("Concurrent verification must not issue a remote command client")
        } catch { XCTAssertEqual(error as? AccountIssue, .provider) }
        XCTAssertEqual(account.sessionContextID, fixtureUserID)
        XCTAssertEqual(account.offlineClipActorID, fixtureUserID)
        _ = try await first.value
        XCTAssertEqual(account.verifiedUserID, fixtureUserID)
    }

    func testRevocationStampWriteFailureReportsSecureStorageFailure() async {
        let storage = FixtureAccountStorage()
        let original = BackendAccount(storage: storage, session: fixtureHTTPSession())
        await original.configure(url: "https://success.invalid", publicKey: fixtureKey, environment: .nonproduction)
        await original.requestCode(method: .email, identifier: "synthetic@example.invalid")
        await original.verifyCode("123456")
        storage.rejectStampWrites()
        let denied = BackendAccount(storage: storage, session: fixtureHTTPSession(mode: "revoked"))
        await denied.restore()
        XCTAssertNil(denied.offlineClipActorID)
        XCTAssertNil(denied.sessionContextID)
        XCTAssertEqual(denied.issue, .storage)
        let restart = BackendAccount(storage: storage, session: fixtureHTTPSession(mode: "offlineUser"))
        await restart.restore()
        XCTAssertNil(restart.offlineClipActorID)
        XCTAssertNil(restart.sessionContextID)
    }

    func testSignOutStampWriteFailureLocksOfflineRestart() async {
        let storage = FixtureAccountStorage()
        let original = BackendAccount(storage: storage, session: fixtureHTTPSession())
        await original.configure(url: "https://success.invalid", publicKey: fixtureKey, environment: .nonproduction)
        await original.requestCode(method: .email, identifier: "synthetic@example.invalid")
        await original.verifyCode("123456")
        storage.rejectStampWrites()
        await original.signOut()
        XCTAssertEqual(original.issue, .storage)
        XCTAssertNil(original.offlineClipActorID)
        XCTAssertNil(original.sessionContextID)
        let restart = BackendAccount(storage: storage, session: fixtureHTTPSession(mode: "offlineUser"))
        await restart.restore()
        XCTAssertNil(restart.offlineClipActorID)
        XCTAssertNil(restart.sessionContextID)
    }

    func testOfflineStampCannotRestoreDifferentStoredSessionIdentity() async throws {
        let storage = FixtureAccountStorage()
        let original = BackendAccount(storage: storage, session: fixtureHTTPSession())
        await original.configure(url: "https://success.invalid", publicKey: fixtureKey, environment: .nonproduction)
        await original.requestCode(method: .email, identifier: "synthetic@example.invalid")
        await original.verifyCode("123456")
        var different = fixtureSession()
        different.user.id = UUID(uuidString: "d7000000-0000-4000-8000-000000000002")!
        try storage.replaceStoredSession(different)
        let restart = BackendAccount(storage: storage, session: fixtureHTTPSession(mode: "offlineUser"))
        await restart.restore()
        XCTAssertNil(restart.offlineClipActorID)
        XCTAssertNil(restart.sessionContextID)
        let online = BackendAccount(storage: storage, session: fixtureHTTPSession(mode: "differentUser"))
        await online.restore()
        XCTAssertEqual(online.verifiedUserID, different.user.id)
        XCTAssertEqual(online.offlineClipActorID, different.user.id)
    }

    func testOfflineClipActorSurvivesTransientRestartButKnownDenialLocksIt() async {
        let storage = FixtureAccountStorage()
        let original = BackendAccount(storage: storage, session: fixtureHTTPSession())
        await original.configure(url: "https://success.invalid", publicKey: fixtureKey, environment: .nonproduction)
        await original.requestCode(method: .email, identifier: "synthetic@example.invalid")
        await original.verifyCode("123456")
        XCTAssertEqual(original.offlineClipActorID, fixtureUserID)
        let offline = BackendAccount(storage: storage, session: fixtureHTTPSession(mode: "offlineUser"))
        await offline.restore()
        XCTAssertNil(offline.verifiedUserID)
        XCTAssertNil(offline.sessionContextID)
        XCTAssertEqual(offline.offlineClipActorID, fixtureUserID)
        let denied = BackendAccount(storage: storage, session: fixtureHTTPSession(mode: "revoked"))
        await denied.restore()
        XCTAssertNil(denied.offlineClipActorID)
        XCTAssertNil(denied.sessionContextID)
        let restarted = BackendAccount(storage: storage, session: fixtureHTTPSession(mode: "offlineUser"))
        await restarted.restore()
        XCTAssertNil(restarted.offlineClipActorID)
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
    private var failReads = false
    private var failStampWrites = false
    func storedSession() throws -> Session? {
        lock.lock(); defer { lock.unlock() }
        return try values.first(where: { $0.key.hasPrefix("session.v1.") && !$0.key.hasSuffix("-code-verifier") && !$0.key.hasSuffix(".email-link") }).map { try JSONDecoder().decode(Session.self, from: $0.value) }
    }
    func replaceStoredSession(_ session: Session) throws {
        lock.lock(); defer { lock.unlock() }
        let key = values.keys.first { $0.hasPrefix("session.v1.") && !$0.hasSuffix("-code-verifier") && !$0.hasSuffix(".email-link") }!
        values[key] = try JSONEncoder().encode(session)
    }
    func rejectStampWrites() { lock.lock(); defer { lock.unlock() }; failStampWrites = true }
    func rejectReads(_ reject: Bool) {
        lock.lock(); defer { lock.unlock() }; failReads = reject
    }
    init(failSessionWrites: Bool = false) { self.failSessionWrites = failSessionWrites }
    func store(key: String, value: Data) throws {
        lock.lock(); defer { lock.unlock() }
        if failStampWrites && key.hasPrefix("offline-actor.v1.") { throw AccountIssue.storage }
        if failSessionWrites && key.hasPrefix("session.v1.") && !key.hasSuffix("-code-verifier") && !key.hasSuffix(".email-link") { throw AccountIssue.storage }
        values[key] = value
    }
    func retrieve(key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        if failReads { throw AccountIssue.storage }
        return values[key]
    }
    func remove(key: String) throws {
        lock.lock(); defer { lock.unlock() }; values[key] = nil
    }
}

private func fixtureHTTPSession(mode: String? = nil) -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FixtureAccountURLProtocol.self]
    if let mode { configuration.httpAdditionalHeaders = ["X-Fixture-Mode": mode, "X-Fixture-Trace": UUID().uuidString] }
    return URLSession(configuration: configuration)
}

private final class FixtureAccountURLProtocol: URLProtocol, @unchecked Sendable {
    private static let counterLock = NSLock()
    nonisolated(unsafe) private static var otpCounts: [String: Int] = [:]
    nonisolated(unsafe) private static var requestCounts: [String: [String: Int]] = [:]
    static func sends(_ trace: String, path: String) -> Int {
        counterLock.lock(); defer { counterLock.unlock() }; return requestCounts[trace]?[path] ?? 0
    }
    static func otpSends(_ trace: String) -> Int {
        counterLock.lock(); defer { counterLock.unlock() }; return otpCounts[trace] ?? 0
    }
    nonisolated(unsafe) private static var userChecks: [String: Int] = [:]
    private static func nextUserCheck(_ trace: String) -> Int {
        counterLock.lock(); defer { counterLock.unlock() }
        let count = (userChecks[trace] ?? 0) + 1
        if count >= 5 { userChecks.removeValue(forKey: trace) } else { userChecks[trace] = count }
        return count
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let trace = request.value(forHTTPHeaderField: "X-Fixture-Trace") ?? "untraced"
        Self.counterLock.lock()
        Self.requestCounts[trace, default: [:]][request.url!.path, default: 0] += 1
        Self.counterLock.unlock()
        let mode = request.value(forHTTPHeaderField: "X-Fixture-Mode")
        if mode?.hasPrefix("lostOTP") == true, request.url?.path.hasSuffix("/otp") == true {
            Self.counterLock.lock()
            let trace = request.value(forHTTPHeaderField: "X-Fixture-Trace")!
            Self.otpCounts[trace, default: 0] += 1
            Self.counterLock.unlock()
            if let status = Int(mode!.dropFirst("lostOTP".count)) {
                client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data("{}".utf8))
                client?.urlProtocolDidFinishLoading(self)
            } else { client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)) }
            return
        }
        if ["accountSwitch", "reusedRefresh"].contains(mode ?? ""), request.url?.path == "/rest/v1/teams",
           request.value(forHTTPHeaderField: "Authorization") != (mode == "accountSwitch" ? "Bearer synthetic-second-user-token" : "Bearer synthetic-access-token-not-a-real-credential") {
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{\"code\":\"42501\",\"message\":\"Synthetic anonymous denial\"}".utf8))
            client?.urlProtocolDidFinishLoading(self); return
        }
        let denied = ["revoked", "forbidden"].contains(mode ?? "") && request.url?.path.hasSuffix("/user") == true
        let logoutFailure = mode == "logoutFailure" && request.url?.path.hasSuffix("/logout") == true
        let refreshFailure = mode == "refreshFailure" && request.url?.path.hasSuffix("/token") == true
        let missingEmailRedirect = mode == "requireEmailRedirect" && request.url?.path.hasSuffix("/otp") == true
            && URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "redirect_to" })?.value != "com.narayanlekhi.teamstats://auth/callback"
        let transientFailure = mode == "transientAfterVerification" && request.url?.path.hasSuffix("/user") == true
            && (2...4).contains(Self.nextUserCheck(request.value(forHTTPHeaderField: "X-Fixture-Trace") ?? "synthetic"))
        let failed = (mode == "offlineUser" && request.url?.path.hasSuffix("/user") == true) || request.url?.host == "failure.invalid" || denied || logoutFailure || refreshFailure || missingEmailRedirect || transientFailure
        if mode == "reusedRefresh", request.url?.path.hasSuffix("/token") == true {
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: ["Content-Type":"application/json","X-Supabase-Api-Version":"2024-01-01"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{\"error_code\":\"refresh_token_already_used\",\"code\":\"refresh_token_already_used\",\"msg\":\"Synthetic reused credential\"}".utf8))
            client?.urlProtocolDidFinishLoading(self); return
        }
        let status = denied ? (mode == "forbidden" ? 403 : 401) : (failed ? 503 : 200)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        let body: Data
        if failed {
            body = Data("{\"msg\":\"Synthetic denied response\"}".utf8)
        } else if request.url?.path.hasSuffix("/token") == true {
            var session = fixtureSession()
            if mode == "rotatingRefresh" { session.refreshToken = "synthetic-rotated-refresh" }
            body = try! AuthClient.Configuration.jsonEncoder.encode(session)
        } else if request.url?.host == "confirmation.invalid", request.url?.path.hasSuffix("/verify") == true {
            body = try! AuthClient.Configuration.jsonEncoder.encode(fixtureUser())
        } else if request.url?.path.hasSuffix("/verify") == true {
            var session = fixtureSession()
            if mode == "accountSwitch", Self.sends(trace, path: "/auth/v1/verify") > 1 { session.user.id = UUID(uuidString: "d7000000-0000-4000-8000-000000000002")!; session.accessToken = "synthetic-second-user-token"; session.refreshToken = "synthetic-second-refresh-token" }
            if request.url?.host == "expired.invalid" { session.expiresAt = 1_700_000_000; session.expiresIn = 0 }
            body = try! AuthClient.Configuration.jsonEncoder.encode(session)
        } else if request.url?.path.hasSuffix("/user") == true {
            var user = fixtureUser()
            if mode == "differentUser" || (mode == "accountSwitch" && Self.sends(trace, path: "/auth/v1/verify") > 1) { user.id = UUID(uuidString: "d7000000-0000-4000-8000-000000000002")! }
            body = try! AuthClient.Configuration.jsonEncoder.encode(user)
        } else if request.url?.path.hasPrefix("/rest/v1/") == true { body = Data("[]".utf8) }
        else { body = Data("{}".utf8) }
        let deliver = { [self] in
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
        if mode == "delayedUser", request.url?.path.hasSuffix("/user") == true {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2, execute: deliver)
        } else { deliver() }
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
