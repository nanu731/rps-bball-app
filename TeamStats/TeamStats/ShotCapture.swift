import Foundation

nonisolated enum ShotTeam: String, Codable, CaseIterable, Sendable { case our, opponent }
nonisolated enum ShotOutcome: String, Codable, Sendable { case made, missed }
nonisolated enum ShotKind: String, Codable, Sendable { case fieldGoal, freeThrows }
nonisolated enum ShotBasket: String, Codable, CaseIterable, Sendable { case top, bottom }

nonisolated struct ShotLocation: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var isValid: Bool { x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y) }
}

nonisolated struct ShotCapturePlayer: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let number: String
    let temporary: Bool
}

nonisolated struct ShotCaptureContext: Codable, Equatable, Sendable {
    let gameID: UUID
    let teamID: UUID?
    let actorID: UUID?
    let assignmentRevision: Int?
    var isShared: Bool { teamID != nil }
}

nonisolated struct ShotFreeThrowAnswer: Codable, Equatable, Sendable {
    let index: Int
    var outcome: ShotOutcome
}

nonisolated struct ShotCaptureEvent: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var kind: ShotKind
    var team: ShotTeam
    var playerID: String?
    var location: ShotLocation?
    var basket: ShotBasket?
    var value: Int?
    var outcome: ShotOutcome?
    var freeThrowAttempts: Int?
    var answers: [ShotFreeThrowAnswer]
}

nonisolated struct ShotCaptureChange: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let revision: Int
    let recordedAt: Date // Entry provenance, never a game clock or possession order.
    let eventID: UUID
    let before: ShotCaptureEvent?
    let after: ShotCaptureEvent?
    let undoOf: UUID?
}

nonisolated enum ShotCaptureIssue: Error, LocalizedError, Equatable {
    case invalid, corrupt, limit, stale, oneChange, nothingToUndo
    var errorDescription: String? {
        switch self {
        case .invalid: "Check the team, player, shot value, location and whole-number attempts. No invalid entry was saved."
        case .corrupt: "This capture could not be validated. Its saved bytes were not changed."
        case .limit: "This capture exceeds the supported storage or integer range. Nothing was truncated. Keep the existing draft."
        case .stale: "The saved capture changed. Reopen it before editing; your current input has not replaced it."
        case .oneChange: "Make one capture change at a time. Your saved capture was not changed."
        case .nothingToUndo: "There is no earlier capture change to undo."
        }
    }
}

nonisolated struct ShotCaptureTotals: Equatable, Sendable {
    var madeTwos = 0, missedTwos = 0, madeThrees = 0, missedThrees = 0
    var madeFreeThrows = 0, missedFreeThrows = 0, pending = 0, points = 0
}

