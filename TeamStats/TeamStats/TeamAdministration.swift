import Foundation
import Observation
import Supabase

/// These names are the server capability contract, never roles inferred from contact details.
enum TeamCapability: String, Codable, CaseIterable, Identifiable, Sendable {
    case statsReview = "stats.review", statsPublish = "stats.publish", datasetsReopen = "datasets.reopen"
    case rosterManage = "roster.manage", membersManage = "members.manage"
    case playsAuthor = "plays.author", playsReview = "plays.review", playsPublish = "plays.publish"
    case practiceUpload = "practice.upload", practiceReview = "practice.review", practicePublish = "practice.publish"
    case filmUpload = "film.upload", filmReview = "film.review", filmPublish = "film.publish"
    case scoutingUpload = "scouting.upload", scoutingRead = "scouting.read"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .statsReview: "Review statistics"
        case .statsPublish: "Publish statistics"
        case .datasetsReopen: "Reopen completed datasets"
        case .rosterManage: "Manage roster"
        case .membersManage: "Manage membership"
        case .playsAuthor: "Author plays"
        case .playsReview: "Review plays"
        case .playsPublish: "Publish plays"
        case .practiceUpload: "Upload and publish own practice clips without review"
        case .practiceReview: "Inspect pending practice videos (owner approves)"
        case .practicePublish: "Publish own practice videos without review"
        case .filmUpload: "Submit Hudl shortcuts"
        case .filmReview: "Inspect pending Hudl shortcuts (owner approves)"
        case .filmPublish: "Publish own Hudl shortcuts without review"
        case .scoutingUpload: "Upload scouting reports for owner review"
        case .scoutingRead: "Read approved scouting reports"
        }
    }
}

enum TeamMembershipStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case pending, active, removed
    var id: String { rawValue }
}

struct ServerTeam: Decodable, Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let ownerAuthUUID: UUID
    let accessRevision: Int64
    enum CodingKeys: String, CodingKey {
        case id, name
        case ownerAuthUUID = "owner_auth_uuid", accessRevision = "access_revision"
    }
}

struct TeamGrantEnvelope: Decodable, Identifiable, Sendable {
    let id: UUID
    let allowedCapabilities: [TeamCapability]
    let expiresAt: String
    enum CodingKeys: String, CodingKey {
        case id
        case allowedCapabilities = "allowed_capabilities", expiresAt = "expires_at"
    }
    var expiry: Date? { administrationDate(expiresAt) }
}

struct TeamAccess: Decodable, Sendable {
    let teamID: UUID
    let userID: UUID
    let isOwner: Bool
    let accessRevision: Int64
    let capabilities: [TeamCapability]
    let grantEnvelopes: [TeamGrantEnvelope]
    enum CodingKeys: String, CodingKey {
        case teamID = "team_id", userID = "user_id", isOwner = "is_owner"
        case accessRevision = "access_revision", capabilities, grantEnvelopes = "grant_envelopes"
    }
    func can(_ capability: TeamCapability) -> Bool { isOwner || capabilities.contains(capability) }
    var grantableCapabilities: [TeamCapability] {
        if isOwner { return TeamCapability.allCases }
        return TeamCapability.allCases.filter { capability in
            grantEnvelopes.contains { $0.allowedCapabilities.contains(capability) && ($0.expiry ?? .distantPast) > Date() }
        }
    }
    var canReadAdministration: Bool { isOwner || can(.membersManage) || !grantableCapabilities.isEmpty }
}

struct ServerRosterEntry: Decodable, Identifiable, Sendable {
    let id: UUID
    let teamID: UUID
    let displayName: String
    let jerseyNumber: String
    let version: Int64
    let archivedAt: String?
    enum CodingKeys: String, CodingKey {
        case id, version
        case teamID = "team_id", displayName = "display_name", jerseyNumber = "jersey_number", archivedAt = "archived_at"
    }
}

