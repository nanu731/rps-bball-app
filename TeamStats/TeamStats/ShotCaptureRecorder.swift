import Foundation
import Observation

/// Serializes in-app file mutations. It caches neither authority nor capture data.
actor ShotCaptureDisk {
    static let shared = ShotCaptureDisk()
    func preflight(_ document: ShotCaptureDocument) throws {
        _ = try ShotCaptureStorage.encoded(document)
    }
    func create(_ document: ShotCaptureDocument, at url: URL) throws {
        try ShotCaptureStorage.create(document, at: url)
    }
    func openLocal(gameID: UUID, at url: URL, players: [ShotCapturePlayer]) throws -> ShotCaptureDocument {
        let context = ShotCaptureContext(gameID: gameID, teamID: nil, actorID: nil, assignmentRevision: nil)
        if FileManager.default.fileExists(atPath: url.path) || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil {
            return try ShotCaptureStorage.load(from: url, context: context)
        }
        let document = try ShotCaptureDocument.local(gameID: gameID, players: players)
        try ShotCaptureStorage.create(document, at: url)
        return document
    }
    func load(from url: URL, context: ShotCaptureContext) throws -> ShotCaptureDocument {
        try ShotCaptureStorage.load(from: url, context: context)
    }
    func preserveAndReload(_ pending: ShotCaptureDocument, from url: URL, copy: URL) throws -> ShotCaptureDocument {
        guard copy != url else { throw ShotCaptureIssue.invalid }
        if FileManager.default.fileExists(atPath: copy.path) {
            guard try ShotCaptureStorage.load(from: copy, context: pending.context) == pending else { throw ShotCaptureIssue.stale }
        } else { try ShotCaptureStorage.create(pending, at: copy) }
        return try ShotCaptureStorage.load(from: url, context: pending.context)
    }
    func save(_ document: ShotCaptureDocument, to url: URL, expectedRevision: Int) throws {
        try ShotCaptureStorage.save(document, to: url, expectedRevision: expectedRevision)
    }
}

/// Pending feedback precedes disk I/O; a receipt follows only a confirmed atomic save.
@MainActor @Observable
final class ShotCaptureRecorder {
    private var durable: ShotCaptureDocument
    private var pending: ShotCaptureDocument?
    private var invalidated = false
    private(set) var isBusy = false
    private(set) var issue: String?
    private(set) var recoveryURL: URL?
    @ObservationIgnored private let url: URL
    @ObservationIgnored private let currentContext: () -> Bool
    @ObservationIgnored private let save: (ShotCaptureDocument, URL, Int) async throws -> Void

    var isCurrent: Bool { !invalidated && currentContext() }
    var visibleDocument: ShotCaptureDocument? { isCurrent ? (pending ?? durable) : nil }
    var needsSave: Bool { isCurrent && pending != nil }
    var savedRevision: Int? { isCurrent ? durable.revision : nil }
    var canChange: Bool { isCurrent && !isBusy && pending == nil }

    init(document: ShotCaptureDocument, url: URL,
         save: ((ShotCaptureDocument, URL, Int) async throws -> Void)? = nil, isCurrentContext: @escaping () -> Bool = { true }) throws {
        try document.validate()
        durable = document; self.url = url; currentContext = isCurrentContext
        self.save = save ?? { candidate, destination, revision in
            try await ShotCaptureDisk.shared.save(candidate, to: destination, expectedRevision: revision)
        }
    }

    func invalidate() { invalidated = true; issue = nil }

    func change(_ edit: (inout ShotCaptureDocument) throws -> Void) async {
        guard canChange else { return }
        var candidate = durable
        do {
            try edit(&candidate)
            guard candidate != durable else { return }
            try candidate.validateSuccessor(of: durable)
            isBusy = true
            do { try await ShotCaptureDisk.shared.preflight(candidate) }
            catch { isBusy = false; throw error }
            isBusy = false
            guard isCurrent else { return }
            pending = candidate
            await retrySave()
        } catch {
            if isCurrent { issue = (error as? ShotCaptureIssue)?.errorDescription ?? "The entry could not be validated. Your saved capture was not changed." }
        }
    }

    func reopenPreservingPending(at copy: URL) async {
        guard isCurrent, !isBusy, let pending else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let latest = try await ShotCaptureDisk.shared.preserveAndReload(pending, from: url, copy: copy)
            guard isCurrent else { return }
            recoveryURL = copy; durable = latest; self.pending = nil
            issue = nil
        } catch {
            if isCurrent { issue = "Could not preserve and reopen. Your pending change is still shown; keep this screen open and retry." }
        }
    }

    func retrySave() async {
        guard isCurrent, !isBusy, let candidate = pending else { return }
        isBusy = true; issue = nil
        defer { isBusy = false }
        do {
            try Task.checkCancellation()
            try await save(candidate, url, durable.revision)
            try Task.checkCancellation()
            guard isCurrent else { return }
            durable = candidate; pending = nil
        } catch {
            guard isCurrent else { return }
            issue = (error as? ShotCaptureIssue)?.errorDescription ??
                "Save not confirmed. Your pending change is still shown. Retry saving it; do not enter it again."
        }
    }
}
