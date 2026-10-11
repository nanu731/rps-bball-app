import XCTest
import Foundation
import Supabase
@testable import TeamStats

@MainActor
final class AdministrationTests: XCTestCase {
    func testAdmissionRequestReportsPendingWithoutClaimingTeamAccess() async {
        let fixture = AdministrationFixture()
        let model = fixture.model()
        await model.requestAdmission(teamID: fixtureTeamID.uuidString)
        XCTAssertEqual(model.admissionStatus, .pending)
        XCTAssertNil(model.access)
        XCTAssertTrue(model.teams.isEmpty)
        XCTAssertNil(model.issue)
        XCTAssertEqual(fixture.commands.first?.parameters["p_team_id"] as? String, fixtureTeamID.uuidString)
    }

    func testTeamDiscoveryUsesServerRowsAndEmptyResponseIsHonest() async {
        let fixture = AdministrationFixture(mode: .empty)
        let model = fixture.model()
        await model.loadTeams()
        XCTAssertTrue(model.teams.isEmpty)
        XCTAssertNil(model.selectedTeam)
        XCTAssertNil(model.issue)
    }

    func testRosterSaveUsesFreshServerIdentityAndLoadedAccessRevision() async throws {
        let fixture = AdministrationFixture()
        let model = fixture.model()
        await load(model)
        await model.saveRoster(entry: nil, displayName: " Synthetic player ", jerseyNumber: " 12 ")
        XCTAssertNil(model.issue)
        XCTAssertNotNil(model.confirmation)
        XCTAssertEqual(model.roster.first?.id, fixtureRosterID)
        let command = try XCTUnwrap(fixture.commands.first)
        XCTAssertEqual(command.name, "team_save_roster")
        XCTAssertEqual(command.parameters["p_expected_access_revision"] as? Int, 7)
        XCTAssertEqual(command.parameters["p_display_name"] as? String, "Synthetic player")
        XCTAssertTrue(command.parameters["p_roster_id"] is NSNull)
        XCTAssertTrue(command.parameters["p_expected_version"] is NSNull)
    }

    func testStaleRosterCommandNeverClaimsSuccessAndReloadUsesNewRevision() async throws {
        let fixture = AdministrationFixture(mode: .staleOnce)
        let model = fixture.model()
        await load(model)
        let entry = try XCTUnwrap(model.roster.first)
        await model.archiveRoster(entry)
        XCTAssertEqual(model.issue, .conflict)
        XCTAssertNil(model.confirmation)
        XCTAssertNil(model.access)
        XCTAssertFalse(model.issue!.localizedDescription.contains("SENSITIVE_FIXTURE_PAYLOAD"))
        await model.reload()
        XCTAssertNil(model.issue)
        XCTAssertEqual(model.access?.accessRevision, 8)
        await model.archiveRoster(try XCTUnwrap(model.roster.first))
        XCTAssertNil(model.issue)
        XCTAssertEqual(fixture.commands.count, 2)
        XCTAssertEqual(fixture.commands[0].parameters["p_expected_version"] as? Int, 3)
        XCTAssertEqual(fixture.commands[1].parameters["p_expected_access_revision"] as? Int, 8)
        XCTAssertEqual(fixture.commands[1].parameters["p_roster_id"] as? String, fixtureRosterID.uuidString)
    }

    func testSeparateMembershipCapabilityAndBoundedDelegationCommands() async throws {
        let fixture = AdministrationFixture()
        let model = fixture.model()
        await load(model)
        await model.setMembership(userID: fixtureMemberID.uuidString, status: .active)
        await model.setCapability(userID: fixtureMemberID.uuidString, capability: .statsReview, enabled: true, expiry: Date(timeIntervalSince1970: 2_500_000_000))
        await model.setCapability(userID: fixtureMemberID.uuidString, capability: .statsReview, enabled: false, expiry: nil)
        await model.delegate(userID: fixtureMemberID.uuidString, capabilities: [.rosterManage, .statsPublish], expiry: Date(timeIntervalSince1970: 2_500_000_000))
        await model.revokeDelegation(try XCTUnwrap(model.delegations.first))
        XCTAssertNil(model.issue)
        XCTAssertEqual(fixture.commands.map(\.name), ["team_set_membership", "team_set_capability", "team_set_capability", "team_delegate", "team_revoke_delegation"])
        for command in fixture.commands {
            XCTAssertEqual(command.parameters["p_expected_access_revision"] as? Int, 7)
            XCTAssertEqual(command.parameters["p_team_id"] as? String, fixtureTeamID.uuidString)
        }
        XCTAssertEqual(fixture.commands[0].parameters["p_status"] as? String, "active")
        XCTAssertEqual(fixture.commands[1].parameters["p_capability"] as? String, "stats.review")
        XCTAssertEqual(fixture.commands[1].parameters["p_enabled"] as? Bool, true)
        XCTAssertEqual(fixture.commands[2].parameters["p_enabled"] as? Bool, false)
        XCTAssertEqual(fixture.commands[3].parameters["p_allowed_capabilities"] as? [String], ["roster.manage", "stats.publish"])
        XCTAssertNotNil(fixture.commands[3].parameters["p_expires_at"] as? String)
        XCTAssertEqual(fixture.commands[4].parameters["p_envelope_id"] as? String, fixtureEnvelopeID.uuidString)
    }