struct ServerMembership: Decodable, Identifiable, Sendable {
    let userID: UUID
    let status: TeamMembershipStatus
    var id: UUID { userID }
    enum CodingKeys: String, CodingKey { case userID = "user_id", status }
}

/// Contacts are derived by a protected server command from independently confirmed Auth fields.
/// They identify an existing membership; they never establish capabilities or owner status.
struct ServerAdministratorIdentity: Decodable, Identifiable, Sendable {
    let userID: UUID
    let email: String?
    let phone: String?
    var id: UUID { userID }
    var label: String { email ?? phone ?? userID.uuidString }
    enum CodingKeys: String, CodingKey { case userID = "user_id", email, phone }
}

struct ServerCapabilityGrant: Decodable, Identifiable, Sendable {
    let id: UUID
    let userID: UUID
    let capability: TeamCapability
    let expiresAt: String?
    let revokedAt: String?
    let envelopeID: UUID?
    enum CodingKeys: String, CodingKey {
        case id, capability
        case userID = "user_id", expiresAt = "expires_at", revokedAt = "revoked_at", envelopeID = "envelope_id"
    }
}

struct ServerDelegation: Decodable, Identifiable, Sendable {
    let id: UUID
    let delegateUserID: UUID
    let allowedCapabilities: [TeamCapability]
    let expiresAt: String
    let revokedAt: String?
    enum CodingKeys: String, CodingKey {
        case id
        case delegateUserID = "delegate_user_id", allowedCapabilities = "allowed_capabilities"
        case expiresAt = "expires_at", revokedAt = "revoked_at"
    }
}

enum AdministrationIssue: Error, LocalizedError, Equatable {
    case invalidTeamID, invalidAccountID, invalidRoster, invalidExpiry, noCapabilities
    case reloadRequired, conflict, denied, server, tooManyRecords, invalidResponse
    var errorDescription: String? {
        switch self {
        case .invalidTeamID: "Enter the team UUID provided in your invitation."
        case .invalidAccountID: "Choose another verified Auth account UUID. Your own account and the owner cannot be changed here."
        case .invalidRoster: "Enter a player name of 1–100 characters and a jersey number of 1–10 characters."
        case .invalidExpiry: "Choose a future expiry within your delegation's expiry."
        case .noCapabilities: "Select at least one capability to delegate."
        case .reloadRequired: "Reload the team before making changes."
        case .conflict: "Team access or this roster entry changed on the server. Reload and review the current values before trying again."
        case .denied: "The server denied this action. Your session, membership or permission may have changed. Reload or sign in again."
        case .server: "The server could not confirm the request. Reload to check current state before trying again."
        case .tooManyRecords: "This list exceeds the supported size. No administration snapshot was loaded. Contact the team owner."
        case .invalidResponse: "The server returned an unexpected response. Reload or check the server setup."
        }
    }
}

/// One public model seam owns bounded reads, expected revisions, server confirmations
/// and safe errors. It never reads or uploads local temporary records.
@MainActor @Observable
final class TeamAdministration {
    private(set) var teams: [ServerTeam] = []
    private(set) var didLoadTeams = false
    private(set) var selectedTeam: ServerTeam?
    private(set) var access: TeamAccess?
    private(set) var roster: [ServerRosterEntry] = []
    private(set) var memberships: [ServerMembership] = []
    private(set) var administratorIdentities: [ServerAdministratorIdentity] = []
    private(set) var identityIssue: AdministrationIssue?
    private(set) var grants: [ServerCapabilityGrant] = []
    private(set) var delegations: [ServerDelegation] = []
    private(set) var isBusy = false
    private(set) var issue: AdministrationIssue?
    private(set) var confirmation: String?
    private(set) var admissionStatus: TeamMembershipStatus?
    @ObservationIgnored private let authenticatedClient: () async throws -> SupabaseClient
    @ObservationIgnored private var retryTeamID: UUID?
    @ObservationIgnored private var retryAdmissionID: String?

