import Foundation
import Observation
import Supabase

enum PlayRevisionStatus: String, Codable, Sendable { case draft, submitted, rejected, published, superseded }
struct ServerPlay: Decodable, Identifiable, Sendable {
    let id: UUID
    let teamID: UUID
    let publishedVersionID: UUID?
    enum CodingKeys: String, CodingKey { case id, teamID = "team_id", publishedVersionID = "published_version_id" }
}
struct PlayRevision: Decodable, Identifiable, Hashable, Sendable {
    let id: UUID
    let teamID: UUID
    let playID: UUID
    let authorUserID: UUID
    let revision: Int64
    let status: PlayRevisionStatus
    let title: String
    let diagram: PlayDiagram
    let basePublishedVersionID: UUID?
    let reviewReason: String
    let recoverySourceVersionID: UUID?
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id && lhs.revision == rhs.revision }
    func hash(into hasher: inout Hasher) { hasher.combine(id); hasher.combine(revision) }
    enum CodingKeys: String, CodingKey {
        case id, revision, status, title, diagram
        case teamID = "team_id", playID = "play_id", authorUserID = "author_user_id"
        case basePublishedVersionID = "base_published_version_id", reviewReason = "review_reason", recoverySourceVersionID = "recovery_source_version_id"
    }
}
enum PlaybookIssue: Error, Equatable, LocalizedError {
    case invalidInput, conflict, denied, unavailable, invalidResponse, reloadRequired
    var errorDescription: String? {
        switch self {
        case .invalidInput: "Check the name, marker positions and movement steps."
        case .conflict: "This play changed on the server. Reload before saving again; your unsaved drawing stays on this screen."
        case .denied: "Your current account cannot perform this play action. Ask the owner about membership or permissions."
        case .unavailable: "The playbook could not be reached. Retry; no save or publication is confirmed."
        case .invalidResponse: "The server returned an unreadable playbook. Retry before continuing."
        case .reloadRequired: "Reload the playbook before another change. Your unsaved drawing stays on this screen."
        }
    }
}
@MainActor @Observable
final class Playbook {
    let teamID: UUID
    private(set) var access: TeamAccess?
    private(set) var plays: [ServerPlay] = []
    private(set) var versions: [PlayRevision] = []
    private(set) var isBusy = false
    private(set) var didLoad = false
    private(set) var reloadRequired = false
    private(set) var issue: PlaybookIssue?
    private(set) var confirmation: String?
    @ObservationIgnored private let authenticatedClient: () async throws -> SupabaseClient
    init(account: BackendAccount, teamID: UUID) {
        self.teamID = teamID
        authenticatedClient = { try await account.authenticatedClient() }
    }
    init(teamID: UUID, authenticatedClient: @escaping () async throws -> SupabaseClient) {
        self.teamID = teamID; self.authenticatedClient = authenticatedClient
    }
    var published: [PlayRevision] {
        plays.compactMap { play in versions.first { $0.id == play.publishedVersionID && $0.status == .published } }
    }
    var ownDrafts: [PlayRevision] { versions.filter { $0.authorUserID == access?.userID && $0.status == .draft } }
    var submissions: [PlayRevision] { versions.filter { $0.status == .submitted } }
    func history(playID: UUID) -> [PlayRevision] { versions.filter { $0.playID == playID && $0.status == .published } }
    func load() async {
        guard !isBusy else { return }
        isBusy = true; didLoad = false; issue = nil; confirmation = nil
        defer { isBusy = false }
        do { try await read(try await authenticatedClient()) }
        catch { access = nil; plays = []; versions = []; fail(error) }
    }
    func openDraft(playID: UUID, source: PlayRevision? = nil) async -> PlayRevision? {
        guard begin() else { return nil }
        defer { isBusy = false }
        do {
            let client = try await authenticatedClient()
            let result: PlayRevision = try await command(client, "play_open_draft", [
                "p_play_id": .string(playID.uuidString), "p_source_version_id": source.map { .string($0.id.uuidString) } ?? .null])
            guard result.teamID == teamID, result.playID == playID, result.status == .draft,
                  result.authorUserID == access?.userID, result.revision > 0, result.diagram.validationMessage == nil else { throw PlaybookIssue.invalidResponse }
            try await read(client)
            confirmation = "Server confirmed the working play draft."
            return versions.first { $0.id == result.id }
        } catch { mutationFailed(error); return nil }
    }
    func currentPublishedVersionID(playID: UUID) -> UUID? { plays.first { $0.id == playID }?.publishedVersionID }
    func isStaleDraft(_ version: PlayRevision) -> Bool {
        version.status == .draft && currentPublishedVersionID(playID: version.playID) != version.basePublishedVersionID
    }
    private struct RecoveryResult: Decodable { let superseded: PlayRevision; let draft: PlayRevision }
    func recoverDraft(_ version: PlayRevision, expectedPublishedVersionID: UUID) async -> PlayRevision? {
        guard begin() else { return nil }
        defer { isBusy = false }
        guard versions.contains(where: { $0.id == version.id && $0.revision == version.revision }),
              version.status == .draft, version.authorUserID == access?.userID, version.revision < Int64.max,
              isStaleDraft(version), currentPublishedVersionID(playID: version.playID) == expectedPublishedVersionID else {
            issue = .reloadRequired; reloadRequired = true; return nil
        }
        do {
            let client = try await authenticatedClient()
            let result: RecoveryResult = try await command(client, "play_recover_draft", [
                "p_version_id": .string(version.id.uuidString), "p_expected_revision": .integer(Int(version.revision)),
                "p_expected_published_version_id": .string(expectedPublishedVersionID.uuidString)])
            let old = result.superseded, new = result.draft
            guard old.id == version.id, old.teamID == teamID, old.playID == version.playID, old.authorUserID == version.authorUserID,
                  old.status == .superseded, old.revision == version.revision + 1, old.title == version.title,
                  old.diagram == version.diagram, old.basePublishedVersionID == version.basePublishedVersionID,
                  old.recoverySourceVersionID == version.recoverySourceVersionID,
                  new.id != old.id, new.teamID == teamID, new.playID == version.playID, new.authorUserID == version.authorUserID,
                  new.status == .draft, new.revision == 1, new.title == version.title, new.diagram == version.diagram,
                  new.basePublishedVersionID == expectedPublishedVersionID, new.recoverySourceVersionID == old.id else {
                throw PlaybookIssue.invalidResponse
            }
            try await read(client)
            guard let loaded = versions.first(where: { $0.id == new.id }), loaded.revision == new.revision else { throw PlaybookIssue.invalidResponse }
            confirmation = "Server created a resumed draft and retained the previous saved drawing as read-only. Unsaved editor changes have not been uploaded."
            return loaded
        } catch { mutationFailed(error); return nil }
    }
    @discardableResult func save(_ version: PlayRevision, title: String, diagram: PlayDiagram) async -> Bool {
        guard !isBusy else { return false }
        guard title.count <= 100, diagram.validationMessage == nil,
              (try? JSONEncoder().encode(diagram).count).map({ $0 <= 1_048_576 }) == true else { issue = .invalidInput; confirmation = nil; return false }
        return await mutate(version, action: "save", values: ["p_title": .string(title), "p_diagram": (try? JSONDecoder().decode(AnyJSON.self, from: JSONEncoder().encode(diagram))) ?? .null])
    }
    @discardableResult func transition(_ version: PlayRevision, action: String, reason: String = "") async -> Bool {
        guard ["submit", "publish", "approve", "reject"].contains(action), reason.count <= 500 else { issue = .invalidInput; return false }
        return await mutate(version, action: action, values: ["p_action": .string(action), "p_reason": .string(reason)])
    }
    private func mutate(_ version: PlayRevision, action: String, values: [String: AnyJSON]) async -> Bool {
        guard begin() else { return false }
        defer { isBusy = false }
        guard versions.contains(where: { $0.id == version.id && $0.revision == version.revision }), version.revision < Int64.max else {
            issue = .reloadRequired; reloadRequired = true; return false
        }
        do {
            let client = try await authenticatedClient()
            var parameters = values
            parameters["p_version_id"] = .string(version.id.uuidString)
            parameters["p_expected_revision"] = .integer(Int(version.revision))
            let result: PlayRevision = try await command(client, action == "save" ? "play_save_draft" : "play_transition", parameters)
            let expected: PlayRevisionStatus = action == "save" ? .draft : action == "submit" ? .submitted : action == "reject" ? .rejected : .published
            guard result.id == version.id, result.teamID == teamID, result.playID == version.playID,
                  result.authorUserID == version.authorUserID, result.revision == version.revision + 1,
                  result.status == expected, result.diagram.validationMessage == nil else { throw PlaybookIssue.invalidResponse }
            try await read(client)
            confirmation = action == "save" ? "Server confirmed the play draft." : "Server confirmed: \(expected.rawValue)."
            return true
        } catch { mutationFailed(error); return false }
    }
    private func begin() -> Bool {
        guard !isBusy else { return false }
        confirmation = nil
        guard didLoad, !reloadRequired else { issue = .reloadRequired; return false }
        isBusy = true; issue = nil; return true
    }
    private func read(_ client: SupabaseClient) async throws {
        let snapshot: TeamAccess = try await command(client, "team_access", [:])
        let rows: [ServerPlay] = try await pages(client, "plays")
        let revisions: [PlayRevision] = try await pages(client, "play_versions")
        guard snapshot.teamID == teamID, Set(rows.map(\.id)).count == rows.count,
              Set(revisions.map(\.id)).count == revisions.count, rows.allSatisfy({ $0.teamID == teamID }),
              revisions.allSatisfy({ $0.teamID == teamID && $0.revision > 0 && $0.diagram.validationMessage == nil }) else { throw PlaybookIssue.invalidResponse }
        // A published pointer must resolve to its own immutable accepted revision.
        guard revisions.allSatisfy({ revision in rows.contains { $0.id == revision.playID } }),
              rows.allSatisfy({ play in play.publishedVersionID == nil || revisions.contains { $0.id == play.publishedVersionID && $0.playID == play.id && $0.status == .published } }) else { throw PlaybookIssue.invalidResponse }
        access = snapshot; plays = rows; versions = revisions; didLoad = true; reloadRequired = false
    }
    private func pages<T: Decodable>(_ client: SupabaseClient, _ table: String) async throws -> [T] {
        var result: [T] = []
        for page in 0..<100 {
            let batch: [T] = try await client.from(table).select().eq("team_id", value: teamID.uuidString)
                .order("id").range(from: page * 100, to: page * 100 + 99).execute().value
            result += batch
            if batch.count < 100 { return result }
        }
        throw PlaybookIssue.unavailable
    }
    private func command<T: Decodable>(_ client: SupabaseClient, _ name: String, _ values: [String: AnyJSON]) async throws -> T {
        var parameters = values; parameters["p_team_id"] = .string(teamID.uuidString)
        return try await client.rpc(name, params: parameters).retry(enabled: false).execute().value
    }
    private func mutationFailed(_ error: Error) { reloadRequired = true; didLoad = false; fail(error) }
    private func fail(_ error: Error) {
        confirmation = nil
        if let error = error as? PlaybookIssue { issue = error }
        else if let error = error as? PostgrestError {
            switch error.code {
            case "40001": issue = .conflict
            case "42501": issue = .denied
            case "22023", "22P02", "23514": issue = .invalidInput
            default: issue = .unavailable
            }
        } else if error is DecodingError { issue = .invalidResponse }
        else { issue = .unavailable }
    }
}