    func testSelfOrOwnerChangeAndInvalidRosterNeverSendMutation() async {
        let fixture = AdministrationFixture()
        let model = fixture.model()
        await load(model)
        await model.setMembership(userID: fixtureOwnerID.uuidString, status: .removed)
        XCTAssertEqual(model.issue, .invalidAccountID)
        await model.setCapability(userID: fixtureOwnerID.uuidString, capability: .membersManage, enabled: true, expiry: nil)
        XCTAssertEqual(model.issue, .invalidAccountID)
        await model.saveRoster(entry: nil, displayName: "", jerseyNumber: "12")
        XCTAssertEqual(model.issue, .invalidRoster)
        XCTAssertTrue(fixture.commands.isEmpty)
    }

    func testDeniedMutationClearsSnapshotAndRetryReloadsWithoutReplayingIt() async {
        let fixture = AdministrationFixture(mode: .denied)
        let model = fixture.model()
        await load(model)
        await model.setMembership(userID: fixtureMemberID.uuidString, status: .pending)
        XCTAssertEqual(model.issue, .denied)
        XCTAssertNil(model.confirmation)
        XCTAssertNil(model.access)
        await model.reload()
        XCTAssertNil(model.issue)
        XCTAssertEqual(fixture.commands.count, 1)
    }

    func testServerConfirmedSaveSurvivesReloadFailureAndRetryDoesNotDuplicateAdd() async {
        let fixture = AdministrationFixture(mode: .reloadFailureOnce)
        let model = fixture.model()
        await load(model)
        await model.saveRoster(entry: nil, displayName: "Synthetic player", jerseyNumber: "12")
        XCTAssertEqual(model.issue, .server)
        XCTAssertNotNil(model.confirmation)
        XCTAssertNil(model.access)
        await model.reload()
        XCTAssertNil(model.issue)
        XCTAssertEqual(fixture.commands.count, 1)
        XCTAssertEqual(model.roster.first?.id, fixtureRosterID)
    }

    func testRosterFetchPagesUntilCompleteInsteadOfSilentlyTruncating() async {
        let fixture = AdministrationFixture(mode: .pagination)
        let model = fixture.model()
        await load(model)
        XCTAssertNil(model.issue)
        XCTAssertEqual(model.roster.count, 101)
        XCTAssertEqual(fixture.rosterOffsets, [0, 100])
    }

    func testDelegatedGrantAuthorityStaysSeparateAndExpiryIsBounded() async {
        let fixture = AdministrationFixture(mode: .delegate)
        let model = fixture.model()
        await load(model)
        XCTAssertEqual(model.access?.grantableCapabilities, [.rosterManage])
        XCTAssertTrue(model.access?.can(.statsReview) == true)
        XCTAssertFalse(model.access?.can(.rosterManage) == true)
        await model.setCapability(userID: fixtureMemberID.uuidString, capability: .rosterManage, enabled: true, expiry: Date(timeIntervalSince1970: 2_500_000_000))
        XCTAssertEqual(model.issue, .invalidExpiry)
        XCTAssertTrue(fixture.commands.isEmpty)
        await model.setCapability(userID: fixtureMemberID.uuidString, capability: .rosterManage, enabled: true, expiry: Date(timeIntervalSince1970: 1_900_000_000))
        XCTAssertNil(model.issue)
        XCTAssertEqual(fixture.commands.count, 1)
    }

    func testAmbiguousMutationFailureIsNotAutomaticallyReplayed() async {
        let fixture = AdministrationFixture(mode: .ambiguousSave)
        let model = fixture.model()
        await load(model)
        let confirmed = await model.saveRoster(entry: nil, displayName: "Synthetic player", jerseyNumber: "12")
        XCTAssertFalse(confirmed)
        XCTAssertEqual(model.issue, .server)
        XCTAssertNil(model.confirmation)
        XCTAssertEqual(fixture.commands.count, 1)
        await model.reload()
        XCTAssertEqual(fixture.commands.count, 1)
        XCTAssertNil(model.issue)
    }

    private func load(_ model: TeamAdministration) async {
        await model.loadTeams()
        guard let team = model.teams.first else { XCTFail("Synthetic team must be discovered"); return }
        await model.selectTeam(team)
    }
}

private let fixtureTeamID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
private let fixtureOwnerID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
private let fixtureMemberID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
private let fixtureRosterID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
private let fixtureEnvelopeID = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!

// Synthetic HTTP responses exercise the real SDK/model seam. They do not prove
// deployed Supabase authorization, verified owner identity or provider delivery.
private final class AdministrationFixture: @unchecked Sendable {
    enum Mode { case standard, empty, staleOnce, denied, reloadFailureOnce, pagination, delegate, ambiguousSave }
    struct Command { let name: String; let parameters: [String: Any] }
    private let lock = NSLock()
    private let mode: Mode
    private var commandValues: [Command] = []
    private var offsets: [Int] = []
    private var didFail = false
    let key = UUID().uuidString
    init(mode: Mode = .standard) { self.mode = mode }
    var commands: [Command] { lock.withLock { commandValues } }
    var rosterOffsets: [Int] { lock.withLock { offsets } }