    init(account: BackendAccount) {
        authenticatedClient = { try await account.authenticatedClient() }
    }
    /// Real SDK transport injection for synthetic seam tests; production uses BackendAccount.
    init(authenticatedClient: @escaping () async throws -> SupabaseClient) {
        self.authenticatedClient = authenticatedClient
    }

    func loadTeams() async {
        guard !isBusy else { return }
        isBusy = true
        didLoadTeams = false
        clearSelection()
        issue = nil
        retryTeamID = nil
        retryAdmissionID = nil
        defer { isBusy = false }
        do {
            let client = try await authenticatedClient()
            teams = try await readPages(client: client, table: "teams", columns: "id,name,owner_auth_uuid,access_revision", order: "id")
            didLoadTeams = true
            if let selectedTeam, !teams.contains(where: { $0.id == selectedTeam.id }) { clearSelection() }
        } catch { teams = []; clearSelection(); fail(error) }
    }

    func selectTeam(_ team: ServerTeam) async { await loadTeam(teamID: team.id) }

    func reload() async {
        if let retryAdmissionID { await requestAdmission(teamID: retryAdmissionID) }
        else if let id = retryTeamID ?? selectedTeam?.id { await loadTeam(teamID: id) }
        else { await loadTeams() }
    }

    func requestAdmission(teamID: String) async {
        guard !isBusy else { return }
        confirmation = nil
        admissionStatus = nil
        guard let id = UUID(uuidString: teamID.trimmingCharacters(in: .whitespacesAndNewlines)) else { issue = .invalidTeamID; return }
        isBusy = true
        issue = nil
        retryAdmissionID = teamID
        defer { isBusy = false }
        do {
            let client = try await authenticatedClient()
            let status: String = try await client.rpc("team_request_membership", params: ["p_team_id": id.uuidString]).execute().value
            guard let result = TeamMembershipStatus(rawValue: status) else { throw AdministrationIssue.invalidResponse }
            admissionStatus = result
            switch result {
            case .pending:
                confirmation = "Your request is waiting for an administrator. Reload teams after they confirm admission."
            case .active:
                confirmation = "The server confirmed active membership. Reload teams to open the team."
            case .removed:
                confirmation = "The server reports removed membership. Ask your administrator about admission."
            }
            retryAdmissionID = nil
        } catch { fail(error) }
    }

