import XCTest
import Foundation
import Supabase
@testable import TeamStats

/// Opt-in, synthetic loopback services only. A trusted generated test OTP proves
/// native SDK/session/RPC compatibility, not typed inbox or real SMS delivery.
@MainActor
final class LocalServerIntegrationTests: XCTestCase {
    func testDefaultEmailLinkWithRealLocalAuthAndDevicePKCE() async throws {
        guard let text = ProcessInfo.processInfo.environment["TEAMSTATS_LOCAL_TEST_FIXTURE"] else {
            throw XCTSkip("Isolated local server fixture is not configured.")
        }
        let fixture = try JSONDecoder().decode(LocalServerFixture.self, from: Data(text.utf8))
        guard let mail = fixture.mailpitURL, mail.host == "127.0.0.1", mail.scheme == "http",
              let api = URL(string: fixture.apiRoot), api.host == "127.0.0.1",
              fixture.syntheticEmail.hasSuffix("@example.invalid") else { throw LocalFixtureIssue.unsafeConfiguration }
        let store = SecureSessionStorage(service: "TeamStats.local-email.tests." + UUID().uuidString)
        let account = BackendAccount(storage: store)
        await account.configure(url: fixture.apiRoot, publicKey: fixture.publishableKey, environment: .localTest)
        await account.requestCode(method: .email, identifier: fixture.syntheticEmail)
        XCTAssertNil(account.issue)
        XCTAssertEqual(account.pendingMethod, .email)
        var messageID: String?
        for _ in 0..<10 {
            let (bytes, response) = try await URLSession.shared.data(from: mail.appendingPathComponent("api/v1/messages"))
            guard (response as? HTTPURLResponse)?.statusCode == 200, bytes.count < 1_048_576 else { throw LocalFixtureIssue.unavailable }
            let list = try JSONDecoder().decode(LocalMailList.self, from: bytes)
            messageID = list.messages.first { $0.to.contains { $0.address == fixture.syntheticEmail } }?.id
            if messageID != nil { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        let id = try XCTUnwrap(messageID)
        let (bytes, response) = try await URLSession.shared.data(from: mail.appendingPathComponent("api/v1/message/" + id))
        guard (response as? HTTPURLResponse)?.statusCode == 200, bytes.count < 1_048_576 else { throw LocalFixtureIssue.unavailable }
        let message = try JSONDecoder().decode(LocalMailBody.self, from: bytes)
        let html = message.html.replacingOccurrences(of: "&amp;", with: "&")
        let regex = try NSRegularExpression(pattern: "https?[^\\s\"<>]+")
        let links = regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { Range($0.range, in: html).flatMap { URL(string: String(html[$0])) } }
        let link = try XCTUnwrap(links.first { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "token" } == true })
        guard link.host == api.host, link.port == api.port,
              URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "redirect_to" })?.value == BackendAccount.emailRedirectURL.absoluteString else { throw LocalFixtureIssue.unsafeConfiguration }
        // Capture the real server redirect without opening a browser or exposing its code.
        let session = URLSession(configuration: .ephemeral, delegate: LocalRedirectStopper(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (_, redirectResponse) = try await session.data(from: link)
        let http = try XCTUnwrap(redirectResponse as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 303)
        let callback = try XCTUnwrap(http.value(forHTTPHeaderField: "Location").flatMap(URL.init(string:)))
        let restarted = BackendAccount(storage: store)
        await restarted.handleEmailLink(callback)
        XCTAssertNil(restarted.issue)
        XCTAssertEqual(restarted.verifiedUserID, fixture.syntheticOwnerAuthUUID)
        await restarted.signOut()
        XCTAssertEqual(restarted.state, .signedOut)
    }

    func testNativeVerifiedSessionAndRosterRoundTrip() async throws {
        guard let text = ProcessInfo.processInfo.environment["TEAMSTATS_LOCAL_TEST_FIXTURE"] else {
            throw XCTSkip("Isolated local server fixture is not configured.")
        }
        let fixture = try JSONDecoder().decode(LocalServerFixture.self, from: Data(text.utf8))
        guard let url = URL(string: fixture.apiRoot), url.host == "127.0.0.1",
              fixture.syntheticEmail.hasSuffix("@example.invalid") else {
            throw LocalFixtureIssue.unsafeConfiguration
        }
        let storage = SecureSessionStorage(service: "TeamStats.local-server.tests." + UUID().uuidString)
        let options = SupabaseClientOptions(auth: .init(storage: storage, storageKey: "synthetic-session", autoRefreshToken: false), global: .init(logger: nil))
        defer { try? storage.remove(key: "synthetic-session") }
        let client = SupabaseClient(supabaseURL: url, supabaseKey: fixture.publishableKey, options: options)
        let verified = try await client.auth.verifyOTP(email: fixture.syntheticEmail, token: fixture.syntheticEmailTestCode, type: .email)
        XCTAssertEqual(verified.user.id, fixture.syntheticOwnerAuthUUID)
        let restarted = SupabaseClient(supabaseURL: url, supabaseKey: fixture.publishableKey, options: options)
        let restoredUser = try await restarted.auth.user()
        XCTAssertEqual(restoredUser.id, fixture.syntheticOwnerAuthUUID)

        let model = TeamAdministration(authenticatedClient: { client })
        await model.loadTeams()
        XCTAssertNil(model.issue)
        let team = try XCTUnwrap(model.teams.first { $0.id == fixture.syntheticTeamID })
        await model.selectTeam(team)
        XCTAssertEqual(model.access?.isOwner, true)
        XCTAssertNil(model.issue)
        let previousIDs = Set(model.roster.map(\.id))
        let label = "TEST ONLY native integration " + UUID().uuidString.prefix(8)
        let saved = await model.saveRoster(entry: nil, displayName: label, jerseyNumber: "0")
        XCTAssertTrue(saved)
        XCTAssertNil(model.issue)
        let entry = try XCTUnwrap(model.roster.first { $0.displayName == label })
        XCTAssertFalse(previousIDs.contains(entry.id))
        let edited = await model.saveRoster(entry: entry, displayName: label + " edited", jerseyNumber: "00")
        XCTAssertTrue(edited)
        XCTAssertNil(model.issue)
        let updated = try XCTUnwrap(model.roster.first { $0.id == entry.id })
        XCTAssertEqual(updated.version, entry.version + 1)
        XCTAssertEqual(model.roster.filter { $0.id == entry.id }.count, 1)
        await model.archiveRoster(updated)
        XCTAssertNil(model.issue)
        XCTAssertNotNil(model.roster.first { $0.id == entry.id }?.archivedAt)
        XCTAssertTrue(previousIDs.isSubset(of: Set(model.roster.map(\.id))))
        let history: [RosterVersion] = try await client.from("roster_entry_revisions").select("version")
            .eq("roster_id", value: entry.id.uuidString).order("version").execute().value
        XCTAssertEqual(history.map(\.version), [1, 2, 3])
        try await client.auth.signOut(scope: .local)
    }
}

private struct LocalServerFixture: Decodable {
    let apiRoot: String
    let publishableKey: String
    let syntheticEmail: String
    let syntheticEmailTestCode: String
    let syntheticOwnerAuthUUID: UUID
    let syntheticTeamID: UUID
    let mailpitURL: URL?
}
private struct RosterVersion: Decodable { let version: Int64 }
private enum LocalFixtureIssue: Error { case unsafeConfiguration, unavailable }
private struct LocalMailList: Decodable {
    let messages: [Message]
    struct Message: Decodable {
        let id: String
        let to: [Recipient]
        enum CodingKeys: String, CodingKey { case id = "ID", to = "To" }
    }
    struct Recipient: Decodable {
        let address: String
        enum CodingKeys: String, CodingKey { case address = "Address" }
    }
}
private struct LocalMailBody: Decodable {
    let html: String
    enum CodingKeys: String, CodingKey { case html = "HTML" }
}
private final class LocalRedirectStopper: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
