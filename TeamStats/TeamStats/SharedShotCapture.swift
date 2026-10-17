import Foundation
import Observation
import CryptoKit
import Supabase

nonisolated struct ShotDeviceScope: Codable, Equatable, Sendable {
    let environment: String
    let actorID: UUID
    let teamID: UUID
    var actorKey: String { Self.digest(environment + "|" + actorID.uuidString) }
    var key: String { actorKey + "-" + teamID.uuidString }
    static func digest(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
}
nonisolated struct ShotPreparedEntry: Codable, Equatable, Identifiable, Sendable {
    let gameID: UUID
    let sessionID: UUID
    let title: String
    let expiresAt: Date?
    var id: UUID { gameID }
}
nonisolated struct ShotPreparation: Codable, Sendable {
    let scope: ShotDeviceScope
    var checking: UUID?
    var entries: [ShotPreparedEntry]
    var eligibleGameIDs: [UUID]?
}
nonisolated struct ShotPreparedRow: Identifiable, Sendable {
    let scope: ShotDeviceScope
    let entry: ShotPreparedEntry
    var id: String { scope.key + entry.gameID.uuidString }
}

/// A protected continuation permit, never a cached remote permission or an upload queue.
actor ShotPreparationStore {
    static let shared = ShotPreparationStore()
    private let root: URL?
    init(root: URL? = nil) { self.root = root }
    func directory() throws -> URL { try root ?? GameStorage.fileURL().deletingLastPathComponent() }
    func permitURL(_ scope: ShotDeviceScope) throws -> URL { try directory().appendingPathComponent("shot-permit-\(scope.key).json") }
    func documentURL(_ scope: ShotDeviceScope, game: UUID, session: UUID) throws -> URL {
        try directory().appendingPathComponent("shot-shared-\(scope.key)-\(game)-\(session).json")
    }
    func outboxURL(_ scope: ShotDeviceScope, game: UUID) throws -> URL { try directory().appendingPathComponent("shot-command-\(scope.key)-\(game).json") }
    private func read(_ scope: ShotDeviceScope) throws -> ShotPreparation? {
        let url = try permitURL(scope)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Self.readBounded(url, maximum: 1024 * 1024)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let value = try decoder.decode(ShotPreparation.self, from: data)
        guard value.scope == scope, value.entries.count <= 1000,
              Set(value.entries.map(\.gameID)).count == value.entries.count else { throw ShotCaptureIssue.corrupt }
        return value
    }
    private func write(_ value: ShotPreparation) throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        guard data.count <= 1024 * 1024 else { throw ShotCaptureIssue.limit }
        try data.write(to: permitURL(value.scope), options: [.atomic, .completeFileProtection])
        guard try read(value.scope)?.checking == value.checking else { throw ShotCaptureIssue.corrupt }
    }
    func lock(_ scope: ShotDeviceScope) throws -> UUID {
        var value = try read(scope) ?? ShotPreparation(scope: scope, checking: nil, entries: [], eligibleGameIDs: [])
        let token = UUID(); value.checking = token; value.eligibleGameIDs = []; try write(value); return token
    }
    func unlock(_ scope: ShotDeviceScope, token: UUID, entry: ShotPreparedEntry?) throws {
        try Task.checkCancellation()
        guard var value = try read(scope), value.checking == token else { throw ShotCaptureIssue.stale }
        if let entry { value.entries.removeAll { $0.gameID == entry.gameID }; value.entries.append(entry); value.eligibleGameIDs = [entry.gameID] }
        value.checking = nil; try write(value)
    }
    func entries(_ scope: ShotDeviceScope, now: Date = Date()) throws -> [ShotPreparedEntry] {
        guard let value = try read(scope), value.checking == nil else { return [] }
        return value.entries.filter { value.eligibleGameIDs?.contains($0.gameID) == true && ($0.expiresAt ?? .distantFuture) > now }
    }
    func catalog(environment: String, actorID: UUID) throws -> [ShotPreparedRow] {
        let prefix = "shot-permit-" + ShotDeviceScope(environment: environment, actorID: actorID, teamID: UUID()).actorKey + "-"
        let files = try FileManager.default.contentsOfDirectory(at: directory(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "json" }
        guard files.count <= 1000 else { throw ShotCaptureIssue.limit }
        return try files.flatMap { url in
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let preparation = try decoder.decode(ShotPreparation.self, from: Self.readBounded(url, maximum: 1024 * 1024))
            guard preparation.scope.environment == environment, preparation.scope.actorID == actorID,
                  try permitURL(preparation.scope) == url else { throw ShotCaptureIssue.corrupt }
            return try entries(preparation.scope).map { ShotPreparedRow(scope: preparation.scope, entry: $0) }
        }
    }
    static func readBounded(_ url: URL, maximum: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
        guard values.isSymbolicLink == false, values.isRegularFile == true, (values.fileSize ?? Int.max) <= maximum else { throw ShotCaptureIssue.corrupt }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let data = try handle.read(upToCount: maximum + 1) ?? Data()
        guard data.count <= maximum else { throw ShotCaptureIssue.limit }; return data
    }
    func pending(at url: URL) throws -> ShotFrozenCommand? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(ShotCommandEnvelope.self, from: Self.readBounded(url, maximum: 12 * 1024 * 1024)).pending
    }
    func rejection(at url: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(ShotCommandEnvelope.self, from: Self.readBounded(url, maximum: 12 * 1024 * 1024)).rejection
    }
    func reject(expected batch: UUID, code: String, at url: URL) throws {
        guard ["PT409", "22023", "42501"].contains(code), let command = try pending(at: url), command.batch == batch else { throw ShotCaptureIssue.stale }
        try JSONEncoder().encode(ShotCommandEnvelope(pending: command, rejection: code)).write(to: url, options: [.atomic, .completeFileProtection])
    }
    func archiveRejected(expected batch: UUID, at url: URL) throws {
        guard let command = try pending(at: url), command.batch == batch, try rejection(at: url) != nil else { throw ShotCaptureIssue.stale }
        let archive = url.deletingLastPathComponent().appendingPathComponent("shot-retained-command-\(batch).json")
        if FileManager.default.fileExists(atPath: archive.path) {
            guard let prior = try pending(at: archive), prior.batch == batch, prior.arguments == command.arguments else { throw ShotCaptureIssue.stale }
        } else {
            try Self.readBounded(url, maximum: 12 * 1024 * 1024).write(to: archive, options: [.atomic, .completeFileProtection])
        }
        try clear(expected: batch, at: url)
    }
    func prepared(_ entry: ShotPreparedEntry, scope: ShotDeviceScope) throws -> (ShotCaptureDocument, URL, ShotFrozenCommand?) {
        guard try entries(scope).contains(entry) else { throw ShotCaptureIssue.stale }
        let url = try documentURL(scope, game: entry.gameID, session: entry.sessionID)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let doc = try decoder.decode(ShotCaptureDocument.self, from: Self.readBounded(url, maximum: 10 * 1024 * 1024))
        try doc.validate()
        guard doc.id == entry.sessionID, doc.context.teamID == scope.teamID, doc.context.gameID == entry.gameID else { throw ShotCaptureIssue.corrupt }
        return (doc, url, try pending(at: outboxURL(scope, game: entry.gameID)))
    }
    func reserve(_ command: ShotFrozenCommand, at url: URL) throws {
        guard try pending(at: url) == nil else { throw ShotCaptureIssue.stale }
        try persist(command, at: url)
    }
    func clear(expected batch: UUID, at url: URL) throws {
        guard try pending(at: url)?.batch == batch else { throw ShotCaptureIssue.stale }
        try persist(nil, at: url)
    }
    func persist(_ command: ShotFrozenCommand?, at url: URL) throws {
        let data = try JSONEncoder().encode(ShotCommandEnvelope(pending: command))
        guard data.count <= 12 * 1024 * 1024 else { throw ShotCaptureIssue.limit }
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}
nonisolated struct ShotFrozenCommand: Codable, Sendable {
    let batch: UUID
    let rpc: String
    let arguments: [String: AnyJSON]
    let payloadDigest: String?
    var operation: String? {
        switch rpc {
        case "shots_save": "save"
        case "shots_assign": "assign"
        case "shots_recovery": "recovery"
        case "shots_score_confirm": "score_confirm"
        case "shots_decide": arguments["p_action"]?.stringValue
        default: nil
        }
    }
}
nonisolated struct ShotCommandEnvelope: Codable { let pending: ShotFrozenCommand?; var rejection: String? = nil }

nonisolated struct SharedShotState: Decodable, Sendable {
    let team_id: UUID
    let game_id: UUID
    let session_id: UUID?
    let recorder_user_id: UUID?
    let assignment_revision: Int
    let state_revision: Int
    let snapshot_id: UUID?
    let document: ShotCaptureDocument?
    let coverage_claim: String?
    let status: String
    let can_record: Bool
    let can_review: Bool
    let can_publish: Bool
    let recording_valid_until: String?
}
nonisolated struct ShotScoreReference: Decodable, Sendable {
    let team_id: UUID
    let game_id: UUID
    let revision: Int
    let reference_id: UUID?
    let our_points: Int?
    let opponent_points: Int?
    let source_note: String?
    let can_confirm: Bool
}
nonisolated struct ShotRecoveryProposal: Decodable, Identifiable, Sendable {
    let snapshot_id: UUID
    let local_revision: Int
    let parent_snapshot_id: UUID
    let uploader_user_id: UUID
    var id: UUID { snapshot_id }
}

/// Invalidates already mounted captures when another screen checks the same team.
@MainActor @Observable final class ShotDeviceGate {
    static let shared = ShotDeviceGate()
    private var epochs: [String: UUID] = [:]
    func lock(_ scope: ShotDeviceScope) -> UUID { let epoch = UUID(); epochs[scope.key] = epoch; return epoch }
    func matches(_ scope: ShotDeviceScope, _ epoch: UUID?) -> Bool { epoch != nil && epochs[scope.key] == epoch }
}

/// One instance serializes explicit online operations. Every write is frozen on disk first.
@MainActor @Observable final class SharedShotCapture {
    private(set) var score: ShotScoreReference?
    private(set) var scoreIssue: String?
    private(set) var state: SharedShotState?
    private(set) var recorder: ShotCaptureRecorder?
    private(set) var pending: ShotFrozenCommand?
    private(set) var inspectedProposal: ShotCaptureDocument?
    private(set) var hasMoreProposals = false
    private(set) var proposals: [ShotRecoveryProposal] = []
    private(set) var isBusy = false
    private(set) var issue: String?
    private(set) var feedbackConfirmed = false
    private(set) var lastConfirmedBatch: UUID?
    private(set) var receiptNotFound = false
    private(set) var rejectedCommand = false
    private(set) var offline = false
    private(set) var hasAuthorizedContent = false
    private(set) var localConflict = false
    private(set) var retainedBranchURL: URL?
    private(set) var deviceDocument: ShotCaptureDocument?
    @ObservationIgnored let scope: ShotDeviceScope
    @ObservationIgnored let gameID: UUID
    @ObservationIgnored let title: String
    @ObservationIgnored private let identityCurrent: () -> Bool
    @ObservationIgnored private let request: (String, [String: AnyJSON]) async throws -> AnyJSON
    @ObservationIgnored private let store: ShotPreparationStore
    @ObservationIgnored private var eligibility = false
    private(set) var knownExpiry: Date?
    @ObservationIgnored private var gateEpoch: UUID?
    @ObservationIgnored private var currentOperation: UUID?

    convenience init(account: BackendAccount, scope: ShotDeviceScope, gameID: UUID, title: String, store: ShotPreparationStore = .shared) {
        let generation = account.authenticationGeneration
        self.init(scope: scope, gameID: gameID, title: title, store: store, request: { name, args in
            let client = try await account.authenticatedClient()
            return try await client.rpc(name, params: args).retry(enabled: false).execute().value
        }, isCurrent: {
            account.authenticationGeneration == generation && account.offlineClipActorID == scope.actorID && account.configuration?.url.absoluteString == scope.environment
        })
    }
    init(scope: ShotDeviceScope, gameID: UUID, title: String, store: ShotPreparationStore,
         request: @escaping (String, [String: AnyJSON]) async throws -> AnyJSON, isCurrent: @escaping () -> Bool) {
        self.scope = scope; self.gameID = gameID; self.title = title; self.store = store
        self.request = request; identityCurrent = isCurrent
    }
    var isCurrent: Bool { identityCurrent() }
    var contentCurrent: Bool { isCurrent && hasAuthorizedContent && (knownExpiry ?? .distantFuture) > Date() && ShotDeviceGate.shared.matches(scope, gateEpoch) }
    var canRecord: Bool { contentCurrent && eligibility && !isBusy && !localConflict && (knownExpiry ?? .distantFuture) > Date() }
    var scopeArguments: [String: AnyJSON] { ["p_team_id": .string(scope.teamID.uuidString), "p_game_id": .string(gameID.uuidString)] }
    private func call(_ name: String, _ args: [String: AnyJSON]) async throws -> AnyJSON {
        guard isCurrent else { throw AccountIssue.noVerifiedSession }
        let result = try await request(name, args)
        try Task.checkCancellation()
        guard isCurrent else { throw AccountIssue.noVerifiedSession }; return result
    }
    private func decode<T: Decodable>(_ type: T.Type, _ json: AnyJSON) throws -> T {
        let data = try JSONEncoder().encode(json)
        guard data.count <= 12 * 1024 * 1024 else { throw ShotCaptureIssue.limit }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
    private func validate(_ value: SharedShotState) throws {
        guard value.team_id == scope.teamID, value.game_id == gameID, value.state_revision >= 0, value.assignment_revision >= 0 else { throw ShotCaptureIssue.corrupt }
        if let doc = value.document {
            try doc.validate()
            guard doc.id == value.session_id, doc.context.gameID == gameID, doc.context.teamID == scope.teamID, doc.context.isShared else { throw ShotCaptureIssue.corrupt }
        }
    }
    func openPrepared(_ entry: ShotPreparedEntry) async {
        guard isCurrent, !isBusy else { return }
        gateEpoch = ShotDeviceGate.shared.lock(scope)
        let epoch = gateEpoch
        isBusy = true; defer { isBusy = false }
        do {
            guard entry.gameID == gameID else { throw ShotCaptureIssue.invalid }
            let (doc, url, frozen) = try await store.prepared(entry, scope: scope)
            guard isCurrent, ShotDeviceGate.shared.matches(scope, epoch) else { throw ShotCaptureIssue.stale }
            knownExpiry = entry.expiresAt
            eligibility = true; offline = true; hasAuthorizedContent = true
            recorder = try makeRecorder(doc, url: url); pending = frozen
        } catch { conceal(); issue = "Prepared capture is locked or unavailable. Reconnect to verify access; saved files remain on this device." }
    }
    private func makeRecorder(_ doc: ShotCaptureDocument, url: URL) throws -> ShotCaptureRecorder {
        try ShotCaptureRecorder(document: doc, url: url, isCurrentContext: { [weak self] in
            guard let self else { return false }; return self.contentCurrent && self.eligibility && (self.knownExpiry ?? .distantFuture) > Date()
        })
    }
    private func install(_ value: SharedShotState) async throws {
        state = value; hasAuthorizedContent = true; offline = false; localConflict = false
        guard value.can_record, let doc = value.document else { recorder = nil; return }
        let url = try await store.documentURL(scope, game: gameID, session: doc.id)
        let local: ShotCaptureDocument
        if FileManager.default.fileExists(atPath: url.path) {
            local = try await ShotCaptureDisk.shared.load(from: url, context: doc.context)
            // Never replace a different branch or silently discard newer offline work.
            if local != doc {
                let common = zip(local.journal, doc.journal).allSatisfy { $0 == $1 }
                if common && local.revision >= doc.revision { /* retain the unsent suffix */ }
                else { localConflict = true }
            }
        } else { try await ShotCaptureDisk.shared.create(doc, at: url); local = doc }
        guard isCurrent else { throw AccountIssue.noVerifiedSession }
        deviceDocument = local
        eligibility = !localConflict
        recorder = try makeRecorder(local, url: url)
    }
    func refresh() async {
        guard isCurrent, !isBusy, recorder?.needsSave != true, recorder?.isBusy != true else { return }
        gateEpoch = ShotDeviceGate.shared.lock(scope)
        isBusy = true; issue = nil; feedbackConfirmed = false; eligibility = false; recorder?.invalidate()
        defer { isBusy = false }
        do {
            let token = try await store.lock(scope); currentOperation = token
            let value = try decode(SharedShotState.self, await call("shots_state", scopeArguments)); try validate(value)
            guard isCurrent, currentOperation == token else { return }
            proposals = []
            if value.can_review { proposals = try decode([ShotRecoveryProposal].self, await call("shots_recoveries", scopeArguments)); hasMoreProposals = proposals.count == 50 }
            score = nil; scoreIssue = nil
            do {
                let reference = try decode(ShotScoreReference.self, await call("shots_score_read", scopeArguments))
                guard reference.team_id == scope.teamID, reference.game_id == gameID, reference.revision >= 0,
                      reference.our_points.map({ $0 >= 0 }) ?? true, reference.opponent_points.map({ $0 >= 0 }) ?? true else { throw ShotCaptureIssue.corrupt }
                score = reference
            } catch {
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                if let failure = error as? PostgrestError, ["42501", "PGRST301"].contains(failure.code ?? "") { throw error }
                guard isCurrent else { throw error }
                scoreIssue = "Official score reference unavailable. Capture loading remains independent; this is not an empty-score result."
            }
            pending = try await store.pending(at: store.outboxURL(scope, game: gameID))
            rejectedCommand = try await store.rejection(at: store.outboxURL(scope, game: gameID)) != nil
            try Task.checkCancellation()
            knownExpiry = value.can_record ? value.recording_valid_until.flatMap(administrationDate) : nil
            try await install(value)
            try Task.checkCancellation()
            if value.can_record, let session = value.session_id, !localConflict {
                let expiry = value.recording_valid_until.flatMap(administrationDate); knownExpiry = expiry
                try await store.unlock(scope, token: token, entry: ShotPreparedEntry(gameID: gameID, sessionID: session, title: title, expiresAt: expiry))
            }
        } catch { conceal(); issue = "Current shot access could not be verified. Prepared continuation is locked until a successful online check. Saved entries were preserved." }
    }
    func retainBranchAndUseServer() async {
        guard contentCurrent, !isBusy, pending == nil, let state, state.can_record,
              let server = state.document, let local = deviceDocument, localConflict else { return }
        isBusy = true; eligibility = false; recorder?.invalidate(); defer { isBusy = false }
        do {
            let url = try await store.documentURL(scope, game: gameID, session: local.id)
            let copy = url.deletingLastPathComponent().appendingPathComponent("shot-retained-branch-\(UUID()).json")
            try await ShotCaptureDisk.shared.preserveAndUseServer(local, server: server, at: url, copy: copy)
            guard isCurrent else { return }
            retainedBranchURL = copy; deviceDocument = server; localConflict = false
            issue = "Device branch retained separately. Refresh current access before continuing from the selected server head."
        } catch { issue = "Could not preserve and switch branches. Existing capture files remain; refresh and retry." }
    }
    func register(players: [ServerRosterEntry]) async {
        guard let state, state.can_record, state.document == nil else { return }
        do {
            let doc = ShotCaptureDocument(schemaVersion: 1, id: UUID(), context: ShotCaptureContext(gameID: gameID, teamID: scope.teamID, actorID: scope.actorID, assignmentRevision: state.assignment_revision),
                players: players.filter { $0.archivedAt == nil }.map { ShotCapturePlayer(id: $0.id.uuidString, name: $0.displayName, number: $0.jerseyNumber, temporary: false) }, journal: [])
            try doc.validate(); await save(doc, recovery: false)
        } catch { issue = "Could not prepare this actual-roster capture." }
    }
    func assign(_ actor: UUID, reason: String) async {
        guard let state else { return }
        var args = revisionArguments(state); args["p_recorder_user_id"] = .string(actor.uuidString); args["p_reason"] = .string(reason)
        await command("shots_assign", args)
    }
    private func revisionArguments(_ state: SharedShotState) -> [String: AnyJSON] {
        var args = scopeArguments; args["p_assignment_revision"] = .integer(state.assignment_revision); args["p_expected_revision"] = .integer(state.state_revision); return args
    }
    func save(_ doc: ShotCaptureDocument, recovery: Bool) async {
        guard let state else { return }
        do {
            let data = try ShotCaptureStorage.encoded(doc)
            let text = String(decoding: data, as: UTF8.self)
            var args = revisionArguments(state); args["p_document_text"] = .string(text)
            if !recovery { args["p_coverage_claim"] = .string("unknown") }
            await command(recovery ? "shots_recovery" : "shots_save", args, digest: ShotDeviceScope.digest(text))
        } catch { issue = "Capture validation failed; no submission was made." }
    }
    func confirmScore(our: Int?, opponent: Int?, source: String) async {
        guard let score, score.can_confirm, our != nil || opponent != nil,
              our.map({ (0...Int(Int32.max)).contains($0) }) ?? true, opponent.map({ (0...Int(Int32.max)).contains($0) }) ?? true,
              !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, source.count <= 200 else { return }
        var args = scopeArguments; args["p_expected_revision"] = .integer(score.revision)
        args["p_our_points"] = our.map(AnyJSON.integer) ?? .null; args["p_opponent_points"] = opponent.map(AnyJSON.integer) ?? .null; args["p_source_note"] = .string(source)
        await command("shots_score_confirm", args)
    }
    func decide(_ action: String, snapshot: UUID? = nil, reason: String) async {
        guard let state, let snapshot = snapshot ?? state.snapshot_id else { return }
        var args = revisionArguments(state); args["p_snapshot_id"] = .string(snapshot.uuidString); args["p_action"] = .string(action); args["p_reason"] = .string(reason)
        args["p_displaced_snapshot_id"] = action == "adopt" ? state.snapshot_id.map { .string($0.uuidString) } ?? .null : .null
        await command("shots_decide", args)
    }
    private func command(_ rpc: String, _ arguments: [String: AnyJSON], digest: String? = nil) async {
        guard isCurrent, !isBusy, pending == nil, recorder?.needsSave != true, recorder?.isBusy != true else { return }
        feedbackConfirmed = false
        let batch = UUID(); var args = arguments
        if rpc == "shots_assign" { args["p_expected_assignment"] = args.removeValue(forKey: "p_assignment_revision") }
        args["p_batch_id"] = .string(batch.uuidString)
        let frozen = ShotFrozenCommand(batch: batch, rpc: rpc, arguments: args, payloadDigest: digest)
        isBusy = true
        do {
            try await store.reserve(frozen, at: store.outboxURL(scope, game: gameID)); pending = frozen
        } catch { isBusy = false; issue = "Could not reserve this command safely. Another frozen command may require recovery. Nothing new was sent."; return }
        isBusy = false
        await sendPending(initial: true)
    }
    func sendPending(initial: Bool = false) async {
        guard initial || receiptNotFound else { return }
        guard isCurrent, !isBusy, let pending else { return }
        gateEpoch = ShotDeviceGate.shared.lock(scope)
        isBusy = true; eligibility = false; recorder?.invalidate(); issue = nil; receiptNotFound = false
        defer { isBusy = false }
        do {
            _ = try await store.lock(scope)
            try validateCommand(pending)
            let receipt = try await call(pending.rpc, pending.arguments)
            try await accept(receipt, pending)
        } catch {
            conceal()
            if let error = error as? PostgrestError, let code = error.code, ["PT409", "22023", "42501"].contains(code) {
                do { try await store.reject(expected: pending.batch, code: code, at: store.outboxURL(scope, game: gameID)); rejectedCommand = true }
                catch { rejectedCommand = false }
            }
            issue = "Command not confirmed. Recover its receipt before retrying; do not submit the capture again. Current authority will be rechecked." }
        // No automatic replay or upload. A successful receipt still requires a fresh state read.
    }
    func recoverReceipt() async {
        guard isCurrent, !isBusy, let pending else { return }
        gateEpoch = ShotDeviceGate.shared.lock(scope)
        isBusy = true; eligibility = false; recorder?.invalidate(); issue = nil
        defer { isBusy = false }
        do {
            _ = try await store.lock(scope)
            try validateCommand(pending)
            var args = scopeArguments; args["p_batch_id"] = .string(pending.batch.uuidString)
            let receipt = try await call(pending.rpc == "shots_score_confirm" ? "shots_score_receipt" : "shots_receipt", args)
            if receipt.isNil { receiptNotFound = true; issue = "No committed receipt was found. You may explicitly retry the same frozen command; it may still be rejected as stale." }
            else { try await accept(receipt, pending) }
        } catch {
            conceal()
            if let error = error as? PostgrestError, let code = error.code, ["PT409", "42501"].contains(code) {
                do { try await store.reject(expected: pending.batch, code: code, at: store.outboxURL(scope, game: gameID)); rejectedCommand = true }
                catch { rejectedCommand = false }
            }
            issue = "Receipt recovery unavailable. The frozen command and capture remain on this device. A denied receipt does not prove the original write failed."
        }
    }
    func watchExpiry() async {
        guard let expiry = knownExpiry else { return }
        do { try await Task.sleep(for: .seconds(max(0, expiry.timeIntervalSinceNow))) }
        catch { return }
        guard isCurrent, knownExpiry == expiry, expiry <= Date() else { return }
        gateEpoch = ShotDeviceGate.shared.lock(scope); conceal()
        issue = "Known recording permission has expired. Reconnect to verify current authority; captured entries remain preserved."
        _ = try? await store.lock(scope)
    }
    func archiveRejected() async {
        guard isCurrent, !isBusy, rejectedCommand, let pending else { return }
        isBusy = true; defer { isBusy = false }
        do {
            try await store.archiveRejected(expected: pending.batch, at: store.outboxURL(scope, game: gameID))
            guard isCurrent else { return }
            self.pending = nil; rejectedCommand = false; receiptNotFound = false
            issue = "Rejected command retained separately. Refresh current access before proposing recovery. This does not establish whether an earlier submission was accepted."
        } catch { issue = "Could not retain and supersede this command. Its pending bytes remain preserved." }
    }
    private func conceal() {
        feedbackConfirmed = false; eligibility = false; hasAuthorizedContent = false; score = nil; scoreIssue = nil; state = nil; proposals = []; inspectedProposal = nil; deviceDocument = nil; recorder?.invalidate()
    }
    func loadProposal(_ id: UUID) async {
        guard isCurrent, !isBusy else { return }
        gateEpoch = ShotDeviceGate.shared.lock(scope); eligibility = false; recorder?.invalidate(); inspectedProposal = nil
        isBusy = true; defer { isBusy = false }
        do {
            _ = try await store.lock(scope)
            var args = scopeArguments; args["p_snapshot_id"] = .string(id.uuidString)
            let doc = try decode(ShotCaptureDocument.self, await call("shots_recovery_document", args)); try doc.validate()
            guard doc.context.teamID == scope.teamID, doc.context.gameID == gameID else { throw ShotCaptureIssue.corrupt }
            inspectedProposal = doc
        } catch { conceal(); issue = "Recovery inspection unavailable. Reverify current access." }
    }
    func moreProposals() async {
        guard isCurrent, !isBusy, let last = proposals.last else { return }
        gateEpoch = ShotDeviceGate.shared.lock(scope)
        isBusy = true; defer { isBusy = false }
        do {
            _ = try await store.lock(scope); eligibility = false; recorder?.invalidate()
            var args = scopeArguments; args["p_after"] = .string(last.id.uuidString)
            let next = try decode([ShotRecoveryProposal].self, await call("shots_recoveries", args))
            guard next.count <= 50, next.allSatisfy({ row in !proposals.contains { $0.id == row.id } }) else { throw ShotCaptureIssue.corrupt }
            proposals += next; hasMoreProposals = next.count == 50
        } catch { conceal(); issue = "Recovery listing unavailable. Reverify current access." }
    }
    private func validateCommand(_ command: ShotFrozenCommand) throws {
        guard ["shots_save", "shots_assign", "shots_decide", "shots_recovery", "shots_score_confirm"].contains(command.rpc),
              command.arguments["p_team_id"]?.stringValue.flatMap(UUID.init(uuidString:)) == scope.teamID,
              command.arguments["p_game_id"]?.stringValue.flatMap(UUID.init(uuidString:)) == gameID,
              command.arguments["p_batch_id"]?.stringValue.flatMap(UUID.init(uuidString:)) == command.batch else { throw ShotCaptureIssue.corrupt }
    }
    private func accept(_ receipt: AnyJSON, _ command: ShotFrozenCommand) async throws {
        guard isCurrent, let values = receipt.objectValue,
              values["batch_id"]?.stringValue.flatMap(UUID.init(uuidString:)) == command.batch,
              values["actor_user_id"]?.stringValue.flatMap(UUID.init(uuidString:)) == scope.actorID,
              values["team_id"]?.stringValue.flatMap(UUID.init(uuidString:)) == scope.teamID,
              values["game_id"]?.stringValue.flatMap(UUID.init(uuidString:)) == gameID,
              values["operation"]?.stringValue == command.operation,
              command.payloadDigest == nil || values["document_digest"]?.stringValue == command.payloadDigest else { throw ShotCaptureIssue.corrupt }
        try await store.clear(expected: command.batch, at: store.outboxURL(scope, game: gameID))
        lastConfirmedBatch = command.batch
        pending = nil; receiptNotFound = false; rejectedCommand = false
        conceal(); feedbackConfirmed = true
        issue = "Server receipt confirmed. Refresh current capture before another action. Saving a draft is not review or publication."
    }
}
