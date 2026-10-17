import Foundation
import Observation
import Supabase

nonisolated enum PrivateFileKind: String, Codable, Sendable { case practice, scouting
    var label: String { self == .practice ? "Practice clips" : "Scouting PDFs" }
    var maximumBytes: Int { (self == .practice ? 10 : 5) * 1024 * 1024 }
}
nonisolated enum PrivateFileStatus: String, Codable, Sendable { case uploading, ready, submitted, rejected, published, failed }
nonisolated enum PrivateFileAction: String, Sendable { case submit, publish, approve, reject }
nonisolated struct PrivateFileResource: Codable, Identifiable, Sendable {
    let id: UUID; let teamID: UUID; let kind: PrivateFileKind
    let playID: UUID?; let gameID: UUID?; let publishedVersionID: UUID?; let archivedAt: String?
    var targetID: UUID? { kind == .practice ? playID : gameID }
    enum CodingKeys: String, CodingKey { case id, kind; case teamID = "team_id", playID = "play_id", gameID = "game_id", publishedVersionID = "published_version_id", archivedAt = "archived_at" }
}
nonisolated struct PrivateFileVersion: Codable, Identifiable, Sendable {
    let id: UUID; let teamID: UUID; let resourceID: UUID; let authorUserID: UUID; let operationID: UUID
    let revision: Int64; let status: PrivateFileStatus; let title: String; let notes: String; let declaredBytes: Int
    let byteCount: Int?; let sha256: String?; let contentType: String?; let basePublishedVersionID: UUID?; let reviewReason: String
    enum CodingKeys: String, CodingKey {
        case id, revision, status, title, notes
        case teamID = "team_id", resourceID = "resource_id", authorUserID = "author_user_id", operationID = "operation_id", declaredBytes = "declared_bytes"
        case byteCount = "byte_count", sha256, contentType = "content_type", basePublishedVersionID = "base_published_version_id", reviewReason = "review_reason"
    }
}
nonisolated struct PrivateFileInput: Equatable, Sendable {
    var title = ""; var notes = ""
    init() {}
    init(_ version: PrivateFileVersion) { title = version.title; notes = version.notes }
    var validDraft: Bool {
        title.count <= 120 && notes.count <= 1000 && !title.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        && !notes.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\r" && $0 != "\t" }
    }
}
nonisolated enum PrivateFileIssue: Error, Equatable {
    case invalidInput, invalidResponse, denied, conflict, server, capacity, hostedUnavailable, reloadRequired, reconcileRequired, integrity, storage, insufficientSpace, invalidFile, missingUpload, validationFailed
    var message: String {
        switch self {
        case .invalidInput: "Check the file size, title and notes. Original files are unchanged."
        case .invalidResponse: "The server returned an unexpected file record. Reload before continuing."
        case .denied: "Current server access does not allow this file action. Reload or sign in again."
        case .conflict: "This saved version changed. Reload and review before trying again."
        case .server: "The file request could not be confirmed. Preserve your input and retry loading or explicitly reconcile."
        case .capacity: "File capacity is unavailable or exhausted. Preserve your input until trusted capacity is verified."
        case .hostedUnavailable: "Hosted file delivery is unavailable until capacity, validation and $0 protection are verified."
        case .reloadRequired: "Reload saved files before changing this record."
        case .reconcileRequired: "The upload outcome is uncertain. Reconcile it before another upload; do not repeat the transfer."
        case .integrity: "The complete file did not match its saved length and hash. Playback is unavailable."
        case .storage: "Device file storage is unavailable. Existing copies are preserved."
        case .insufficientSpace: "There is not enough free device space. Existing copies are preserved."
        case .missingUpload: "The server confirmed no stored object. Start a new upload operation; the old draft and allocation remain retained."
        case .validationFailed: "Server validation failed for this upload. The failed operation and allocation remain retained. Start a new draft after validation is available."
        case .invalidFile: "The trusted validator rejected this file. Choose a supported readable PDF or H264/AAC MP4."
        }
    }
}
nonisolated private enum FileValue: Encodable { case string(String), integer(Int64), null
    func encode(to encoder: Encoder) throws { var value = encoder.singleValueContainer(); switch self {
    case .string(let string): try value.encode(string); case .integer(let integer): try value.encode(integer); case .null: try value.encodeNil() } }
}