nonisolated struct ShotCaptureDocument: Codable, Equatable, Identifiable, Sendable {
    static let maximumChanges = 20_000
    static let maximumAttempts = 2_147_483_647 // Interoperable integer bound, not a basketball rule.
    let schemaVersion: Int
    let id: UUID
    let context: ShotCaptureContext
    let players: [ShotCapturePlayer]
    private(set) var journal: [ShotCaptureChange]
    var revision: Int { journal.count }

    static func local(gameID: UUID, players: [ShotCapturePlayer]) throws -> Self {
        let document = Self(schemaVersion: 1, id: UUID(), context: ShotCaptureContext(
            gameID: gameID, teamID: nil, actorID: nil, assignmentRevision: nil), players: players, journal: [])
        try document.validate()
        return document
    }

    func validate() throws { _ = try projected() }
    func validateSuccessor(of previous: Self) throws {
        try validate()
        guard id == previous.id, context == previous.context, players == previous.players,
              schemaVersion == previous.schemaVersion else { throw ShotCaptureIssue.stale }
        guard previous.revision < Self.maximumChanges, revision == previous.revision + 1 else { throw ShotCaptureIssue.oneChange }
        guard Array(journal.dropLast()) == previous.journal else { throw ShotCaptureIssue.stale }
    }
    func events() throws -> [ShotCaptureEvent] { try projected().events }
    var canUndo: Bool { (try? projected().undoable.isEmpty) == false }

    private func projected() throws -> (events: [ShotCaptureEvent], undoable: [ShotCaptureChange]) {
        let zero = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        guard schemaVersion == 1, id != zero, context.gameID != zero,
              journal.count <= Self.maximumChanges, players.count <= 1_000,
              Set(players.map(\.id)).count == players.count,
              players.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 100 && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 100 &&
                  !$0.number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.number.count <= 10 }) else { throw ShotCaptureIssue.corrupt }
        if context.isShared {
            guard context.teamID != zero, let actor = context.actorID, actor != zero,
                  let assignment = context.assignmentRevision, assignment > 0,
                  players.allSatisfy({ !$0.temporary && UUID(uuidString: $0.id) != nil }) else { throw ShotCaptureIssue.corrupt }
        } else if context.actorID != nil || context.assignmentRevision != nil { throw ShotCaptureIssue.corrupt }
        var current: [UUID: ShotCaptureEvent] = [:]
        var order: [UUID] = [], ever = Set<UUID>(), changes = Set<UUID>()
        var undoable: [ShotCaptureChange] = []
        for (index, change) in journal.enumerated() {
            guard change.revision == index + 1, change.id != zero, change.eventID != zero,
                  changes.insert(change.id).inserted, change.recordedAt.timeIntervalSince1970.isFinite,
                  (0...253_402_300_799).contains(change.recordedAt.timeIntervalSince1970),
                  change.before == current[change.eventID], change.before != change.after else { throw ShotCaptureIssue.corrupt }
            for event in [change.before, change.after].compactMap({ $0 }) {
                guard event.id == change.eventID else { throw ShotCaptureIssue.corrupt }
                try validate(event)
            }
            if let undone = change.undoOf {
                guard let last = undoable.last, last.id == undone, last.eventID == change.eventID,
                      change.before == last.after, change.after == last.before else { throw ShotCaptureIssue.corrupt }
                undoable.removeLast()
            } else {
                guard let after = change.after, change.before == nil || after.kind == change.before?.kind else { throw ShotCaptureIssue.corrupt }
                if change.before == nil {
                    guard ever.insert(after.id).inserted else { throw ShotCaptureIssue.corrupt }
                    order.append(after.id)
                }
                undoable.append(change)
            }
            current[change.eventID] = change.after
        }
        return (order.compactMap { current[$0] }, undoable)
    }

    private func validate(_ event: ShotCaptureEvent) throws {
        guard (event.team == .opponent && event.playerID == nil) ||
                (event.team == .our && players.contains(where: { $0.id == event.playerID })) else { throw ShotCaptureIssue.invalid }
        switch event.kind {
        case .fieldGoal:
            guard let location = event.location, location.isValid, event.basket != nil,
                  event.value == nil || event.value == 2 || event.value == 3,
                  event.outcome == nil || event.value != nil,
                  event.freeThrowAttempts == nil, event.answers.isEmpty else { throw ShotCaptureIssue.invalid }
        case .freeThrows:
            guard event.location == nil, event.basket == nil, event.value == nil, event.outcome == nil,
                  let count = event.freeThrowAttempts, (1...Self.maximumAttempts).contains(count),
                  event.answers.count <= Self.maximumChanges,
                  Set(event.answers.map(\.index)).count == event.answers.count,
                  event.answers.allSatisfy({ (1...count).contains($0.index) }) else { throw ShotCaptureIssue.invalid }
        }
    }

    private mutating func append(_ event: ShotCaptureEvent) throws {
        let before = try events().first { $0.id == event.id }
        if before == event { return } // Repeated result taps are the same observation, not another change.
        guard revision < Self.maximumChanges else { throw ShotCaptureIssue.limit }
        var candidate = self
        candidate.journal.append(ShotCaptureChange(id: UUID(), revision: revision + 1, recordedAt: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)),
            eventID: event.id, before: before, after: event, undoOf: nil))
        try candidate.validate()
        self = candidate
    }

    @discardableResult mutating func startFieldGoal(team: ShotTeam, playerID: String?, location: ShotLocation, basket: ShotBasket) throws -> UUID {
        let event = ShotCaptureEvent(id: UUID(), kind: .fieldGoal, team: team, playerID: playerID,
            location: location, basket: basket, value: nil, outcome: nil, freeThrowAttempts: nil, answers: [])
        try append(event)
        return event.id
    }

    mutating func correct(_ event: ShotCaptureEvent) throws {
        guard try events().contains(where: { $0.id == event.id }) else { throw ShotCaptureIssue.invalid }
        try append(event)
    }

    @discardableResult mutating func startFreeThrows(team: ShotTeam, playerID: String?, attempts: Int) throws -> UUID {
        let event = ShotCaptureEvent(id: UUID(), kind: .freeThrows, team: team, playerID: playerID,
            location: nil, basket: nil, value: nil, outcome: nil, freeThrowAttempts: attempts, answers: [])
        try append(event)
        return event.id
    }

    mutating func answerFreeThrow(seriesID: UUID, index: Int, outcome: ShotOutcome?) throws {
        guard var event = try events().first(where: { $0.id == seriesID }), event.kind == .freeThrows,
              let count = event.freeThrowAttempts, (1...count).contains(index) else { throw ShotCaptureIssue.invalid }
        event.answers.removeAll { $0.index == index }
        if let outcome { event.answers.append(ShotFreeThrowAnswer(index: index, outcome: outcome)) }
        event.answers.sort { $0.index < $1.index }
        try append(event)
    }

    mutating func undo() throws {
        guard let last = try projected().undoable.last else { throw ShotCaptureIssue.nothingToUndo }
        guard revision < Self.maximumChanges else { throw ShotCaptureIssue.limit }
        var candidate = self
        candidate.journal.append(ShotCaptureChange(id: UUID(), revision: revision + 1, recordedAt: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)),
            eventID: last.eventID, before: last.after, after: last.before, undoOf: last.id))
        try candidate.validate()
        self = candidate
    }

    func totals(team: ShotTeam, playerID: String? = nil) throws -> ShotCaptureTotals {
        var result = ShotCaptureTotals()
        func add(_ value: inout Int, _ increment: Int) throws {
            let sum = value.addingReportingOverflow(increment)
            guard !sum.overflow else { throw ShotCaptureIssue.limit }; value = sum.partialValue
        }
        for event in try events() where event.team == team && (playerID == nil || event.playerID == playerID) {
            if event.kind == .freeThrows {
                try add(&result.pending, event.freeThrowAttempts! - event.answers.count)
                for answer in event.answers {
                    if answer.outcome == .made { try add(&result.madeFreeThrows, 1); try add(&result.points, 1) }
                    else { try add(&result.missedFreeThrows, 1) }
                }
            } else if let outcome = event.outcome, let value = event.value {
                if value == 2 {
                    if outcome == .made { try add(&result.madeTwos, 1) } else { try add(&result.missedTwos, 1) }
                } else {
                    if outcome == .made { try add(&result.madeThrees, 1) } else { try add(&result.missedThrees, 1) }
                }
                if outcome == .made { try add(&result.points, value) }
            } else { try add(&result.pending, 1) }
        }
        return result
    }
}