    @MainActor func model() -> TeamAdministration {
        AdministrationURLProtocol.registry.insert(self)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AdministrationURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Administration-Fixture": key]
        let client = SupabaseClient(supabaseURL: URL(string: "https://administration.invalid")!,
            supabaseKey: "sb_publishable_synthetic_fixture", options: .init(
                auth: .init(autoRefreshToken: false),
                global: .init(session: URLSession(configuration: configuration), logger: nil)))
        return TeamAdministration(authenticatedClient: { client })
    }

    func response(_ request: URLRequest) -> (Int, Data) {
        lock.lock()
        defer { lock.unlock() }
        let name = request.url!.lastPathComponent
        if request.url!.path.contains("/rpc/") {
            if name == "team_access" {
                return json(["team_id": fixtureTeamID.uuidString, "user_id": mode == .delegate ? "77777777-7777-4777-8777-777777777777" : fixtureOwnerID.uuidString, "is_owner": mode != .delegate,
                    "access_revision": mode == .staleOnce && didFail ? 8 : 7, "capabilities": mode == .delegate ? ["stats.review"] : [], "grant_envelopes": mode == .delegate ? [["id": fixtureEnvelopeID.uuidString, "allowed_capabilities": ["roster.manage"], "expires_at": "2040-01-01T00:00:00Z"]] : []])
            }
            let body = request.httpBody ?? readBodyStream(request.httpBodyStream)
            let parameters = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
            commandValues.append(Command(name: name, parameters: parameters))
            if mode == .denied || (mode == .staleOnce && !didFail) {
                didFail = true
                return json(["code": mode == .denied ? "42501" : "40001", "message": "SENSITIVE_FIXTURE_PAYLOAD", "details": "SENSITIVE_FIXTURE_PAYLOAD", "hint": NSNull()], status: 400)
            }
            if mode == .ambiguousSave { return json(["code": "503", "message": "SENSITIVE_FIXTURE_PAYLOAD"], status: 503) }
            if name == "team_request_membership" { return (200, Data("\"pending\"".utf8)) }
            if name == "team_save_roster" { return (200, Data("\"\(fixtureRosterID.uuidString)\"".utf8)) }
            if name == "team_delegate" { return (200, Data("\"\(fixtureEnvelopeID.uuidString)\"".utf8)) }
            return (200, Data())
        }
        if name == "teams" {
            if mode == .reloadFailureOnce && !commandValues.isEmpty && !didFail {
                didFail = true
                return json(["code": "XX000", "message": "SENSITIVE_FIXTURE_PAYLOAD"], status: 400)
            }
            return json(mode == .empty ? [] : [["id": fixtureTeamID.uuidString, "name": "Synthetic team", "owner_auth_uuid": fixtureOwnerID.uuidString, "access_revision": mode == .staleOnce && didFail ? 8 : 7]])
        }
        if name == "roster_entries" {
            let offset = Int(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "offset" })?.value ?? "0") ?? 0
            offsets.append(offset)
            if mode == .pagination { return json((offset..<min(offset + 100, 101)).map { rosterRow(id: String(format: "44444444-4444-4444-8444-%012d", $0)) }) }
            return json([rosterRow(id: fixtureRosterID.uuidString)])
        }
        if name == "team_memberships" { return json([["user_id": fixtureMemberID.uuidString, "status": "active"]]) }
        if name == "delegation_envelopes" {
            return json([["id": fixtureEnvelopeID.uuidString, "delegate_user_id": fixtureMemberID.uuidString,
                "allowed_capabilities": ["roster.manage"], "expires_at": "2049-03-22T04:26:40Z", "revoked_at": NSNull()]])
        }
        return json([])
    }
    private func rosterRow(id: String) -> [String: Any] {
        ["id": id, "team_id": fixtureTeamID.uuidString, "display_name": "Synthetic player", "jersey_number": "12", "version": 3, "archived_at": NSNull()]
    }
    private func json(_ value: Any, status: Int = 200) -> (Int, Data) { (status, try! JSONSerialization.data(withJSONObject: value)) }
    private func readBodyStream(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            result.append(buffer, count: count)
        }
        return result
    }
}

private final class AdministrationFixtureRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: AdministrationFixture] = [:]
    func insert(_ fixture: AdministrationFixture) { lock.withLock { values[fixture.key] = fixture } }
    func get(_ key: String) -> AdministrationFixture? { lock.withLock { values[key] } }
}
private final class AdministrationURLProtocol: URLProtocol, @unchecked Sendable {
    static let registry = AdministrationFixtureRegistry()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let fixture = Self.registry.get(request.value(forHTTPHeaderField: "X-Administration-Fixture") ?? "") else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        let (status, body) = fixture.response(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
