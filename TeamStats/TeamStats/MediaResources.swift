import Foundation
import Observation
import Supabase

enum MediaResourceKind: String, Codable, Sendable {
    case practice, film
    var label: String { self == .practice ? "Practice video links" : "Game Film — Hudl" }
    var inspection: TeamCapability { self == .practice ? .practiceReview : .filmReview }
    var publication: TeamCapability { self == .practice ? .practicePublish : .filmPublish }
}
enum MediaResourceStatus: String, Codable, Sendable {
    case draft, submitted, rejected, published, superseded
    var label: String {
        switch self {
        case .draft: "Private draft"
        case .submitted: "Pending owner review"
        case .rejected: "Rejected — frozen revision"
        case .published: "Published link — provider access unverified"
        case .superseded: "Saved earlier proposal — read-only"
        }
    }
}
struct MediaResource: Decodable, Identifiable, Sendable {
    let id: UUID
    let teamID: UUID
    let kind: MediaResourceKind
    let playID: UUID?
    let gameID: UUID?
    let publishedVersionID: UUID?
    var targetID: UUID? { kind == .practice ? playID : gameID }
    enum CodingKeys: String, CodingKey {
        case id, kind
        case teamID = "team_id", playID = "play_id", gameID = "game_id", publishedVersionID = "published_version_id"
    }
}
struct MediaResourceVersion: Decodable, Identifiable, Sendable {
    let id: UUID
    let teamID: UUID
    let resourceID: UUID
    let authorUserID: UUID
    let revision: Int64
    let status: MediaResourceStatus
    let title: String
    let linkURL: String
    let notes: String
    let basePublishedVersionID: UUID?
    let recoverySourceVersionID: UUID?
    let reviewReason: String
    enum CodingKeys: String, CodingKey {
        case id, revision, status, title, notes
        case teamID = "team_id", resourceID = "resource_id", authorUserID = "author_user_id"
        case linkURL = "link_url", basePublishedVersionID = "base_published_version_id", recoverySourceVersionID = "recovery_source_version_id", reviewReason = "review_reason"
    }
    var externalURL: URL? { MediaLinkInput.validURL(linkURL) }
}
/// User-authored links are never fetched, embedded or treated as proof of video rights.
struct MediaLinkInput: Equatable, Sendable {
    var title = ""
    var linkURL = ""
    var notes = ""
    init() {}
    init(_ version: MediaResourceVersion) { title = version.title; linkURL = version.linkURL; notes = version.notes }
    var validDraft: Bool {
        title.count <= 120 && notes.count <= 1000 &&
        !title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) &&
        !notes.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\r" && $0 != "\t" }) &&
        (linkURL.isEmpty || Self.validURL(linkURL) != nil)
    }
    var readyToSubmit: Bool { validDraft && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Self.validURL(linkURL) != nil }
    func validDraft(for kind: MediaResourceKind) -> Bool {
        validDraft && (kind != .film || linkURL.isEmpty || Self.hudlURL(linkURL) != nil)
    }
    func readyToSubmit(for kind: MediaResourceKind) -> Bool {
        readyToSubmit && validDraft(for: kind)
    }
    /// Deliberately narrow supported hosts; no inference from suffixes or redirects.
    static func hudlURL(_ text: String) -> URL? {
        guard let url = validURL(text) else { return nil }
        let authority = text.dropFirst(8).prefix { $0 != "/" && $0 != "?" }.lowercased()
        guard ["hudl.com", "www.hudl.com", "hudl.com:443", "www.hudl.com:443"].contains(authority) else { return nil }
        return url
    }
    static func validURL(_ text: String) -> URL? {
        guard text.count <= 2048, text.hasPrefix("https://"),
              text.unicodeScalars.allSatisfy({ $0.value >= 33 && $0.value <= 126 }),
              !text.contains("@"), !text.contains("\\"), !text.contains("#"),
              let components = URLComponents(string: text), components.scheme == "https",
              components.user == nil, components.password == nil, components.fragment == nil,
              let host = components.host, !host.isEmpty,
              host.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-").contains($0) }),
              host.first?.isLetter == true || host.first?.isNumber == true,
              components.port == nil || components.port == 443 else { return nil }
        let bytes = Array(text.utf8)
        for index in bytes.indices where bytes[index] == 37 {
            guard index + 2 < bytes.count, [bytes[index + 1], bytes[index + 2]].allSatisfy({
                (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
            }) else { return nil }
        }
        let denied: Set<String> = ["token", "access_token", "refresh_token", "id_token", "auth", "authorization", "key", "api_key", "apikey", "secret", "password", "credential", "signature", "sig", "code", "jwt", "x-amz-signature", "x-amz-credential"]
        let query = components.percentEncodedQuery ?? ""
        for item in query.split(separator: "&") {
            let name = item.split(separator: "=", maxSplits: 1).first.map(String.init) ?? ""
            guard !name.contains("%"), !denied.contains(name.lowercased()) else { return nil }
        }
        return components.url
    }
}
private struct MediaDraftResume: Decodable { let previous: MediaResourceVersion; let draft: MediaResourceVersion }

