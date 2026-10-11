import Foundation

enum StatisticUnavailable: Equatable {
    case incompleteDataset, missingInput, invalidInput, overflow, zeroAttempts
}

enum StatisticValue<Value: Equatable>: Equatable {
    case available(Value)
    case unavailable(StatisticUnavailable)
}

enum StatisticShot: CaseIterable {
    case twos, threes, freeThrows

    fileprivate var possessionFields: (made: PossessionField, missed: PossessionField) {
        switch self {
        case .twos: (.twosMade, .twosMissed)
        case .threes: (.threesMade, .threesMissed)
        case .freeThrows: (.freeThrowsMade, .freeThrowsMissed)
        }
    }

    fileprivate var boxFields: (made: BoxScoreField, missed: BoxScoreField) {
        switch self {
        case .twos: (.twosMade, .twosMissed)
        case .threes: (.threesMade, .threesMissed)
        case .freeThrows: (.freeThrowsMade, .freeThrowsMissed)
        }
    }
}

// Supplied by the caller from dataset state; numeric coverage never implies completion.
struct GameStatisticsCompletion {
    var boxScores = false
    var ourPossessions = false
    var opponentPossessions = false
}

struct StatisticComparison: Equatable {
    let field: BoxScoreField
    let boxScoreTotal: Int
    let possessionTotal: Int

    var matches: Bool { boxScoreTotal == possessionTotal }
    // Totals emitted by reconcile are nonnegative Ints, so their difference fits in Int.
    var difference: Int { boxScoreTotal - possessionTotal }
}

// Calculation only: this does not establish server completion, review, or publication.
struct GameStatistics {
    let gameID: UUID
    let boxScores: [PlayerBoxScore]
    let coveredPlayerIDs: Set<String>
    let possessions: [PossessionRecord]
    let completion: GameStatisticsCompletion

    func boxScoreTotal(_ field: BoxScoreField, playerID: String? = nil) -> StatisticValue<Int> {
        guard completion.boxScores else { return .unavailable(.incompleteDataset) }
        let fields = Set(BoxScoreField.allCases.map(\.rawValue))
        guard !coveredPlayerIDs.contains(""),
              Set(boxScores.map(\.playerID)).count == boxScores.count,
              boxScores.allSatisfy({ record in
                  record.gameID == gameID && coveredPlayerIDs.contains(record.playerID) &&
                  record.values.allSatisfy { fields.contains($0.key) && $0.value >= 0 }
              }) else { return .unavailable(.invalidInput) }
        guard !coveredPlayerIDs.isEmpty,
              coveredPlayerIDs.isSubset(of: Set(boxScores.map(\.playerID))) else {
            return .unavailable(.missingInput)
        }
        let selected = boxScores.filter { playerID == nil || $0.playerID == playerID }
        guard !selected.isEmpty else { return .unavailable(.missingInput) }
        let values = selected.compactMap { $0.values[field.rawValue] }
        guard values.count == selected.count else { return .unavailable(.missingInput) }
        return checkedSum(values)
    }

    func boxScoreRebounds(playerID: String? = nil) -> StatisticValue<Int> {
        combine(boxScoreTotal(.offensiveRebounds, playerID: playerID),
                boxScoreTotal(.defensiveRebounds, playerID: playerID))
    }

    func boxScoreShotAttempts(_ shot: StatisticShot, playerID: String? = nil) -> StatisticValue<Int> {
        combine(boxScoreTotal(shot.boxFields.made, playerID: playerID),
                boxScoreTotal(shot.boxFields.missed, playerID: playerID))
    }

    // Percentage is on a 0...100 scale, using summed makes and attempts rather than averaged percentages.
    func boxScoreShootingPercentage(_ shot: StatisticShot, playerID: String? = nil) -> StatisticValue<Double> {
        percentage(made: boxScoreTotal(shot.boxFields.made, playerID: playerID),
                   attempts: boxScoreShotAttempts(shot, playerID: playerID))
    }

    func realPossessions(team: PossessionTeam) -> StatisticValue<Int> {
        let records = possessions.filter { $0.team == team }
        if let reason = possessionIssue(records, team: team) { return .unavailable(reason) }
        guard records.allSatisfy({ $0.turnover != nil && $0.values["offensiveRebounds"] != nil }) else {
            return .unavailable(.missingInput)
        }
        let turnovers = records.filter { $0.turnover == true }.count
        return checkedSum([records.count - turnovers] + records.compactMap { $0.values["offensiveRebounds"] })
    }

