import Foundation

nonisolated enum ShotMetric: String, CaseIterable, Identifiable, Sendable {
    case twoMakes, twoMisses, twoAttempts, threeMakes, threeMisses, threeAttempts, freeThrowMakes, freeThrowMisses, freeThrowAttempts
    var id: String { rawValue }
    var label: String {
        switch self {
        case .twoMakes: "2PT makes"
        case .twoMisses: "2PT misses"
        case .twoAttempts: "2PT attempts"
        case .threeMakes: "3PT makes"
        case .threeMisses: "3PT misses"
        case .threeAttempts: "3PT attempts"
        case .freeThrowMakes: "FT makes"
        case .freeThrowMisses: "FT misses"
        case .freeThrowAttempts: "FT attempts"
        }
    }
}
nonisolated enum ShotComparison: Equatable, Sendable {
    case unavailable, incomplete, match, disagree, lowerBoundDisagrees
    var label: String {
        switch self {
        case .unavailable: "Unavailable — official input missing or invalid"
        case .incomplete: "Check incomplete — captured inputs still pending"
        case .match: "Values agree · agreement does not establish coverage"
        case .disagree: "Values disagree"
        case .lowerBoundDisagrees: "Disagree — recorded lower bound already exceeds official value"
        }
    }
}
nonisolated struct ShotObservedCount: Equatable, Sendable { let value: Int; let pending: Int }
nonisolated struct ShotOfficialCount: Equatable, Sendable {
    let value: Int?
    let missing: Int
    let unavailable: Bool
    static func sum(_ values: [Int?]) -> Self {
        guard !values.isEmpty else { return Self(value: nil, missing: 0, unavailable: true) }
        var total = 0, missing = 0
        for value in values {
            guard let value else { missing += 1; continue }
            guard value >= 0 else { return Self(value: nil, missing: missing, unavailable: true) }
            let sum = total.addingReportingOverflow(value)
            guard !sum.overflow else { return Self(value: nil, missing: missing, unavailable: true) }
            total = sum.partialValue
        }
        return Self(value: missing == 0 ? total : nil, missing: missing, unavailable: false)
    }
}
nonisolated struct ShotBand: Identifiable, Sendable {
    let id: String
    let label: String
    let made: Int
    let missed: Int
    let pending: Int
    let points: Int
    var answered: Int { made + missed }
    var conversion: Double? { answered == 0 ? nil : Double(made) / Double(answered) }
}

