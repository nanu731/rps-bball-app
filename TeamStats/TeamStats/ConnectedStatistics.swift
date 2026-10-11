import Foundation
import Observation
import Supabase

enum ConnectedDatasetType: String, Codable, CaseIterable, Identifiable, Sendable {
    case boxScores = "box_scores", ourPossessions = "our_possessions"
    case opponentPossessions = "opponent_possessions", playerPaintTouches = "player_paint_touches"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .boxScores: "Player box scores"
        case .ourPossessions: "Our possessions"
        case .opponentPossessions: "Opponent possessions"
        case .playerPaintTouches: "Player paint touches"
        }
    }
}
enum ConnectedVersionStatus: String, Codable, Sendable {
    case draft, completed, submitted, rejected, published
    var isComplete: Bool { self != .draft }
}
struct ConnectedGame: Decodable, Identifiable, Sendable {
    let id: UUID
    let teamID: UUID
    let dateString: String
    let opponent: String
    let homeAway: String
    let gameType: String
    let publicationGeneration: Int64
    enum CodingKeys: String, CodingKey {
        case id, opponent
        case teamID = "team_id", dateString = "date", homeAway = "home_away"
        case gameType = "game_type", publicationGeneration = "publication_generation"
    }
    // A game date is a calendar day, not a UTC instant that changes on another device.
    var date: Date? { Self.calendarDate(dateString) }
    static func calendarDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard text.count == 10, let date = formatter.date(from: text), formatter.string(from: date) == text else { return nil }
        return date
    }
    static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
