import Foundation
import Observation

/// Serializes in-app file mutations. It caches neither authority nor capture data.
actor ShotCaptureDisk {
    static let shared = ShotCaptureDisk()
    func create(_ document: ShotCaptureDocument, at url: URL) throws {
        try ShotCaptureStorage.create(document, at: url)
    }
    func load(from url: URL, context: ShotCaptureContext) throws -> ShotCaptureDocument {
        try ShotCaptureStorage.load(from: url, context: context)
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
            pending = candidate
            await retrySave()
        } catch {
            if isCurrent { issue = (error as? ShotCaptureIssue)?.errorDescription ?? "The entry could not be validated. Your saved capture was not changed." }
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