/// Observations only. It neither fills omissions nor writes official statistics.
nonisolated struct ShotAnalysis: Sendable {
    let events: [ShotCaptureEvent]
    let fieldGoals: [ShotCaptureEvent]
    let points: Int
    let pending: Int
    let bands: [ShotBand]
    var coverageEstablished: Bool { false } // Raw observations never establish server-confirmed coverage authority.
    init(document: ShotCaptureDocument, team: ShotTeam, playerID: String?) throws {
        try document.validate()
        events = try document.events().filter { $0.team == team && (playerID == nil || $0.playerID == playerID) }
        let goals = events.filter { $0.kind == .fieldGoal }; fieldGoals = goals
        let totals = try document.totals(team: team, playerID: playerID)
        points = totals.points; pending = totals.pending
        bands = [("left", "Left band"), ("center", "Center band"), ("right", "Right band")].enumerated().map { index, item in
            let shots = goals.filter { event in
                guard let point = event.location, let basket = event.basket else { return false }
                let x = ShotCourtTransform.attackRelative(point, basket: basket).x
                return (x < 1.0 / 3 ? 0 : x < 2.0 / 3 ? 1 : 2) == index
            }
            return ShotBand(id: item.0, label: item.1, made: shots.filter { $0.outcome == .made }.count,
                missed: shots.filter { $0.outcome == .missed }.count, pending: shots.filter { $0.outcome == nil }.count,
                points: shots.reduce(0) { $0 + ($1.outcome == .made ? $1.value ?? 0 : 0) })
        }
    }
    func count(_ metric: ShotMetric) -> ShotObservedCount {
        switch metric {
        case .twoMakes, .threeMakes, .twoMisses, .threeMisses:
            let value = metric == .twoMakes || metric == .twoMisses ? 2 : 3
            let outcome: ShotOutcome = metric == .twoMisses || metric == .threeMisses ? .missed : .made
            return ShotObservedCount(value: fieldGoals.filter { $0.value == value && $0.outcome == outcome }.count,
                pending: fieldGoals.filter { $0.value == nil || ($0.value == value && $0.outcome == nil) }.count)
        case .twoAttempts, .threeAttempts:
            let value = metric == .twoAttempts ? 2 : 3
            return ShotObservedCount(value: fieldGoals.filter { $0.value == value }.count,
                pending: fieldGoals.filter { $0.value == nil }.count)
        case .freeThrowMakes, .freeThrowMisses:
            let outcome: ShotOutcome = metric == .freeThrowMakes ? .made : .missed
            return ShotObservedCount(value: events.reduce(0) { $0 + $1.answers.filter { $0.outcome == outcome }.count },
                pending: events.reduce(0) { $0 + (($1.freeThrowAttempts ?? 0) - $1.answers.count) })
        case .freeThrowAttempts:
            return ShotObservedCount(value: events.reduce(0) { $0 + ($1.freeThrowAttempts ?? 0) }, pending: 0)
        }
    }
    func scoreCheck(official: Int?) -> ShotComparison { Self.compare(points, pending: pending, official: official) }
    func countCheck(_ metric: ShotMetric, official: Int?) -> ShotComparison {
        let observed = count(metric); return Self.compare(observed.value, pending: observed.pending, official: official)
    }
    private static func compare(_ value: Int, pending: Int, official: Int?) -> ShotComparison {
        guard let official, official >= 0 else { return .unavailable }
        if pending > 0 { return value > official ? .lowerBoundDisagrees : .incomplete }
        return value == official ? .match : .disagree
    }
}

/// Independent saved source with provenance; missing values never become zeros.
struct ShotOfficialSource: Identifiable {
    let id: String
    let label: String
    let counts: [ShotMetric: ShotOfficialCount]
    static func boxes(_ records: [PlayerBoxScore], expectedPlayerIDs: [String], label: String) -> Self {
        let rows: [[String: Int]?] = expectedPlayerIDs.map { id in records.first { samePlayer($0.playerID, id) }?.values }
        return Self(id: "boxes", label: label, counts: counts(rows))
    }
    static func possessions(_ records: [PossessionRecord], label: String) -> Self {
        Self(id: "possessions", label: label, counts: counts(records.map { Optional($0.values) }))
    }
    private static func samePlayer(_ a: String, _ b: String) -> Bool {
        if let first = UUID(uuidString: a), let second = UUID(uuidString: b) { return first == second }; return a == b
    }
    private static func counts(_ rows: [[String: Int]?]) -> [ShotMetric: ShotOfficialCount] {
        var result: [ShotMetric: ShotOfficialCount] = [:]
        for (made, attempts, keyMade, keyMissed) in [
            (ShotMetric.twoMakes, ShotMetric.twoAttempts, "twosMade", "twosMissed"),
            (.threeMakes, .threeAttempts, "threesMade", "threesMissed"),
            (.freeThrowMakes, .freeThrowAttempts, "freeThrowsMade", "freeThrowsMissed")] {
            result[made] = .sum(rows.map { $0?[keyMade] })
            let missed: ShotMetric = made == .twoMakes ? .twoMisses : made == .threeMakes ? .threeMisses : .freeThrowMisses
            result[missed] = .sum(rows.map { $0?[keyMissed] })
            var attemptInputs: [Int?] = [], invalidArithmetic = false
            for row in rows {
                guard let a = row?[keyMade], let b = row?[keyMissed] else { attemptInputs.append(nil); continue }
                guard a >= 0, b >= 0 else { invalidArithmetic = true; continue }
                let sum = a.addingReportingOverflow(b)
                if sum.overflow { invalidArithmetic = true } else { attemptInputs.append(sum.partialValue) }
            }
            result[attempts] = invalidArithmetic ? ShotOfficialCount(value: nil, missing: 0, unavailable: true) : .sum(attemptInputs)
        }
        return result
    }
}