struct ConnectedCoveredPlayer: Codable, Hashable, Sendable {
    let id: UUID
    let version: Int64
}
struct ConnectedVersion: Decodable, Identifiable, Sendable {
    let id: UUID
    let teamID: UUID
    let gameID: UUID
    let datasetID: UUID
    let datasetType: ConnectedDatasetType
    let authorUserID: UUID
    let revision: Int64
    let status: ConnectedVersionStatus
    let records: [AnyJSON]
    let coveredRoster: [ConnectedCoveredPlayer]
    let basePublishedVersionID: UUID?
    enum CodingKeys: String, CodingKey {
        case id, revision, status, records
        case teamID = "team_id", gameID = "game_id", datasetID = "dataset_id", datasetType = "dataset_type"
        case authorUserID = "author_user_id", coveredRoster = "covered_roster", basePublishedVersionID = "base_published_version_id"
    }
    func boxScores() throws -> [PlayerBoxScore] {
        guard datasetType == .boxScores else { throw ConnectedStatisticsIssue.invalidResponse }
        let records = try decodeDisplayRecords(PlayerBoxScore.self)
        guard Set(records.map(\.playerID)).count == records.count else { throw ConnectedStatisticsIssue.invalidResponse }
        return records
    }
    func possessions() throws -> [PossessionRecord] {
        guard datasetType == .ourPossessions || datasetType == .opponentPossessions else { throw ConnectedStatisticsIssue.invalidResponse }
        let records = try decodeDisplayRecords(PossessionRecord.self)
        let team: PossessionTeam = datasetType == .ourPossessions ? .ours : .opponent
        guard Set(records.map(\.id)).count == records.count, Set(records.map(\.number)).count == records.count,
              records.allSatisfy({ $0.team == team && $0.number > 0 }) else { throw ConnectedStatisticsIssue.invalidResponse }
        return records
    }
    func paintTouches() throws -> [PlayerPaintTouchRecord] {
        guard datasetType == .playerPaintTouches else { throw ConnectedStatisticsIssue.invalidResponse }
        let records = try decodeDisplayRecords(PlayerPaintTouchRecord.self)
        guard Set(records.map(\.playerID)).count == records.count else { throw ConnectedStatisticsIssue.invalidResponse }
        return records
    }
    private func decodeDisplayRecords<T: Decodable>(_ type: T.Type) throws -> [T] {
        // Only the display/calculation adapter removes explicit null counts. The server JSON stays untouched.
        let display = try records.map { record -> AnyJSON in
            guard var object = record.objectValue,
                  let recordGame = object["gameID"]?.stringValue.flatMap(UUID.init(uuidString:)), recordGame == gameID else { throw ConnectedStatisticsIssue.invalidResponse }
            let identityKey = datasetType == .ourPossessions || datasetType == .opponentPossessions ? "id" : "playerID"
            guard let identity = object[identityKey]?.stringValue.flatMap(UUID.init(uuidString:)) else { throw ConnectedStatisticsIssue.invalidResponse }
            object[identityKey] = .string(identity.uuidString)
            let allowedKeys: Set<String>
            switch datasetType {
            case .boxScores: allowedKeys = ["gameID", "playerID", "values"]
            case .playerPaintTouches: allowedKeys = ["gameID", "playerID", "total"]
            case .ourPossessions, .opponentPossessions: allowedKeys = ["id", "gameID", "team", "number", "values", "turnover"]
            }
            guard Set(object.keys).isSubset(of: allowedKeys) else { throw ConnectedStatisticsIssue.invalidResponse }
            if datasetType == .playerPaintTouches {
                if let total = object["total"], !total.isNil, total.intValue == nil || total.intValue! < 0 { throw ConnectedStatisticsIssue.invalidResponse }
            } else {
                let allowedCounts = datasetType == .boxScores ? Set(BoxScoreField.allCases.map(\.rawValue)) : Set(PossessionField.allCases.map(\.rawValue))
                guard let counts = object["values"]?.objectValue,
                      Set(counts.keys).isSubset(of: allowedCounts),
                      counts.values.allSatisfy({ $0.isNil || ($0.intValue != nil && $0.intValue! >= 0) }) else { throw ConnectedStatisticsIssue.invalidResponse }
                object["values"] = .object(counts.filter { !$0.value.isNil })
            }
            return .object(object)
        }
        do { return try JSONDecoder().decode([T].self, from: JSONEncoder().encode(display)) }
        catch { throw ConnectedStatisticsIssue.invalidResponse }
    }
}
struct ConnectedDatasetPointer: Decodable, Identifiable, Sendable {
    let id: UUID
    let teamID: UUID
    let gameID: UUID
    let datasetType: ConnectedDatasetType
    let publishedVersionID: UUID?
    enum CodingKeys: String, CodingKey {
        case id
        case teamID = "team_id", gameID = "game_id", datasetType = "dataset_type", publishedVersionID = "published_version_id"
    }
}
enum ConnectedEditStatus: String, Decodable, Sendable { case pending, approved, rejected }
struct ConnectedEditRequest: Decodable, Identifiable, Sendable {
    let id: UUID
    let teamID: UUID
    let sourceVersionID: UUID
    let requesterUserID: UUID
    let revision: Int64
    let status: ConnectedEditStatus
    let reason: String
    let reviewReason: String
    let workingVersionID: UUID?
    enum CodingKeys: String, CodingKey {
        case id, revision, status, reason
        case teamID = "team_id", sourceVersionID = "source_version_id", requesterUserID = "requester_user_id"
        case reviewReason = "review_reason", workingVersionID = "working_version_id"
    }
}
struct ConnectedRosterLabel: Decodable, Identifiable, Sendable {
    let id: UUID
    let teamID: UUID
    let name: String
    let jerseyNumber: String
    let version: Int64
    enum CodingKeys: String, CodingKey {
        case version
        case id = "roster_id", teamID = "team_id", name = "display_name", jerseyNumber = "jersey_number"
    }
}
struct ConnectedExportOutbox: Decodable, Identifiable, Sendable {
    let id: UUID
    let teamID: UUID
    let gameID: UUID
    let acceptedVersionID: UUID
    let publicationGeneration: Int64
    let createdAt: String
    enum CodingKeys: String, CodingKey {
        case id
        case teamID = "team_id", gameID = "game_id", acceptedVersionID = "accepted_version_id"
        case publicationGeneration = "publication_generation", createdAt = "created_at"
    }
}
struct ConnectedDraftSave: Encodable, Sendable {
    let versionID: UUID
    let expectedRevision: Int64
    let records: [AnyJSON]
    let coveredRoster: [ConnectedCoveredPlayer]
    enum CodingKeys: String, CodingKey {
        case versionID = "version_id", expectedRevision = "expected_revision", records, coveredRoster = "covered_roster"
    }
    init(version: ConnectedVersion, records: [AnyJSON], coveredRoster: [ConnectedCoveredPlayer] = []) {
        versionID = version.id; expectedRevision = version.revision
        self.records = records; self.coveredRoster = coveredRoster
    }
    init(version: ConnectedVersion, boxScores: [PlayerBoxScore], coveredRoster: [ConnectedCoveredPlayer]) throws {
        guard version.datasetType == .boxScores else { throw ConnectedStatisticsIssue.invalidInput }
        self.init(version: version, records: try Self.encoded(boxScores, preservingNullsFrom: version), coveredRoster: coveredRoster)
    }
    init(version: ConnectedVersion, possessions: [PossessionRecord]) throws {
        guard [.ourPossessions, .opponentPossessions].contains(version.datasetType) else { throw ConnectedStatisticsIssue.invalidInput }
        self.init(version: version, records: try Self.encoded(possessions, preservingNullsFrom: version))
    }
    init(version: ConnectedVersion, paintTouches: [PlayerPaintTouchRecord], coveredRoster: [ConnectedCoveredPlayer]) throws {
        guard version.datasetType == .playerPaintTouches else { throw ConnectedStatisticsIssue.invalidInput }
        self.init(version: version, records: try Self.encoded(paintTouches, preservingNullsFrom: version), coveredRoster: coveredRoster)
    }
    private static func encoded<T: Encodable>(_ records: [T], preservingNullsFrom version: ConnectedVersion) throws -> [AnyJSON] {
        let raw = try JSONDecoder().decode([AnyJSON].self, from: JSONEncoder().encode(records))
        return raw.map { record in
            guard var object = record.objectValue else { return record }
            guard let identity = (object["playerID"] ?? object["id"])?.stringValue.flatMap(UUID.init(uuidString:)) else { return record }
            guard let original = version.records.first(where: {
                ($0.objectValue?["playerID"] ?? $0.objectValue?["id"])?.stringValue.flatMap(UUID.init(uuidString:)) == identity
            })?.objectValue else { return record }
            if var values = object["values"]?.objectValue, let old = original["values"]?.objectValue {
                for (key, value) in old where value.isNil && values[key] == nil { values[key] = .null }
                object["values"] = .object(values)
            }
            for (key, value) in original where value.isNil && object[key] == nil { object[key] = .null }
            return .object(object)
        }
    }
}
enum ConnectedStatisticsIssue: Error, LocalizedError, Equatable {
    case invalidInput, invalidResponse, conflict, denied, server, tooManyRecords, reloadRequired
    var errorDescription: String? {
        switch self {
        case .invalidInput: "Check the entered game details, counts, roster coverage and completion confirmations."
        case .invalidResponse: "The server returned unexpected statistics. Reload or check the server setup."
        case .conflict: "This dataset changed on the server. Reload its current version before saving again. Your unsaved entries remain in the editor."
        case .denied: "The server denied this action. Your session, membership or permission may have changed. Reload or sign in again."
        case .server: "The server could not confirm this request. Reload to check the current version before trying again."
        case .tooManyRecords: "This list exceeds the supported size. No statistics snapshot was loaded. Contact the team owner."
        case .reloadRequired: "Reload current server statistics before making another change."
        }
    }
}
/// Connected server state only. Editors own unsaved text; this model never reads local JSON files.
@MainActor @Observable
final class ConnectedStatistics {
    let teamID: UUID
    private(set) var games: [ConnectedGame] = []
    private(set) var didLoadGames = false
    private(set) var selectedGame: ConnectedGame?
    private(set) var access: TeamAccess?
    private(set) var roster: [ServerRosterEntry] = []
    private(set) var versions: [ConnectedVersion] = []
    private(set) var datasets: [ConnectedDatasetPointer] = []
    private(set) var editRequests: [ConnectedEditRequest] = []
    private(set) var exportOutbox: [ConnectedExportOutbox] = []
    private(set) var didLoadGame = false
    private(set) var suppressNumericWarning = false
    private(set) var reloadRequired = false
    @ObservationIgnored private var historicalRoster: [ConnectedRosterLabel] = []
    @ObservationIgnored private var retryGame: ConnectedGame?
    var ownVersions: [ConnectedVersion] { versions.filter { $0.authorUserID == access?.userID } }
    var reviewQueue: [ConnectedVersion] {
        guard didLoadGame, access?.can(.statsReview) == true else { return [] }
        return versions.filter { $0.status == .submitted && (access?.isOwner == true || $0.authorUserID != access?.userID) }
    }
    var editReviewQueue: [ConnectedEditRequest] {
        guard didLoadGame, access?.can(.datasetsReopen) == true else { return [] }
        return editRequests.filter { $0.status == .pending && (access?.isOwner == true || $0.requesterUserID != access?.userID) }
    }
    var publishedVersions: [ConnectedDatasetType: ConnectedVersion] {
        guard didLoadGame else { return [:] }
        var accepted: [ConnectedDatasetType: ConnectedVersion] = [:]
        for pointer in datasets {
            if let version = versions.first(where: { $0.id == pointer.publishedVersionID && $0.status == .published }) { accepted[pointer.datasetType] = version }
        }
        return accepted
    }
    func rosterLabels(for version: ConnectedVersion) -> [ConnectedRosterLabel] {
        version.coveredRoster.compactMap { player in historicalRoster.first { $0.id == player.id && $0.version == player.version } }
    }
    func publishedStatistics() throws -> GameStatistics? {
        guard didLoadGame, let game = selectedGame else { return nil }
        let accepted = publishedVersions
        let box = try accepted[.boxScores]?.boxScores() ?? []
        let ours = try accepted[.ourPossessions]?.possessions() ?? []
        let opponent = try accepted[.opponentPossessions]?.possessions() ?? []
        return GameStatistics(gameID: game.id, boxScores: box,
            coveredPlayerIDs: Set(accepted[.boxScores]?.coveredRoster.map { $0.id.uuidString } ?? []),
            possessions: ours + opponent,
            completion: GameStatisticsCompletion(boxScores: accepted[.boxScores]?.status == .published,
                ourPossessions: accepted[.ourPossessions]?.status == .published,
                opponentPossessions: accepted[.opponentPossessions]?.status == .published))
    }
    private(set) var isBusy = false
    private(set) var issue: ConnectedStatisticsIssue?
    private(set) var confirmation: String?
    @ObservationIgnored private let authenticatedClient: () async throws -> SupabaseClient
    init(account: BackendAccount, teamID: UUID) {
        self.teamID = teamID
        authenticatedClient = { try await account.authenticatedClient() }
    }
    /// Real SDK HTTP transport injection for synthetic public-seam tests.
    init(teamID: UUID, authenticatedClient: @escaping () async throws -> SupabaseClient) {
        self.teamID = teamID; self.authenticatedClient = authenticatedClient
    }
    func loadGames() async {
        guard !isBusy else { return }
        isBusy = true; issue = nil; confirmation = nil; didLoadGames = false
        retryGame = nil; clearGame()
        defer { isBusy = false }
        do {
            let client = try await authenticatedClient()
            let snapshot: TeamAccess = try await command(client, "team_access", [:])
            guard snapshot.teamID == teamID else { throw ConnectedStatisticsIssue.invalidResponse }
            games = try await pages(client, table: "games", order: "id")
            guard games.allSatisfy({ $0.teamID == teamID && $0.date != nil }) else { throw ConnectedStatisticsIssue.invalidResponse }
            didLoadGames = true; reloadRequired = false
        } catch { games = []; fail(error) }
    }
    @discardableResult
    func createGame(id: UUID, dateString: String, opponent: String, homeAway: String, gameType: String) async -> Bool {
        guard !isBusy else { return false }
        confirmation = nil
        let opponent = opponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ConnectedGame.calendarDate(dateString) != nil, (1...100).contains(opponent.count),
              ["home", "away"].contains(homeAway), ["regularSeason", "playoff"].contains(gameType) else { issue = .invalidInput; return false }
        isBusy = true; issue = nil
        defer { isBusy = false }
        do {
            let client = try await authenticatedClient()
            let game: ConnectedGame = try await command(client, "stats_create_game", [
                "p_game_id": .string(id.uuidString), "p_date": .string(dateString), "p_opponent": .string(opponent),
                "p_home_away": .string(homeAway), "p_game_type": .string(gameType)])
            guard game.id == id, game.teamID == teamID, game.dateString == dateString,
                  game.opponent == opponent, game.homeAway == homeAway, game.gameType == gameType else { throw ConnectedStatisticsIssue.invalidResponse }
            games.removeAll { $0.id == id }; games.append(game)
            confirmation = "Server confirmed the game."
            return true
        } catch { fail(error); return false }
    }
    func openDraft(_ dataset: ConnectedDatasetType) async -> ConnectedVersion? {
        guard beginMutation(), let game = selectedGame else { return nil }
        defer { isBusy = false }
        do {
            let client = try await authenticatedClient()
            let version: ConnectedVersion = try await command(client, "stats_open_draft", ["p_game_id": .string(game.id.uuidString), "p_dataset_type": .string(dataset.rawValue)])
            guard version.teamID == teamID, version.gameID == game.id, version.datasetType == dataset,
                  version.authorUserID == access?.userID, version.status == .draft, version.revision > 0 else { throw ConnectedStatisticsIssue.invalidResponse }
            try await readGame(game, client: client)
            confirmation = "Server confirmed the working draft."
            return versions.first { $0.id == version.id }
        } catch { mutationFailed(error); return nil }
    }
    @discardableResult
    func saveDraftBatch(_ items: [ConnectedDraftSave]) async -> Bool {
        guard !isBusy else { return false }
        confirmation = nil
        guard !items.isEmpty, Set(items.map(\.versionID)).count == items.count else { issue = .invalidInput; return false }
        guard items.allSatisfy({ item in versions.contains { $0.id == item.versionID && $0.revision == item.expectedRevision && $0.status == .draft && $0.authorUserID == access?.userID } }) else {
            issue = .reloadRequired; reloadRequired = true; return false
        }
        guard beginMutation(), let game = selectedGame else { return false }
        defer { isBusy = false }
        do {
            let client = try await authenticatedClient()
            let rawItems = try JSONDecoder().decode(AnyJSON.self, from: JSONEncoder().encode(items))
            let saved: [ConnectedVersion] = try await command(client, "stats_save_drafts", ["p_items": rawItems])
            guard saved.count == items.count, zip(saved, items).allSatisfy({ version, item in
                version.id == item.versionID && version.teamID == teamID && version.gameID == game.id &&
                version.authorUserID == access?.userID && version.status == .draft && version.revision > item.expectedRevision &&
                version.records == item.records && version.coveredRoster == item.coveredRoster
            }) else { throw ConnectedStatisticsIssue.invalidResponse }
            try await readGame(game, client: client)
            confirmation = "Server confirmed all draft changes."
            return true
        } catch { mutationFailed(error); return false }
    }
    @discardableResult
    func complete(_ version: ConnectedVersion, confirmRoster: Bool = false, confirmNumericZeros: Bool = false, suppressNumericWarning: Bool = false) async -> Bool {
        await versionCommand("stats_complete", version: version, allowed: [.draft], values: [
            "p_confirm_roster": .bool(confirmRoster), "p_confirm_numeric_zeros": .bool(confirmNumericZeros),
            "p_suppress_numeric_warning": .bool(suppressNumericWarning)], message: "Server confirmed dataset completion.")
    }
    @discardableResult
    func publish(_ version: ConnectedVersion) async -> Bool {
        await versionCommand("stats_publish", version: version, allowed: [.completed, .submitted], message: "Server confirmed publication of this dataset.")
    }
    @discardableResult
    func submit(_ version: ConnectedVersion) async -> Bool {
        await versionCommand("stats_submit", version: version, allowed: [.completed], message: "Server confirmed submission for review.")
    }
    @discardableResult
    func review(_ version: ConnectedVersion, approve: Bool, reason: String = "") async -> Bool {
        guard reason.count <= 500 else { issue = .invalidInput; confirmation = nil; return false }
        return await versionCommand("stats_review", version: version, allowed: [.submitted], values: [
            "p_approve": .bool(approve), "p_reason": .string(reason)], message: approve ? "Server confirmed acceptance and publication." : "Server confirmed rejection. The proposal remains frozen.")
    }
    @discardableResult
    func requestEdit(_ version: ConnectedVersion, reason: String = "") async -> Bool {
        guard !isBusy else { return false }
        confirmation = nil
        guard reason.count <= 500 else { issue = .invalidInput; return false }
        guard version.status != .draft, versions.contains(where: { $0.id == version.id && $0.revision == version.revision }) else { issue = .reloadRequired; return false }
        guard beginMutation(), let game = selectedGame else { return false }
        defer { isBusy = false }
        do {
            let client = try await authenticatedClient()
            let request: ConnectedEditRequest = try await command(client, "stats_request_edit", [
                "p_source_version_id": .string(version.id.uuidString), "p_expected_revision": .integer(Int(version.revision)), "p_reason": .string(reason)])
            guard request.teamID == teamID, request.sourceVersionID == version.id,
                  request.requesterUserID == access?.userID, request.revision > 0, request.status == .pending else { throw ConnectedStatisticsIssue.invalidResponse }
            try await readGame(game, client: client)
            confirmation = "Server confirmed the edit request. Published statistics remain available."
            return true
        } catch { mutationFailed(error); return false }
    }
    private struct EditReviewResponse: Decodable { let request: ConnectedEditRequest; let version: ConnectedVersion? }
    @discardableResult
    func reviewEdit(_ request: ConnectedEditRequest, approve: Bool, reason: String = "") async -> Bool {
        guard !isBusy else { return false }
        confirmation = nil
        guard reason.count <= 500 else { issue = .invalidInput; return false }
        guard request.status == .pending, editRequests.contains(where: { $0.id == request.id && $0.revision == request.revision }) else { issue = .reloadRequired; return false }
        guard beginMutation(), let game = selectedGame else { return false }
        defer { isBusy = false }
        do {
            let client = try await authenticatedClient()
            let result: EditReviewResponse = try await command(client, "stats_review_edit", [
                "p_request_id": .string(request.id.uuidString), "p_expected_revision": .integer(Int(request.revision)),
                "p_approve": .bool(approve), "p_reason": .string(reason)])
            guard result.request.id == request.id, result.request.teamID == teamID,
                  result.request.sourceVersionID == request.sourceVersionID, result.request.requesterUserID == request.requesterUserID,
                  result.request.revision > request.revision, result.request.status == (approve ? .approved : .rejected) else { throw ConnectedStatisticsIssue.invalidResponse }
            if approve {
                guard let version = result.version, version.id == result.request.workingVersionID,
                      version.teamID == teamID, version.gameID == game.id, version.status == .draft,
                      version.authorUserID == request.requesterUserID, version.revision > 0 else { throw ConnectedStatisticsIssue.invalidResponse }
            } else if result.version != nil || result.request.workingVersionID != nil { throw ConnectedStatisticsIssue.invalidResponse }
            try await readGame(game, client: client)
            confirmation = approve ? "Server confirmed a new working revision. Published statistics remain intact." : "Server confirmed rejection of the edit request."
            return true
        } catch { mutationFailed(error); return false }
    }
    private func versionCommand(_ name: String, version: ConnectedVersion, allowed: [ConnectedVersionStatus], values: [String: AnyJSON] = [:], message: String) async -> Bool {
        guard !isBusy else { return false }
        confirmation = nil
        guard allowed.contains(version.status), versions.contains(where: { $0.id == version.id && $0.revision == version.revision && $0.status == version.status }) else { issue = .reloadRequired; reloadRequired = true; return false }
        guard beginMutation(), let game = selectedGame else { return false }
        defer { isBusy = false }
        do {
            let client = try await authenticatedClient()
            var parameters = values
            parameters["p_version_id"] = .string(version.id.uuidString)
            parameters["p_expected_revision"] = .integer(Int(version.revision))
            let result: ConnectedVersion = try await command(client, name, parameters)
            let expectedStatus: ConnectedVersionStatus
            switch name {
            case "stats_complete": expectedStatus = .completed
            case "stats_submit": expectedStatus = .submitted
            case "stats_publish": expectedStatus = .published
            case "stats_review": expectedStatus = values["p_approve"]?.boolValue == true ? .published : .rejected
            default: throw ConnectedStatisticsIssue.invalidResponse
            }
            guard result.status == expectedStatus, result.id == version.id, result.teamID == teamID, result.gameID == game.id,
                  result.datasetID == version.datasetID, result.datasetType == version.datasetType,
                  result.authorUserID == version.authorUserID, result.revision > version.revision else { throw ConnectedStatisticsIssue.invalidResponse }
            try await readGame(game, client: client)
            confirmation = message
            return true
        } catch { mutationFailed(error); return false }
    }
    private func beginMutation() -> Bool {
        guard !isBusy else { return false }
        confirmation = nil
        guard didLoadGame, selectedGame != nil, access != nil, !reloadRequired else { issue = .reloadRequired; return false }
        isBusy = true; issue = nil
        return true
    }
    private func mutationFailed(_ error: Error) {
        // Keep the editor's buffers outside this model; require a read before any further POST.
        reloadRequired = true; didLoadGame = false; access = nil
        fail(error)
    }
    func loadGame(_ game: ConnectedGame) async {
        guard !isBusy else { return }
        guard game.teamID == teamID else { issue = .invalidInput; return }
        retryGame = game; isBusy = true; issue = nil; confirmation = nil
        clearGame()
        defer { isBusy = false }
        do { try await readGame(game, client: authenticatedClient()) }
        catch { clearGame(); fail(error) }
    }
    func reload() async {
        if let game = retryGame { await loadGame(game) }
        else { await loadGames() }
    }
    private struct Preferences: Decodable {
        let suppressNumericWarning: Bool
        enum CodingKeys: String, CodingKey { case suppressNumericWarning = "suppress_numeric_warning" }
    }
    private func readGame(_ game: ConnectedGame, client: SupabaseClient) async throws {
        let gameRows: [ConnectedGame] = try await client.from("games").select().eq("team_id", value: teamID.uuidString).eq("id", value: game.id.uuidString).limit(1).execute().value
        guard let currentGame = gameRows.first, currentGame.teamID == teamID, currentGame.date != nil else { throw ConnectedStatisticsIssue.denied }
        let snapshot: TeamAccess = try await command(client, "team_access", [:])
        guard snapshot.teamID == teamID else { throw ConnectedStatisticsIssue.invalidResponse }
        let loadedRoster: [ServerRosterEntry] = try await pages(client, table: "roster_entries", order: "id")
        let loadedHistory: [ConnectedRosterLabel] = try await pages(client, table: "roster_entry_revisions", order: "roster_id")
        let loadedVersions: [ConnectedVersion] = try await pages(client, table: "stat_versions", order: "id", gameID: game.id)
        let loadedDatasets: [ConnectedDatasetPointer] = try await pages(client, table: "stat_datasets", order: "id", gameID: game.id)
        let requests: [ConnectedEditRequest] = try await pages(client, table: "stat_edit_requests", order: "id")
        let preferences: Preferences = try await command(client, "stats_preferences", [:])
        let outbox: [ConnectedExportOutbox] = snapshot.isOwner ? try await pages(client, table: "stat_export_outbox", order: "id", gameID: game.id) : []
        guard loadedRoster.allSatisfy({ $0.teamID == teamID }), loadedHistory.allSatisfy({ $0.teamID == teamID }),
              Set(loadedVersions.map(\.id)).count == loadedVersions.count,
              Set(loadedDatasets.map(\.datasetType)).count == loadedDatasets.count,
              loadedVersions.allSatisfy({ version in
                  version.teamID == teamID && version.gameID == game.id && version.revision > 0 &&
                  loadedDatasets.contains { $0.id == version.datasetID && $0.datasetType == version.datasetType } &&
                  version.coveredRoster.allSatisfy { covered in loadedHistory.contains { $0.id == covered.id && $0.version == covered.version } }
              }), loadedDatasets.allSatisfy({ pointer in
                  pointer.teamID == teamID && pointer.gameID == game.id && (pointer.publishedVersionID == nil ||
                  loadedVersions.contains { $0.id == pointer.publishedVersionID && $0.datasetID == pointer.id && $0.status == .published })
              }), requests.allSatisfy({ $0.teamID == teamID && $0.revision > 0 }),
              outbox.allSatisfy({ $0.teamID == teamID && $0.gameID == game.id }) else { throw ConnectedStatisticsIssue.invalidResponse }
        // Expose one complete snapshot. Partial failed reads never become empty-success UI.
        selectedGame = currentGame; access = snapshot; roster = loadedRoster; historicalRoster = loadedHistory
        versions = loadedVersions; datasets = loadedDatasets
        editRequests = requests.filter { request in loadedVersions.contains { $0.id == request.sourceVersionID } }
        exportOutbox = outbox; suppressNumericWarning = preferences.suppressNumericWarning
        didLoadGame = true; reloadRequired = false
    }
    private func clearGame() {
        selectedGame = nil; access = nil; roster = []; historicalRoster = []; versions = []; datasets = []
        editRequests = []; exportOutbox = []; suppressNumericWarning = false; didLoadGame = false
    }
    private func pages<T: Decodable>(_ client: SupabaseClient, table: String, order: String, gameID: UUID? = nil) async throws -> [T] {
        var rows: [T] = []
        let pageSize = 100
        for page in 0..<50 {
            let query = client.from(table).select().eq("team_id", value: teamID.uuidString)
            if let gameID { _ = query.eq("game_id", value: gameID.uuidString) }
            let ordered = query.order(order)
            if table == "roster_entry_revisions" { _ = ordered.order("version") }
            let values: [T] = try await ordered.range(from: page * pageSize, to: (page + 1) * pageSize - 1).execute().value
            rows.append(contentsOf: values)
            if values.count < pageSize { return rows }
        }
        throw ConnectedStatisticsIssue.tooManyRecords
    }
    private func command<T: Decodable>(_ client: SupabaseClient, _ name: String, _ values: [String: AnyJSON]) async throws -> T {
        var parameters = values; parameters["p_team_id"] = .string(teamID.uuidString)
        // A lost POST response cannot safely be replayed using an old revision.
        return try await client.rpc(name, params: parameters).retry(enabled: false).execute().value
    }
    private func fail(_ error: Error) {
        confirmation = nil
        if let error = error as? ConnectedStatisticsIssue { issue = error }
        else if let error = error as? PostgrestError {
            switch error.code {
            case "40001": issue = .conflict
            case "42501": issue = .denied
            case "22023", "23514", "23503": issue = .invalidInput
            default: issue = .server
            }
        } else if error is DecodingError { issue = .invalidResponse }
        else { issue = .server }
    }
}
