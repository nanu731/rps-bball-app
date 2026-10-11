import XCTest
import Foundation
import Supabase
@testable import TeamStats

/// Opt-in, synthetic loopback services only. A trusted generated test OTP proves
/// native SDK/session/RPC compatibility, not typed inbox or real SMS delivery.
@MainActor
final class LocalServerIntegrationTests: XCTestCase {
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
}
private struct RosterVersion: Decodable { let version: Int64 }
private enum LocalFixtureIssue: Error { case unsafeConfiguration }