    func possessionTotal(_ field: PossessionField, team: PossessionTeam) -> StatisticValue<Int> {
        let records = possessions.filter { $0.team == team }
        if let reason = possessionIssue(records, team: team) { return .unavailable(reason) }
        let values = records.compactMap { $0.values[field.rawValue] }
        guard values.count == records.count else { return .unavailable(.missingInput) }
        return checkedSum(values)
    }

    func possessionShotAttempts(_ shot: StatisticShot, team: PossessionTeam) -> StatisticValue<Int> {
        combine(possessionTotal(shot.possessionFields.made, team: team),
                possessionTotal(shot.possessionFields.missed, team: team))
    }

    func possessionShootingPercentage(_ shot: StatisticShot, team: PossessionTeam) -> StatisticValue<Double> {
        percentage(made: possessionTotal(shot.possessionFields.made, team: team),
                   attempts: possessionShotAttempts(shot, team: team))
    }

    func possessionPoints(team: PossessionTeam) -> StatisticValue<Int> {
        let twos = weighted(possessionTotal(.twosMade, team: team), by: 2)
        let threes = weighted(possessionTotal(.threesMade, team: team), by: 3)
        return combine(combine(twos, threes), possessionTotal(.freeThrowsMade, team: team))
    }

    func reconcile() -> StatisticValue<[StatisticComparison]> {
        let fields: [BoxScoreField] = [.points, .twosMade, .twosMissed, .threesMade,
                                       .threesMissed, .freeThrowsMade, .freeThrowsMissed]
        var comparisons: [StatisticComparison] = []
        for field in fields {
            let box = boxScoreTotal(field)
            let team: StatisticValue<Int>
            if field == .points {
                team = possessionPoints(team: .ours)
            } else if let possessionField = PossessionField(rawValue: field.rawValue) {
                team = possessionTotal(possessionField, team: .ours)
            } else {
                return .unavailable(.invalidInput)
            }
            switch (box, team) {
            case (.available(let playerTotal), .available(let teamTotal)):
                comparisons.append(StatisticComparison(field: field, boxScoreTotal: playerTotal,
                                                        possessionTotal: teamTotal))
            case (.unavailable(let reason), _), (_, .unavailable(let reason)):
                return .unavailable(reason)
            }
        }
        return .available(comparisons)
    }

    private func weighted(_ value: StatisticValue<Int>, by weight: Int) -> StatisticValue<Int> {
        switch value {
        case .available(let count):
            let result = count.multipliedReportingOverflow(by: weight)
            return result.overflow ? .unavailable(.overflow) : .available(result.partialValue)
        case .unavailable(let reason): return .unavailable(reason)
        }
    }

    private func possessionIssue(_ records: [PossessionRecord], team: PossessionTeam) -> StatisticUnavailable? {
        let complete = team == .ours ? completion.ourPossessions : completion.opponentPossessions
        guard complete else { return .incompleteDataset }
        let fields = Set(PossessionField.allCases.map(\.rawValue))
        guard Set(records.map(\.id)).count == records.count,
              Set(records.map(\.number)).count == records.count,
              records.allSatisfy({ record in
                  record.gameID == gameID && record.number > 0 &&
                  record.values.allSatisfy { fields.contains($0.key) && $0.value >= 0 }
              }) else { return .invalidInput }
        guard !records.isEmpty,
              records.map(\.number).sorted() == Array(1...records.count) else { return .missingInput }
        return nil
    }

    private func percentage(made: StatisticValue<Int>, attempts: StatisticValue<Int>) -> StatisticValue<Double> {
        switch (made, attempts) {
        case (.available(let makes), .available(let total)):
            guard total > 0 else { return .unavailable(.zeroAttempts) }
            return .available(Double(makes) / Double(total) * 100)
        case (.unavailable(let reason), _), (_, .unavailable(let reason)): return .unavailable(reason)
        }
    }

    private func combine(_ first: StatisticValue<Int>, _ second: StatisticValue<Int>) -> StatisticValue<Int> {
        switch (first, second) {
        case (.available(let a), .available(let b)): return checkedSum([a, b])
        case (.unavailable(let reason), _), (_, .unavailable(let reason)): return .unavailable(reason)
        }
    }

    private func checkedSum(_ values: [Int]) -> StatisticValue<Int> {
        var sum = 0
        for value in values {
            let next = sum.addingReportingOverflow(value)
            guard !next.overflow else { return .unavailable(.overflow) }
            sum = next.partialValue
        }
        return .available(sum)
    }
}
