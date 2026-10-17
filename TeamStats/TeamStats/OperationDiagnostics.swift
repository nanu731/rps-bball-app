import Foundation
import OSLog

nonisolated enum DiagnosticCategory: String, Codable, Sendable {
    case authentication = "authentication_transport"
    case session, sharedLoad, sharedSave, fileTransport, fileOperation
}
nonisolated enum DiagnosticOutcome: String, Codable, Sendable {
    case succeeded, failed, cancelled, unconfirmed
}
nonisolated enum DiagnosticFailure: String, Codable, Sendable {
    case none, denied, unavailable, invalid, storage, conflict, capacity, integrity, cancelled
}
nonisolated struct DiagnosticEvent: Codable, Sendable {
    let category: DiagnosticCategory
    let outcome: DiagnosticOutcome
    let failure: DiagnosticFailure
    let durationMS: Int?
    let attempts: Int
}

/// Content-free evidence only; no disk store, network transmission or user identifier.
nonisolated final class OperationDiagnostics: @unchecked Sendable {
    static let subsystem = "org.teamstats.diagnostics"
    private static let logger = Logger(subsystem: subsystem, category: "operations")
    static let shared = OperationDiagnostics { line in OperationDiagnostics.logger.notice("\(line, privacy: .public)") }
    struct Snapshot: Sendable {
        let events: [DiagnosticEvent]
        let discarded: Int
        let sinkFailures: Int
        let suppressed: Int
    }
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "org.teamstats.diagnostics.output", qos: .utility)
    private let sink: @Sendable (String) throws -> Void
    private let clock: @Sendable () -> TimeInterval
    private var epoch: UInt64 = 0
    private var events: [(TimeInterval, DiagnosticEvent)] = []
    private var discarded = 0, sinkFailures = 0, suppressed = 0, emitted = 0
    private var window: TimeInterval = 0
    private var emitting = false

    init(clock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         sink: @escaping @Sendable (String) throws -> Void) {
        self.clock = clock; self.sink = sink
    }
    func begin(_ category: DiagnosticCategory, attempts: Int = 1) -> DiagnosticSpan {
        lock.withLock { DiagnosticSpan(owner: self, epoch: epoch, category: category, start: clock(), attempts: attempts) }
    }
    func generation() -> UInt64 { lock.withLock { epoch } }
    func note(_ category: DiagnosticCategory, outcome: DiagnosticOutcome, failure: DiagnosticFailure, generation: UInt64? = nil) {
        let expected = generation ?? self.generation()
        record(DiagnosticEvent(category: category, outcome: outcome, failure: failure,
                               durationMS: nil, attempts: 0), epoch: expected)
    }
    /// Clear memory at account boundaries; old spans cannot repopulate it.
    func reset() {
        lock.withLock { epoch &+= 1; events.removeAll(keepingCapacity: true); discarded = 0; sinkFailures = 0; suppressed = 0 }
        // Do not reset the process emission budget or enqueue more work behind a stalled sink.
    }
    func snapshot() -> Snapshot {
        lock.withLock {
            expire(clock())
            return Snapshot(events: events.map(\.1), discarded: discarded, sinkFailures: sinkFailures, suppressed: suppressed)
        }
    }
    private func expire(_ now: TimeInterval) {
        let before = events.count
        events.removeAll { now - $0.0 >= 900 }
        discarded = min(9999, discarded + before - events.count)
    }
    fileprivate func elapsed(since start: TimeInterval) -> TimeInterval { clock() - start }
    fileprivate func record(_ event: DiagnosticEvent, epoch expected: UInt64) {
        let shouldEmit = lock.withLock { () -> Bool in
            guard epoch == expected else { return false }
            let now = clock(); expire(now)
            if events.count == 64 { events.removeFirst(); discarded = min(9999, discarded + 1) }
            events.append((now, event))
            if now - window >= 60 { window = now; emitted = 0 }
            guard !emitting, emitted < 32 else { suppressed = min(9999, suppressed + 1); return false }
            emitting = true; emitted += 1
            return true
        }
        guard shouldEmit else { return }
        // At most one queued/running sink. Slow or failed output never holds up a save.
        queue.async { [self] in
            defer { lock.withLock { emitting = false } }
            guard lock.withLock({ epoch == expected }) else { return }
            do {
                let data = try JSONEncoder().encode(event)
                try sink(String(decoding: data, as: UTF8.self))
            } catch { lock.withLock { if epoch == expected { sinkFailures = min(9999, sinkFailures + 1) } } }
        }
    }
}
nonisolated final class DiagnosticSpan: @unchecked Sendable {
    private let owner: OperationDiagnostics
    private let epoch: UInt64, category: DiagnosticCategory, start: TimeInterval
    private let lock = NSLock()
    private var attempts: Int
    private var finished = false
    fileprivate init(owner: OperationDiagnostics, epoch: UInt64, category: DiagnosticCategory,
                     start: TimeInterval, attempts: Int) {
        self.owner = owner; self.epoch = epoch; self.category = category; self.start = start
        self.attempts = min(3, max(0, attempts))
    }
    func attempt() { lock.withLock { attempts = min(3, attempts + 1) } }
    func finish(_ outcome: DiagnosticOutcome, failure: DiagnosticFailure = .none, timed: Bool = true) {
        let count = lock.withLock { () -> Int? in
            guard !finished else { return nil }; finished = true; return attempts
        }
        guard let count else { return }
        let elapsed = owner.elapsed(since: start)
        let milliseconds = timed && elapsed.isFinite ? Int(min(3_600_000, max(0, elapsed * 1000)) / 10) * 10 : nil
        owner.record(DiagnosticEvent(category: category, outcome: outcome, failure: failure,
                                     durationMS: milliseconds, attempts: count), epoch: epoch)
    }
}