@MainActor @Observable
final class PrivateFiles {
    let teamID: UUID; let kind: PrivateFileKind; let targetID: UUID
    private(set) var resources: [PrivateFileResource] = []
    private(set) var versions: [PrivateFileVersion] = []
    private(set) var access: TeamAccess?
    private(set) var didLoad = false
    private(set) var isBusy = false
    private(set) var issue: PrivateFileIssue?
    private(set) var confirmation: String?
    private(set) var contentConcealed = false
    private(set) var reloadRequired = false
    private(set) var pendingVersion: PrivateFileVersion?
    private(set) var uploadNeedsReconciliation = false
    @ObservationIgnored private let configuration: () -> AccountConfiguration?
    @ObservationIgnored private let authenticatedClient: () async throws -> SupabaseClient
    @ObservationIgnored private let accessToken: () async throws -> String
    @ObservationIgnored private let offlineActor: () -> UUID?
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored let retention: ClipRetention
    @ObservationIgnored private var proposal: FileProposal?
    private struct FileProposal {
        let resourceID: UUID; let operationID: UUID; let baseID: UUID?; let bytes: Data; let input: PrivateFileInput
    }
    init(teamID: UUID, kind: PrivateFileKind, targetID: UUID, account: BackendAccount, retention: ClipRetention = ClipRetention()) {
        self.teamID = teamID; self.kind = kind; self.targetID = targetID
        configuration = { account.configuration }; authenticatedClient = { try await account.authenticatedClient() }
        accessToken = { try await account.accessToken() }
        offlineActor = { account.offlineClipActorID }; session = AccountHTTP.session(resourceTimeout: 90); self.retention = retention
    }
    init(teamID: UUID, kind: PrivateFileKind, targetID: UUID, configuration: AccountConfiguration,
         authenticatedClient: @escaping () async throws -> SupabaseClient, offlineActor: @escaping () -> UUID?,
         session: URLSession = AccountHTTP.session(resourceTimeout: 90), retention: ClipRetention = ClipRetention(),
         accessToken: (() async throws -> String)? = nil) {
        self.teamID = teamID; self.kind = kind; self.targetID = targetID
        self.configuration = { configuration }; self.authenticatedClient = authenticatedClient
        // Existing integration fixtures may supply a standalone SDK client; the app supplies its single Auth source.
        self.accessToken = accessToken ?? { try await authenticatedClient().auth.session.accessToken }
        self.offlineActor = offlineActor; self.session = session; self.retention = retention
    }
    var hasPendingReservation: Bool { proposal != nil && pendingVersion == nil }
    var canContribute: Bool { didLoad && (kind == .practice || access?.isOwner == true || access?.capabilities.contains { $0.rawValue == "scouting.upload" } == true) }
    var canPublishOwn: Bool { canContribute && kind == .practice && (access?.can(.practiceUpload) == true || access?.can(.practicePublish) == true) }
    var published: [PrivateFileVersion] { resources.compactMap { resource in versions.first { $0.id == resource.publishedVersionID && $0.status == .published && resource.archivedAt == nil } } }
    var ownDrafts: [PrivateFileVersion] { versions.filter { $0.authorUserID == access?.userID && [.uploading, .ready].contains($0.status) } }
    var clipScope: ClipScope? {
        guard kind == .practice, let configuration = configuration(), let actor = offlineActor() else { return nil }
        return ClipScope(projectURL: configuration.url, actorID: actor, teamID: teamID)
    }
    func load() async {
        guard !isBusy else { return }; isBusy = true; defer { isBusy = false }
        issue = nil; didLoad = false
        do { try await readSnapshot(authenticatedClient()) }
        catch { fail(error); resources = []; versions = []; access = nil; reloadRequired = true }
    }
    @discardableResult
    func reserve(data: Data, input: PrivateFileInput, replacing resource: PrivateFileResource? = nil) async -> PrivateFileVersion? {
        guard !isBusy else { return nil }
        guard canContribute, !reloadRequired, offlineActor() == access?.userID else { issue = .reloadRequired; return nil }
        guard !data.isEmpty, data.count <= kind.maximumBytes, input.validDraft else { issue = .invalidInput; return nil }
        guard proposal == nil || pendingVersion?.status == .ready else { issue = .reconcileRequired; return nil }
        if let resource, resource.teamID != teamID || resource.kind != kind || resource.targetID != targetID || resource.archivedAt != nil {
            issue = .invalidInput; return nil
        }
        proposal = FileProposal(resourceID: resource?.id ?? UUID(), operationID: UUID(), baseID: resource?.publishedVersionID, bytes: data, input: input)
        pendingVersion = nil; uploadNeedsReconciliation = false
        return await retryReservation()
    }
    @discardableResult
    func retryReservation() async -> PrivateFileVersion? {
        guard !isBusy else { return nil }
        guard let proposal, offlineActor() == access?.userID else { issue = .reloadRequired; return nil }
        isBusy = true; issue = nil; confirmation = nil; defer { isBusy = false }
        do {
            let version: PrivateFileVersion = try await rpc(authenticatedClient(), "file_reserve", [
                "p_resource_id": .string(proposal.resourceID.uuidString), "p_kind": .string(kind.rawValue),
                "p_target_id": .string(targetID.uuidString), "p_operation_id": .string(proposal.operationID.uuidString),
                "p_declared_bytes": .integer(Int64(proposal.bytes.count)), "p_title": .string(proposal.input.title), "p_notes": .string(proposal.input.notes),
                "p_base_published_version_id": proposal.baseID.map { .string($0.uuidString) } ?? .null])
            guard valid(version), version.resourceID == proposal.resourceID, version.operationID == proposal.operationID,
                version.declaredBytes == proposal.bytes.count, version.basePublishedVersionID == proposal.baseID else { throw PrivateFileIssue.invalidResponse }
            pendingVersion = version; accept(version)
            confirmation = "Server saved the upload reservation. File validation and storage are still pending."
            return version
        } catch { fail(error); return nil }
    }
    @discardableResult
    func upload() async -> PrivateFileVersion? {
        guard !isBusy else { return nil }
        guard !uploadNeedsReconciliation else { issue = .reconcileRequired; return nil }
        guard let proposal, let version = pendingVersion, version.status == .uploading else { issue = .reloadRequired; return nil }
        return await transferUpload(version, body: proposal.bytes, reconcile: false)
    }
    @discardableResult
    func reconcile(_ version: PrivateFileVersion) async -> PrivateFileVersion? {
        guard !isBusy else { return nil }
        guard valid(version), version.authorUserID == access?.userID, offlineActor() == access?.userID else { issue = .denied; return nil }
        return await transferUpload(version, body: Data(), reconcile: true)
    }
    private func transferUpload(_ version: PrivateFileVersion, body: Data, reconcile: Bool) async -> PrivateFileVersion? {
        isBusy = true; issue = nil; confirmation = nil; defer { isBusy = false }
        do {
            let client = try await authenticatedClient()
            let request = try await gatewayRequest(client, route: "uploads/" + version.operationID.uuidString + (reconcile ? "/reconcile" : ""), method: "POST", body: body)
            uploadNeedsReconciliation = true
            let bytes = try await PrivateFileTransfer.read(request, session: session, maximum: 65_536)
            let reply = try JSONDecoder().decode(PrivateFileVersion.self, from: bytes)
            guard valid(reply), reply.id == version.id, reply.resourceID == version.resourceID, reply.operationID == version.operationID,
                reply.status == .ready, reply.byteCount == version.declaredBytes else { throw PrivateFileIssue.invalidResponse }
            if !reconcile { guard reply.sha256 == clipDigest(body) else { throw PrivateFileIssue.integrity } }
            pendingVersion = reply; accept(reply); uploadNeedsReconciliation = false
            confirmation = "Server confirmed validated, durably stored private bytes. This version still requires submission or authorized publication."
            return reply
        } catch {
            fail(error)
            if issue == .missingUpload || issue == .invalidFile || issue == .validationFailed { proposal = nil; pendingVersion = nil; uploadNeedsReconciliation = false }
            return nil
        }
    }
    @discardableResult
    func save(_ version: PrivateFileVersion, input: PrivateFileInput) async -> PrivateFileVersion? {
        guard input.validDraft else { issue = .invalidInput; return nil }
        return await command(version, name: "file_save", values: ["p_title": .string(input.title), "p_notes": .string(input.notes)])
    }
    @discardableResult
    func transition(_ version: PrivateFileVersion, action: PrivateFileAction, reason: String = "") async -> PrivateFileVersion? {
        guard reason.count <= 500 else { issue = .invalidInput; return nil }
        return await command(version, name: "file_transition", values: ["p_action": .string(action.rawValue), "p_reason": .string(reason)])
    }
    private func command(_ version: PrivateFileVersion, name: String, values: [String: FileValue]) async -> PrivateFileVersion? {
        guard !isBusy else { return nil }
        guard didLoad, !reloadRequired, offlineActor() == access?.userID, valid(version), versions.contains(where: { $0.id == version.id && $0.revision == version.revision }) else { issue = .reloadRequired; return nil }
        isBusy = true; issue = nil; confirmation = nil; defer { isBusy = false }
        do {
            var values = values; values["p_version_id"] = .string(version.id.uuidString); values["p_expected_revision"] = .integer(version.revision)
            let client = try await authenticatedClient()
            let reply: PrivateFileVersion = try await rpc(client, name, values)
            guard valid(reply), reply.id == version.id, reply.resourceID == version.resourceID, reply.operationID == version.operationID,
                reply.revision > version.revision else { throw PrivateFileIssue.invalidResponse }
            accept(reply); confirmation = "Server confirmed the saved file change."
            try await readSnapshot(client)
            return reply
        } catch { fail(error); reloadRequired = true; return nil }
    }
    @discardableResult
    func archive(_ resource: PrivateFileResource) async -> Bool {
        guard !isBusy, didLoad, resource.teamID == teamID, resource.kind == kind, resource.targetID == targetID else { issue = .reloadRequired; return false }
        isBusy = true; issue = nil; confirmation = nil; defer { isBusy = false }
        do {
            let client = try await authenticatedClient()
            _ = try await client.rpc("file_archive", params: ["p_team_id": FileValue.string(teamID.uuidString), "p_resource_id": .string(resource.id.uuidString),
                "p_expected_published_version_id": resource.publishedVersionID.map { .string($0.uuidString) } ?? .null]).retry(enabled: false).execute()
            if let scope = clipScope, let versionID = resource.publishedVersionID { try retention.recordDenial(scope: scope, versionID: versionID) }
            confirmation = "Server archived this resource. Existing bytes and history remain retained."
            try await readSnapshot(client)
            return true
        } catch { fail(error); reloadRequired = true; return false }
    }
    func retainedClips() throws -> [RetainedClip] {
        guard !contentConcealed, let scope = clipScope else { return [] }
        return try retention.items(scope: scope, actorID: offlineActor()).filter { $0.targetID == targetID }
    }
    func offlineURL(_ clip: RetainedClip) throws -> URL? {
        guard !contentConcealed, let scope = clipScope, clip.targetID == targetID else { throw ClipRetentionIssue.locked }
        return try retention.cachedURL(scope: scope, versionID: clip.versionID, actorID: offlineActor(), requireRetained: true)
    }
    /// Recheck current RLS visibility before reusing bytes; reuse consumes no delivery allowance.
    func retrieve(_ version: PrivateFileVersion, keepOnDevice: Bool = false) async -> URL? {
        guard !isBusy else { return nil }; isBusy = true; issue = nil; defer { isBusy = false }
        var denialVersion: UUID?
        do {
            let client = try await authenticatedClient()
            let current: TeamAccess = try await rpc(client, "team_access", [:])
            guard current.teamID == teamID else { throw PrivateFileIssue.invalidResponse }
            denialVersion = version.id
            let visible: [PrivateFileVersion] = try await pages(client, table: "file_resource_versions", id: version.id)
            guard let saved = visible.first, visible.count == 1, valid(saved), saved.id == version.id else { throw PrivateFileIssue.denied }
            guard let count = saved.byteCount, let digest = saved.sha256 else { throw PrivateFileIssue.invalidFile }
            let parents: [PrivateFileResource] = try await pages(client, table: "file_resources", id: saved.resourceID)
            guard parents.count == 1, let parent = parents.first, parent.teamID == teamID, parent.kind == kind, parent.targetID == targetID else { throw PrivateFileIssue.invalidResponse }
            let currentPublished = parent.publishedVersionID == saved.id && parent.archivedAt == nil && saved.status == .published
            if !currentPublished, let scope = clipScope { try retention.recordDenial(scope: scope, versionID: saved.id) }
            guard !keepOnDevice || (kind == .practice && currentPublished) else { throw PrivateFileIssue.invalidInput }
            if kind == .practice, currentPublished, let scope = clipScope, current.userID == scope.actorID {
                try retention.confirmMembership(scope: scope, visibleVersionID: saved.id)
                do {
                    if let cached = try retention.cachedURL(scope: scope, versionID: saved.id, actorID: current.userID, requireRetained: false, expectedCount: count, expectedSHA256: digest) {
                        if keepOnDevice { try retention.keep(scope: scope, versionID: saved.id, actorID: current.userID) }
                        return cached
                    }
                } catch ClipRetentionIssue.integrity {
                    // The requested retrieval may fetch a fresh authorized copy; old bytes stay preserved.
                }
            }
            let operation = UUID()
            let receipt: FileDelivery = try await rpc(client, "file_delivery", ["p_version_id": .string(saved.id.uuidString), "p_operation_id": .string(operation.uuidString)])
            guard receipt.versionID == saved.id, receipt.operationID == operation, receipt.byteCount == count,
                receipt.sha256 == digest, receipt.contentType == saved.contentType else { throw PrivateFileIssue.invalidResponse }
            let request = try await gatewayRequest(client, route: "files/" + saved.id.uuidString + "?operation=" + operation.uuidString, method: "GET")
            let bytes = try await PrivateFileTransfer.read(request, session: session, maximum: count, expectedType: receipt.contentType)
            guard bytes.count == count, clipDigest(bytes) == digest else { throw PrivateFileIssue.integrity }
            if kind == .practice, currentPublished, let scope = clipScope, current.userID == scope.actorID {
                return try retention.store(bytes, scope: scope, versionID: saved.id, targetID: targetID, title: saved.title,
                    expectedCount: count, expectedSHA256: digest, keepOnDevice: keepOnDevice)
            }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PrivateFiles").appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let url = folder.appendingPathComponent(saved.id.uuidString + (kind == .practice ? ".mp4" : ".pdf"))
            try bytes.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600, .protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
            return url
        } catch { fail(error, denialVersion: denialVersion); return nil }
    }
    private func gatewayRequest(_ client: SupabaseClient, route: String, method: String, body: Data? = nil) async throws -> URLRequest {
        guard let configuration = configuration() else { throw PrivateFileIssue.server }
        guard configuration.environment == .localTest else { throw PrivateFileIssue.hostedUnavailable }
        let token = try await accessToken()
        guard let url = URL(string: configuration.url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/functions/v1/teamstats-files/" + route) else { throw PrivateFileIssue.invalidInput }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 90
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization"); request.setValue(configuration.publicKey, forHTTPHeaderField: "apikey")
        if body != nil { request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type") }
        return request
    }
    private func accept(_ version: PrivateFileVersion) {
        versions.removeAll { $0.id == version.id }; versions.append(version)
        if pendingVersion?.id == version.id { pendingVersion = version }
    }
    private func readSnapshot(_ client: SupabaseClient) async throws {
        let current: TeamAccess = try await rpc(client, "team_access", [:])
        guard current.teamID == teamID else { throw PrivateFileIssue.invalidResponse }
        let parents: [PrivateFileResource] = try await pages(client, table: "file_resources")
        let rows: [PrivateFileVersion] = try await pages(client, table: "file_resource_versions")
        guard Set(parents.map(\.id)).count == parents.count,
            parents.allSatisfy({ $0.teamID == teamID && $0.kind == kind && $0.targetID == targetID }),
            Set(rows.map(\.id)).count == rows.count,
            rows.allSatisfy(valid) else { throw PrivateFileIssue.invalidResponse }
        let parentIDs = Set(parents.map(\.id))
        guard rows.allSatisfy({ parentIDs.contains($0.resourceID) }) else { throw PrivateFileIssue.invalidResponse }
        resources = parents; versions = rows; access = current; didLoad = true; reloadRequired = false; contentConcealed = false
        if let scope = clipScope, current.userID == scope.actorID { try retention.confirmMembership(scope: scope) }
    }
    private func valid(_ version: PrivateFileVersion) -> Bool {
        version.teamID == teamID && version.revision > 0 && version.declaredBytes > 0 && version.declaredBytes <= kind.maximumBytes
        && (version.byteCount != nil || [.uploading, .failed].contains(version.status))
        && (version.byteCount == nil || (version.byteCount == version.declaredBytes && version.sha256?.count == 64 && version.contentType == (kind == .practice ? "video/mp4" : "application/pdf")))
    }
    private func pages<T: Decodable>(_ client: SupabaseClient, table: String, id: UUID? = nil) async throws -> [T] {
        var rows: [T] = []
        for page in 0..<50 {
            let parent = table == "file_resources"
            let columns = parent ? "*" : "*,file_resources!file_resource_versions_team_id_resource_id_fkey!inner(kind,play_id,game_id)"
            let query = client.from(table).select(columns).eq("team_id", value: teamID.uuidString)
            _ = query.eq(parent ? "kind" : "file_resources.kind", value: kind.rawValue)
            _ = query.eq((parent ? "" : "file_resources.") + (kind == .practice ? "play_id" : "game_id"), value: targetID.uuidString)
            if let id { _ = query.eq("id", value: id.uuidString) }
            let values: [T] = try await query.order("id").range(from: page * 100, to: (page + 1) * 100 - 1).retry(enabled: false).execute().value
            rows.append(contentsOf: values)
            if values.count < 100 { return rows }
        }
        throw PrivateFileIssue.invalidResponse
    }
    private func rpc<T: Decodable>(_ client: SupabaseClient, _ name: String, _ values: [String: FileValue]) async throws -> T {
        var values = values; values["p_team_id"] = .string(teamID.uuidString)
        return try await client.rpc(name, params: values).retry(enabled: false).execute().value
    }
    private func fail(_ error: Error, denialVersion: UUID? = nil) {
        if let error = error as? PrivateFileIssue { issue = error }
        else if let error = error as? PostgrestError {
            switch error.code { case "42501": issue = .denied; case "40001", "PT409": issue = .conflict; case "P0001": issue = .capacity; default: issue = .server }
        } else if let error = error as? ClipRetentionIssue {
            switch error { case .insufficientSpace: issue = .insufficientSpace; case .integrity: issue = .integrity; case .locked: issue = .denied; case .storage: issue = .storage }
        } else { issue = .server }
        if issue == .denied {
            contentConcealed = true; resources = []; versions = []; access = nil
            if let scope = clipScope { do { try retention.recordDenial(scope: scope, versionID: denialVersion) } catch { issue = .storage } }
        }
    }
}

nonisolated private struct FileDelivery: Decodable {
    let operationID: UUID; let versionID: UUID; let byteCount: Int; let sha256: String; let contentType: String
    enum CodingKeys: String, CodingKey { case operationID = "operation_id", versionID = "version_id", byteCount = "byte_count", sha256, contentType = "content_type" }
}
nonisolated private enum PrivateFileTransfer {
    // Byte iteration must not inherit the UI actor under approachable concurrency.
    @concurrent static func read(_ request: URLRequest, session: URLSession, maximum: Int, expectedType: String? = nil) async throws -> Data {
        let (stream, response) = try await session.bytes(for: request, delegate: FileRedirectBlocker())
        defer { stream.task.cancel() }
        guard let response = response as? HTTPURLResponse else { throw PrivateFileIssue.invalidResponse }
        if !(200..<300).contains(response.statusCode) {
            var body = Data()
            for try await byte in stream { body.append(byte); if body.count >= 8192 { break } }
            let code = (try? JSONSerialization.jsonObject(with: body) as? [String: String])?["error"]
            if [401, 403].contains(response.statusCode) { throw PrivateFileIssue.denied }
            if code == "upload_not_stored_start_new_operation" { throw PrivateFileIssue.missingUpload }
            if ["capacity_unavailable", "private_file_capacity_unknown"].contains(code ?? "") { throw PrivateFileIssue.capacity }
            if ["validation_resource_limit", "validator_receipt_mismatch"].contains(code ?? "") { throw PrivateFileIssue.validationFailed }
            if ["unsupported_type", "encrypted_pdf", "malformed_file", "resource_limit", "unsupported_codec", "duration_limit", "dimension_limit", "size_limit", "active_content", "unreadable_content", "invalid_request", "unreadable", "invalid_pdf", "active_pdf", "invalid_video", "dimensions_limit", "file_validation_failed"].contains(code ?? "") { throw PrivateFileIssue.invalidFile }
            throw PrivateFileIssue.server
        }
        guard maximum > 0, maximum <= 10 * 1024 * 1024, response.expectedContentLength <= maximum,
            expectedType == nil || response.mimeType == expectedType else { throw PrivateFileIssue.integrity }
        var bytes = Data()
        for try await byte in stream {
            try Task.checkCancellation()
            bytes.append(byte)
            guard bytes.count <= maximum else { throw PrivateFileIssue.integrity }
        }
        return bytes
    }
}
nonisolated private final class FileRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