enum MediaResourceIssue: Error, Equatable {
    case invalidInput, invalidResponse, denied, conflict, server, reloadRequired, tooManyRecords
    var message: String {
        switch self {
        case .invalidInput: "Check the title, notes and HTTPS link. Credentials and link fragments are not accepted."
        case .invalidResponse: "The server returned an unexpected media record. Reload before continuing."
        case .denied: "Current account access does not allow this media action. Reload to check permissions."
        case .conflict: "The media revision changed. Reload and compare before saving again."
        case .server: "Media could not be loaded or confirmed. Retry loading before another save."
        case .reloadRequired: "Reload saved media before another change. Unsaved text stays in this editor."
        case .tooManyRecords: "Media exceeds the current read-page limit. No incomplete list is shown."
        }
    }
}
@MainActor @Observable
final class MediaResources {
    let teamID: UUID
    let kind: MediaResourceKind
    let targetID: UUID
    private(set) var resources: [MediaResource] = []
    private(set) var versions: [MediaResourceVersion] = []
    private(set) var access: TeamAccess?
    private(set) var didLoad = false
    private(set) var isBusy = false
    private(set) var reloadRequired = false
    private(set) var issue: MediaResourceIssue?
    private(set) var confirmation: String?
    private(set) var contentConcealed = false
    @ObservationIgnored private let authenticatedClient: () async throws -> SupabaseClient
    init(teamID: UUID, kind: MediaResourceKind, targetID: UUID, account: BackendAccount) {
        self.teamID = teamID; self.kind = kind; self.targetID = targetID
        authenticatedClient = { try await account.authenticatedClient() }
    }
    init(teamID: UUID, kind: MediaResourceKind, targetID: UUID, authenticatedClient: @escaping () async throws -> SupabaseClient) {
        self.teamID = teamID; self.kind = kind; self.targetID = targetID; self.authenticatedClient = authenticatedClient
    }
    var canContribute: Bool { didLoad && (kind == .practice || access?.can(.filmUpload) == true) }
    var canPublishOwn: Bool { canContribute && access?.can(kind.publication) == true }
    var published: [MediaResourceVersion] {
        resources.compactMap { resource in versions.first { $0.id == resource.publishedVersionID && $0.status == .published } }
    }
    var ownDrafts: [MediaResourceVersion] { versions.filter { $0.authorUserID == access?.userID && $0.status == .draft } }
    var unpublished: [MediaResourceVersion] { versions.filter { $0.status != .draft && $0.status != .published } }
    func load() async {
        guard !isBusy else { return }
        isBusy = true; defer { isBusy = false }
        issue = nil; confirmation = nil; didLoad = false
        do {
            let client = try await authenticatedClient()
            let current: TeamAccess = try await rpc(client, "team_access", [:])
            guard current.teamID == teamID else { throw MediaResourceIssue.invalidResponse }
            let parents: [MediaResource] = try await pages(client, "media_resources", filterTarget: true)
            guard Set(parents.map(\.id)).count == parents.count,
                  parents.allSatisfy({ $0.teamID == teamID && $0.kind == kind && $0.targetID == targetID && (($0.playID == nil) != ($0.gameID == nil)) }) else { throw MediaResourceIssue.invalidResponse }
            let all: [MediaResourceVersion] = parents.isEmpty ? [] : try await pages(client, "media_resource_versions", filterTarget: false)
            let ids = Set(parents.map(\.id))
            let rows = all.filter { ids.contains($0.resourceID) }
            guard Set(rows.map(\.id)).count == rows.count, rows.allSatisfy(validResponse),
                  parents.allSatisfy({ parent in parent.publishedVersionID == nil || rows.contains(where: { $0.id == parent.publishedVersionID && $0.status == .published }) }) else { throw MediaResourceIssue.invalidResponse }
            resources = parents; versions = rows; access = current; didLoad = true; reloadRequired = false
            contentConcealed = false
        } catch { recordFailure(error); resources = []; versions = []; access = nil; reloadRequired = true }
    }
    /// Identifies only the exact server-created successor; attaching editor text is a separate user action.
    func recoveredDraft(after previous: MediaResourceVersion, expectedID: UUID? = nil, expectedRevision: Int64? = nil) -> MediaResourceVersion? {
        guard didLoad, !reloadRequired, !isBusy, canContribute,
              previous.status == .superseded, previous.authorUserID == access?.userID,
              versions.contains(where: { $0.id == previous.id && $0.revision == previous.revision && $0.status == .superseded }),
              let current = resources.first(where: { $0.id == previous.resourceID })?.publishedVersionID else { return nil }
        var sourceID = previous.id
        var visited: Set<UUID> = [sourceID]
        for _ in 0..<versions.count {
            let matches = versions.filter { $0.recoverySourceVersionID == sourceID }
            guard matches.count == 1, let next = matches.first,
                  visited.insert(next.id).inserted,
                  next.teamID == teamID, next.resourceID == previous.resourceID,
                  next.authorUserID == previous.authorUserID else { return nil }
            if next.status == .draft {
                guard next.basePublishedVersionID == current,
                      expectedID == nil || expectedID == next.id,
                      expectedRevision == nil || expectedRevision == next.revision else { return nil }
                return next
            }
            guard next.status == .superseded else { return nil }
            sourceID = next.id
        }
        return nil
    }
    func hasNewerPublishedLink(_ version: MediaResourceVersion) -> Bool {
        guard version.status == .draft,
              let parent = resources.first(where: { $0.id == version.resourceID }),
              let current = parent.publishedVersionID else { return false }
        return version.basePublishedVersionID != current
    }
    /// Explicitly preserves the last saved proposal. Editors retain unsaved text separately.
    @discardableResult
    func resumeDraft(_ version: MediaResourceVersion) async -> MediaResourceVersion? {
        guard !isBusy else { return nil }
        confirmation = nil
        guard didLoad && !reloadRequired else { issue = .reloadRequired; return nil }
        guard canContribute, version.authorUserID == access?.userID, version.status == .draft else { issue = .denied; return nil }
        guard version.revision < Int64.max,
              versions.contains(where: { $0.id == version.id && $0.revision == version.revision }),
              hasNewerPublishedLink(version),
              let current = resources.first(where: { $0.id == version.resourceID })?.publishedVersionID else { issue = .reloadRequired; return nil }
        isBusy = true; defer { isBusy = false }; issue = nil
        do {
            let reply: MediaDraftResume = try await rpc(authenticatedClient(), "media_resume_draft", [
                "p_version_id": .string(version.id.uuidString), "p_expected_revision": .integer(Int(version.revision)),
                "p_expected_published_version_id": .string(current.uuidString)])
            let old = reply.previous; let fresh = reply.draft
            guard validResponse(old), validResponse(fresh), old.id == version.id, old.status == .superseded,
                  old.revision == version.revision + 1, old.resourceID == version.resourceID,
                  old.authorUserID == version.authorUserID, old.basePublishedVersionID == version.basePublishedVersionID, MediaLinkInput(old) == MediaLinkInput(version),
                  fresh.id != old.id, fresh.status == .draft, fresh.revision == 1,
                  fresh.resourceID == old.resourceID, fresh.authorUserID == old.authorUserID,
                  fresh.basePublishedVersionID == current, fresh.recoverySourceVersionID == old.id, MediaLinkInput(fresh) == MediaLinkInput(old) else { throw MediaResourceIssue.invalidResponse }
            versions.removeAll { $0.id == old.id || $0.id == fresh.id }; versions.append(contentsOf: [old, fresh])
            confirmation = "Server preserved the saved earlier proposal and created a current draft. Typed changes remain unsaved."
            return fresh
        } catch { recordFailure(error); reloadRequired = true; return nil }
    }
    @discardableResult
    func openDraft(resourceID: UUID, source: MediaResourceVersion? = nil) async -> MediaResourceVersion? {
        guard canContribute else { issue = .denied; return nil }
        return await command("media_open_draft", resourceID: resourceID, expectedStatus: .draft, values: [
            "p_resource_id": .string(resourceID.uuidString), "p_kind": .string(kind.rawValue),
            "p_target_id": .string(targetID.uuidString), "p_source_version_id": source.map { .string($0.id.uuidString) } ?? .null])
    }
    @discardableResult
    func save(_ version: MediaResourceVersion, input: MediaLinkInput) async -> MediaResourceVersion? {
        guard input.validDraft(for: kind) else { issue = .invalidInput; confirmation = nil; return nil }
        guard version.status == .draft, version.authorUserID == access?.userID, canContribute, version.revision < Int64.max else { issue = .denied; return nil }
        return await command("media_save_draft", resourceID: version.resourceID, expectedStatus: .draft, version: version, values: [
            "p_title": .string(input.title), "p_link_url": .string(input.linkURL), "p_notes": .string(input.notes)])
    }
    @discardableResult
    func transition(_ version: MediaResourceVersion, action: String, reason: String = "") async -> MediaResourceVersion? {
        let own = version.authorUserID == access?.userID
        guard reason.count <= 500, ["submit", "publish", "approve", "reject"].contains(action) else { issue = .invalidInput; return nil }
        guard (action == "submit" && own && canContribute && version.status == .draft) ||
              (action == "publish" && own && canPublishOwn && version.status == .draft) ||
              (["approve", "reject"].contains(action) && access?.isOwner == true && version.status == .submitted) else { issue = .denied; return nil }
        guard action == "reject" || MediaLinkInput(version).readyToSubmit(for: kind) else { issue = .invalidInput; return nil }
        let expected: MediaResourceStatus = action == "submit" ? .submitted : action == "reject" ? .rejected : .published
        return await command("media_transition", resourceID: version.resourceID, expectedStatus: expected, version: version, values: ["p_action": .string(action), "p_reason": .string(reason)])
    }
    private func command(_ name: String, resourceID: UUID, expectedStatus: MediaResourceStatus,
                         version: MediaResourceVersion? = nil, values: [String: AnyJSON]) async -> MediaResourceVersion? {
        guard !isBusy else { return nil }
        confirmation = nil
        guard didLoad && !reloadRequired else { issue = .reloadRequired; return nil }
        if let version, version.revision == Int64.max || !versions.contains(where: { $0.id == version.id && $0.revision == version.revision }) {
            issue = .reloadRequired; return nil
        }
        isBusy = true; defer { isBusy = false }; issue = nil
        var params = values
        if let version {
            params["p_version_id"] = .string(version.id.uuidString); params["p_expected_revision"] = .integer(Int(version.revision))
        }
        do {
            let result: MediaResourceVersion = try await rpc(authenticatedClient(), name, params)
            guard validResponse(result), result.resourceID == resourceID, result.status == expectedStatus,
                  (version == nil || (result.id == version?.id && result.revision == version!.revision + 1)),
                  (name == "media_transition" && ["approve", "reject"].contains(values["p_action"]?.stringValue ?? "") || result.authorUserID == access?.userID) else { throw MediaResourceIssue.invalidResponse }
            versions.removeAll { $0.id == result.id }; versions.append(result)
            if !resources.contains(where: { $0.id == resourceID }) {
                let object: [String: AnyJSON] = ["id": .string(resourceID.uuidString), "team_id": .string(teamID.uuidString), "kind": .string(kind.rawValue),
                    "play_id": kind == .practice ? .string(targetID.uuidString) : .null,
                    "game_id": kind == .film ? .string(targetID.uuidString) : .null, "published_version_id": .null]
                resources.append(try JSONDecoder().decode(MediaResource.self, from: JSONEncoder().encode(object)))
            }
            if result.status == .published, let index = resources.firstIndex(where: { $0.id == resourceID }) {
                let old = resources[index]
                resources[index] = MediaResource(id: old.id, teamID: old.teamID, kind: old.kind, playID: old.playID, gameID: old.gameID, publishedVersionID: result.id)
            }
            confirmation = "Server confirmed \(result.status == .draft ? "draft save" : result.status.label.lowercased())."
            return result
        } catch { recordFailure(error); reloadRequired = true; return nil }
    }
    private func recordFailure(_ error: Error) {
        issue = Self.map(error)
        if issue == .denied {
            contentConcealed = true; resources = []; versions = []; access = nil
            didLoad = false; reloadRequired = true
        }
    }
    private func validResponse(_ row: MediaResourceVersion) -> Bool {
        row.teamID == teamID && row.revision > 0 && row.reviewReason.count <= 500 && MediaLinkInput(row).validDraft &&
        (row.status == .draft || row.status == .rejected || row.status == .superseded || MediaLinkInput(row).readyToSubmit)
    }
    private func pages<T: Decodable>(_ client: SupabaseClient, _ table: String, filterTarget: Bool) async throws -> [T] {
        var rows: [T] = []
        for page in 0..<50 {
            // Explicit FK avoids ambiguity with the parent's reverse published-version pointer.
            let selection = filterTarget ? "*" : "*,media_resources!media_resource_versions_team_id_resource_id_fkey!inner(kind,play_id,game_id)"
            let query = client.from(table).select(selection).eq("team_id", value: teamID.uuidString)
            if filterTarget {
                _ = query.eq("kind", value: kind.rawValue).eq(kind == .practice ? "play_id" : "game_id", value: targetID.uuidString)
            } else {
                _ = query.eq("media_resources.kind", value: kind.rawValue)
                    .eq(kind == .practice ? "media_resources.play_id" : "media_resources.game_id", value: targetID.uuidString)
            }
            let values: [T] = try await query.order("created_at").order("id").range(from: page * 100, to: page * 100 + 99).execute().value
            rows.append(contentsOf: values)
            if values.count < 100 { return rows }
        }
        throw MediaResourceIssue.tooManyRecords
    }
    private func rpc<T: Decodable>(_ client: SupabaseClient, _ name: String, _ values: [String: AnyJSON]) async throws -> T {
        var params = values; params["p_team_id"] = .string(teamID.uuidString)
        return try await client.rpc(name, params: params).retry(enabled: false).execute().value
    }
    private static func map(_ error: Error) -> MediaResourceIssue {
        if let error = error as? MediaResourceIssue { return error }
        if let error = error as? PostgrestError {
            switch error.code {
            case "42501": return .denied
            case "40001": return .conflict
            case "22023", "23514", "23503": return .invalidInput
            default: return .server
            }
        }
        return error is DecodingError ? .invalidResponse : .server
    }
}