    @discardableResult
    func saveRoster(entry: ServerRosterEntry?, displayName: String, jerseyNumber: String) async -> Bool {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = jerseyNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...100).contains(name.count), (1...10).contains(number.count) else { validation(.invalidRoster); return false }
        if let entry, entry.teamID != selectedTeam?.id || entry.archivedAt != nil { validation(.reloadRequired); return false }
        return await mutate("team_save_roster", values: [
            "p_display_name": .string(name), "p_jersey_number": .string(number),
            "p_roster_id": entry.map { .string($0.id.uuidString) } ?? .null,
            "p_expected_version": entry.map { .integer($0.version) } ?? .null
        ], result: .uuid, message: entry == nil ? "Server confirmed the new roster entry." : "Server confirmed the roster changes.")
    }

    func archiveRoster(_ entry: ServerRosterEntry) async {
        guard entry.teamID == selectedTeam?.id, entry.archivedAt == nil else { validation(.reloadRequired); return }
        await mutate("team_archive_roster", values: ["p_roster_id": .string(entry.id.uuidString), "p_expected_version": .integer(entry.version)], message: "Server confirmed the archive. Historical records are retained.")
    }

    func setMembership(userID: String, status: TeamMembershipStatus) async {
        guard let id = targetID(userID) else { validation(.invalidAccountID); return }
        await mutate("team_set_membership", values: ["p_user_id": .string(id.uuidString), "p_status": .string(status.rawValue)], message: "Server confirmed the membership change.")
    }

    func setCapability(userID: String, capability: TeamCapability, enabled: Bool, expiry: Date?) async {
        guard let id = targetID(userID) else { validation(.invalidAccountID); return }
        if let expiry, !expiry.timeIntervalSince1970.isFinite || expiry <= Date() { validation(.invalidExpiry); return }
        if enabled, access?.isOwner == false {
            guard let expiry, access?.grantEnvelopes.contains(where: { $0.allowedCapabilities.contains(capability) && ($0.expiry ?? .distantPast) >= expiry }) == true else { validation(.invalidExpiry); return }
        }
        await mutate("team_set_capability", values: ["p_user_id": .string(id.uuidString), "p_capability": .string(capability.rawValue), "p_enabled": .boolean(enabled), "p_expires_at": expiry.map { .string(administrationTimestamp($0)) } ?? .null], message: "Server confirmed the capability \(enabled ? "grant" : "revocation").")
    }

    @discardableResult
    func delegate(userID: String, capabilities: Set<TeamCapability>, expiry: Date) async -> Bool {
        guard let id = targetID(userID) else { validation(.invalidAccountID); return false }
        guard !capabilities.isEmpty else { validation(.noCapabilities); return false }
        guard expiry.timeIntervalSince1970.isFinite, expiry > Date() else { validation(.invalidExpiry); return false }
        return await mutate("team_delegate", values: ["p_user_id": .string(id.uuidString), "p_allowed_capabilities": .strings(capabilities.map(\.rawValue).sorted()), "p_expires_at": .string(administrationTimestamp(expiry))], result: .uuid, message: "Server confirmed the bounded delegation.")
    }

    func revokeDelegation(_ delegation: ServerDelegation) async {
        guard delegations.contains(where: { $0.id == delegation.id }) else { validation(.reloadRequired); return }
        await mutate("team_revoke_delegation", values: ["p_envelope_id": .string(delegation.id.uuidString)], message: "Server confirmed the delegation revocation.")
    }

    private func loadTeam(teamID: UUID) async {
        guard !isBusy else { return }
        isBusy = true
        issue = nil
        retryTeamID = teamID
        retryAdmissionID = nil
        clearSelection()
        defer { isBusy = false }
        do { try await readTeam(teamID: teamID, client: authenticatedClient()) }
        catch { clearSelection(); fail(error) }
    }

    private func readTeam(teamID: UUID, client: SupabaseClient) async throws {
        let rows: [ServerTeam] = try await client.from("teams").select("id,name,owner_auth_uuid,access_revision").eq("id", value: teamID.uuidString).limit(1).execute().value
        guard let team = rows.first else { throw AdministrationIssue.denied }
        let snapshot: TeamAccess = try await client.rpc("team_access", params: ["p_team_id": teamID.uuidString]).execute().value
        guard snapshot.teamID == teamID, snapshot.accessRevision >= 0 else { throw AdministrationIssue.invalidResponse }
        let loadedRoster: [ServerRosterEntry] = try await readPages(client: client, table: "roster_entries", columns: "id,team_id,display_name,jersey_number,version,archived_at", order: "id", teamID: teamID)
        var loadedMemberships: [ServerMembership] = []
        var loadedGrants: [ServerCapabilityGrant] = []
        var loadedDelegations: [ServerDelegation] = []
        if snapshot.canReadAdministration {
            loadedMemberships = try await readPages(client: client, table: "team_memberships", columns: "user_id,status", order: "user_id", teamID: teamID)
            loadedGrants = try await readPages(client: client, table: "capability_grants", columns: "id,user_id,capability,expires_at,revoked_at,envelope_id", order: "id", teamID: teamID)
            loadedDelegations = try await readPages(client: client, table: "delegation_envelopes", columns: "id,delegate_user_id,allowed_capabilities,expires_at,revoked_at", order: "id", teamID: teamID)
        }
        // Publish only a complete snapshot. A command racing these reads is rejected
        // by the snapshot revision at the next mutation.
        selectedTeam = team
        access = snapshot
        roster = loadedRoster
        memberships = loadedMemberships
        grants = loadedGrants
        delegations = loadedDelegations
        if snapshot.canReadAdministration {
            do {
                administratorIdentities = try await readIdentities(client: client, teamID: teamID)
            } catch {
                let safeIssue = administrationIssue(error)
                administratorIdentities = []
                if safeIssue == .denied { throw safeIssue }
                identityIssue = safeIssue
            }
        }
    }

    func identity(for userID: UUID) -> ServerAdministratorIdentity? {
        administratorIdentities.first { $0.userID == userID }
    }

    private func readIdentities(client: SupabaseClient, teamID: UUID) async throws -> [ServerAdministratorIdentity] {
        var rows: [ServerAdministratorIdentity] = []
        for page in 0..<50 {
            let values: [ServerAdministratorIdentity] = try await client.rpc("team_administrator_identities", params: ["p_team_id": teamID.uuidString])
                .order("user_id").range(from: page * 100, to: (page + 1) * 100 - 1).execute().value
            rows.append(contentsOf: values)
            if values.count < 100 { return rows }
        }
        throw AdministrationIssue.tooManyRecords
    }

    private func readPages<T: Decodable>(client: SupabaseClient, table: String, columns: String, order: String, teamID: UUID? = nil) async throws -> [T] {
        var rows: [T] = []
        let pageSize = 100
        for page in 0..<50 {
            let query = client.from(table).select(columns)
            if let teamID { _ = query.eq("team_id", value: teamID.uuidString) }
            let values: [T] = try await query.order(order).range(from: page * pageSize, to: (page + 1) * pageSize - 1).execute().value
            rows.append(contentsOf: values)
            if values.count < pageSize { return rows }
        }
        throw AdministrationIssue.tooManyRecords
    }

    private enum RPCResult { case void, uuid }
    @discardableResult
    private func mutate(_ rpc: String, values: [String: CommandValue], result: RPCResult = .void, message: String) async -> Bool {
        guard !isBusy else { return false }
        confirmation = nil
        guard let team = selectedTeam, let access else { issue = .reloadRequired; return false }
        isBusy = true
        issue = nil
        retryTeamID = team.id
        retryAdmissionID = nil
        defer { isBusy = false }
        var didCommit = false
        do {
            let client = try await authenticatedClient()
            var parameters = values
            parameters["p_team_id"] = .string(team.id.uuidString)
            parameters["p_expected_access_revision"] = .integer(access.accessRevision)
            if result == .uuid {
                let _: UUID = try await client.rpc(rpc, params: parameters).retry(enabled: false).execute().value
            } else { _ = try await client.rpc(rpc, params: parameters).retry(enabled: false).execute() }
            didCommit = true
            confirmation = message
            clearSelection()
            // Never replay an ambiguous mutation: reload reveals whether it committed.
            try await readTeam(teamID: team.id, client: client)
        } catch { clearSelection(); fail(error) }
        return didCommit
    }

    private func targetID(_ value: String) -> UUID? {
        guard let id = UUID(uuidString: value.trimmingCharacters(in: .whitespacesAndNewlines)), id != access?.userID, id != selectedTeam?.ownerAuthUUID else { return nil }
        return id
    }
    private func validation(_ value: AdministrationIssue) { confirmation = nil; issue = value }
    private func clearSelection() { selectedTeam = nil; access = nil; roster = []; memberships = []; grants = []; delegations = []; administratorIdentities = []; identityIssue = nil }
    private func fail(_ error: Error) { issue = administrationIssue(error) }
}

private func administrationIssue(_ error: Error) -> AdministrationIssue {
    if let error = error as? AdministrationIssue { return error }
    if let error = error as? PostgrestError {
        switch error.code {
        case "40001": return .conflict
        case "42501": return .denied
        case "22023", "23514", "23503": return .invalidResponse
        default: return .server
        }
    }
    return .server
}

private enum CommandValue: Encodable {
    case string(String), integer(Int64), boolean(Bool), strings([String]), null
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .strings(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

func administrationDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
}
private func administrationTimestamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