nonisolated enum ShotCaptureStorage {
    static let maximumBytes = 10 * 1_024 * 1_024
    static func load(from url: URL, context: ShotCaptureContext) throws -> ShotCaptureDocument {
        guard url.isFileURL, (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw ShotCaptureIssue.corrupt }
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        guard let size, size.int64Value <= maximumBytes else { throw ShotCaptureIssue.limit }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw ShotCaptureIssue.limit }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(ShotCaptureDocument.self, from: data)
        guard document.context == context else { throw ShotCaptureIssue.corrupt }
        try document.validate()
        return document
    }
    static func create(_ document: ShotCaptureDocument, at url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path),
              (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) == nil else { throw ShotCaptureIssue.stale }
        try write(document, to: url)
    }
    static func save(_ document: ShotCaptureDocument, to url: URL, expectedRevision: Int) throws {
        let current = try load(from: url, context: document.context)
        if current == document { return } // Same immutable change after an uncertain local receipt.
        guard current.revision == expectedRevision, expectedRevision >= 0 else { throw ShotCaptureIssue.stale }
        try document.validateSuccessor(of: current)
        try write(document, to: url)
    }
    private static func write(_ document: ShotCaptureDocument, to url: URL) throws {
        try document.validate()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= maximumBytes else { throw ShotCaptureIssue.limit }
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}

/// Full-court observation coordinates; neither regulation distance nor shot-value inference.
nonisolated struct ShotCourtTransform {
    let flipped: Bool
    func display(_ point: ShotLocation) -> ShotLocation {
        flipped ? ShotLocation(x: 1 - point.x, y: 1 - point.y) : point
    }
    func capture(x: Double, y: Double, width: Double, height: Double) throws -> ShotLocation {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { throw ShotCaptureIssue.invalid }
        let point = ShotLocation(x: x / width, y: y / height)
        guard point.isValid else { throw ShotCaptureIssue.invalid }
        return display(point) // A180-degree display flip is its own inverse.
    }
    static func attackRelative(_ point: ShotLocation, basket: ShotBasket) -> ShotLocation {
        ShotCourtTransform(flipped: basket == .bottom).display(point)
    }
}
