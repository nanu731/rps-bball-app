import XCTest
@testable import TeamStats

final class GameStatisticsTests: XCTestCase {
    @MainActor
    func testCompletedCoveredPlayerTotalsRetainEnteredZero() async {
        let game = UUID()
        let statistics = GameStatistics(gameID: game, boxScores: [
            PlayerBoxScore(gameID: game, playerID: "synthetic-a", values: ["points": 12]),
            PlayerBoxScore(gameID: game, playerID: "synthetic-b", values: ["points": 0])
        ], coveredPlayerIDs: ["synthetic-a", "synthetic-b"], possessions: [],
           completion: GameStatisticsCompletion(boxScores: true))
        XCTAssertEqual(statistics.boxScoreTotal(.points), .available(12))
    }

    @MainActor
    func testDraftTotalsStayUnavailableDespiteFullNumericCoverage() async {
        let game = UUID()
        let statistics = GameStatistics(gameID: game, boxScores: [
            PlayerBoxScore(gameID: game, playerID: "synthetic-a", values: ["points": 0])
        ], coveredPlayerIDs: ["synthetic-a"], possessions: [],
           completion: GameStatisticsCompletion())
        XCTAssertEqual(statistics.boxScoreTotal(.points), .unavailable(.incompleteDataset))
    }

    @MainActor
    func testCompletedTotalsRequireEveryCoveredPlayerAndEnteredField() async {
        let game = UUID()
        let cases: [(Set<String>, [PlayerBoxScore])] = [
            ([], []),
            (["synthetic-a"], []),
            (["synthetic-a"], [PlayerBoxScore(gameID: game, playerID: "synthetic-a", values: [:])]),
            (["synthetic-a", "synthetic-b"], [PlayerBoxScore(gameID: game, playerID: "synthetic-a", values: ["points": 0])])
        ]
        for (covered, records) in cases {
            let statistics = GameStatistics(gameID: game, boxScores: records,
                coveredPlayerIDs: covered, possessions: [],
                completion: GameStatisticsCompletion(boxScores: true))
            XCTAssertEqual(statistics.boxScoreTotal(.points), .unavailable(.missingInput))
        }
    }

    @MainActor
    func testTotalsRejectInvalidOrMismatchedPlayerRecords() async {
        let game = UUID()
        let valid = PlayerBoxScore(gameID: game, playerID: "synthetic-a", values: ["points": 5])
        let cases = [
            [PlayerBoxScore(gameID: UUID(), playerID: "synthetic-a", values: ["points": 5])],
            [PlayerBoxScore(gameID: game, playerID: "synthetic-a", values: ["points": -1])],
            [PlayerBoxScore(gameID: game, playerID: "synthetic-a", values: ["points": 5, "unknown": 1])],
            [valid, valid],
            [valid, PlayerBoxScore(gameID: game, playerID: "unexpected", values: ["points": 5])]
        ]
        for records in cases {
            let statistics = GameStatistics(gameID: game, boxScores: records,
                coveredPlayerIDs: ["synthetic-a"], possessions: [],
                completion: GameStatisticsCompletion(boxScores: true))
            XCTAssertEqual(statistics.boxScoreTotal(.points), .unavailable(.invalidInput))
        }
    }

    @MainActor
    func testPlayerTotalOverflowIsUnavailable() async {
        let game = UUID()
        let statistics = GameStatistics(gameID: game, boxScores: [
            PlayerBoxScore(gameID: game, playerID: "synthetic-a", values: ["points": Int.max]),
            PlayerBoxScore(gameID: game, playerID: "synthetic-b", values: ["points": 1])
        ], coveredPlayerIDs: ["synthetic-a", "synthetic-b"], possessions: [],
           completion: GameStatisticsCompletion(boxScores: true))
        XCTAssertEqual(statistics.boxScoreTotal(.points), .unavailable(.overflow))
    }

    @MainActor
    func testReboundsAreDerivedFromBothEnteredCountsForPlayerAndTeam() async {
        let game = UUID()
        let statistics = GameStatistics(gameID: game, boxScores: [
            PlayerBoxScore(gameID: game, playerID: "synthetic-a", values: ["offensiveRebounds": 2, "defensiveRebounds": 5]),
            PlayerBoxScore(gameID: game, playerID: "synthetic-b", values: ["offensiveRebounds": 1, "defensiveRebounds": 3])
        ], coveredPlayerIDs: ["synthetic-a", "synthetic-b"], possessions: [],
           completion: GameStatisticsCompletion(boxScores: true))
        XCTAssertEqual(statistics.boxScoreRebounds(playerID: "synthetic-a"), .available(7))
        XCTAssertEqual(statistics.boxScoreRebounds(), .available(11))
    }

    @MainActor
    func testShotAttemptsAndPercentagesSumCountsBeforeDivision() async {
        let game = UUID()
        let statistics = GameStatistics(gameID: game, boxScores: [
            PlayerBoxScore(gameID: game, playerID: "synthetic-a", values: [
                "twosMade": 1, "twosMissed": 3, "threesMade": 2, "threesMissed": 2,
                "freeThrowsMade": 3, "freeThrowsMissed": 1]),
            PlayerBoxScore(gameID: game, playerID: "synthetic-b", values: [
                "twosMade": 1, "twosMissed": 0, "threesMade": 1, "threesMissed": 3,
                "freeThrowsMade": 1, "freeThrowsMissed": 0])
        ], coveredPlayerIDs: ["synthetic-a", "synthetic-b"], possessions: [],
           completion: GameStatisticsCompletion(boxScores: true))
        XCTAssertEqual(statistics.boxScoreShotAttempts(.twos, playerID: "synthetic-a"), .available(4))
        XCTAssertEqual(statistics.boxScoreShootingPercentage(.twos, playerID: "synthetic-a"), .available(25))
        XCTAssertEqual(statistics.boxScoreShotAttempts(.twos), .available(5))
        XCTAssertEqual(statistics.boxScoreShootingPercentage(.twos), .available(40))
        XCTAssertEqual(statistics.boxScoreShotAttempts(.threes), .available(8))
        XCTAssertEqual(statistics.boxScoreShootingPercentage(.threes), .available(37.5))
        XCTAssertEqual(statistics.boxScoreShotAttempts(.freeThrows), .available(5))
        XCTAssertEqual(statistics.boxScoreShootingPercentage(.freeThrows), .available(80))
    }

    @MainActor
    func testRealPossessionsUsesEachTeamsOwnCountTurnoversAndRebounds() async {
        let game = UUID()
        let statistics = GameStatistics(gameID: game, boxScores: [], coveredPlayerIDs: [], possessions: [
            possession(game, .ours, 1, rebounds: 2, turnover: true),
            possession(game, .opponent, 1, rebounds: 4, turnover: false),
            possession(game, .ours, 2, rebounds: 0, turnover: false),
            possession(game, .opponent, 2, rebounds: 2, turnover: true),
            possession(game, .ours, 3, rebounds: 1, turnover: false)
        ], completion: GameStatisticsCompletion(ourPossessions: true, opponentPossessions: true))
        XCTAssertEqual(statistics.realPossessions(team: .ours), .available(5))
        XCTAssertEqual(statistics.realPossessions(team: .opponent), .available(7))
    }

    @MainActor
    func testRealPossessionsRequiresCompletedMatchingValidInputs() async {
        let game = UUID()
        let valid = possession(game, .ours, 1, rebounds: 0, turnover: false)
        let cases: [([PossessionRecord], Bool, StatisticUnavailable)] = [
            ([valid], false, .incompleteDataset),
            ([], true, .missingInput),
            ([possession(game, .ours, 1, rebounds: 0, turnover: nil)], true, .missingInput),
            ([PossessionRecord(id: UUID(), gameID: game, team: .ours, number: 1, values: [:], turnover: false)], true, .missingInput),
            ([possession(UUID(), .ours, 1, rebounds: 0, turnover: false)], true, .invalidInput),
            ([possession(game, .ours, 1, rebounds: -1, turnover: false)], true, .invalidInput),
            ([valid, valid], true, .invalidInput),
            ([valid, possession(game, .ours, 1, rebounds: 0, turnover: false)], true, .invalidInput),
            ([possession(game, .ours, 0, rebounds: 0, turnover: false)], true, .invalidInput),
            ([possession(game, .ours, 2, rebounds: 0, turnover: false)], true, .missingInput),
            ([possession(game, .ours, 1, rebounds: Int.max, turnover: false)], true, .overflow)
        ]
        for (records, complete, reason) in cases {
            let statistics = GameStatistics(gameID: game, boxScores: [], coveredPlayerIDs: [],
                possessions: records, completion: GameStatisticsCompletion(ourPossessions: complete))
            XCTAssertEqual(statistics.realPossessions(team: .ours), .unavailable(reason))
            XCTAssertEqual(statistics.realPossessions(team: .opponent), .unavailable(.incompleteDataset))
        }
        let zero = GameStatistics(gameID: game, boxScores: [], coveredPlayerIDs: [],
            possessions: [possession(game, .ours, 1, rebounds: 0, turnover: true)],
            completion: GameStatisticsCompletion(ourPossessions: true))
        XCTAssertEqual(zero.realPossessions(team: .ours), .available(0))
    }

    @MainActor
    func testPossessionScoringAndShootingRemainTeamSpecific() async {
        let game = UUID()
        let statistics = GameStatistics(gameID: game, boxScores: [], coveredPlayerIDs: [], possessions: [
            PossessionRecord(id: UUID(), gameID: game, team: .ours, number: 1, values: [
                "twosMade": 2, "twosMissed": 3, "threesMade": 1, "threesMissed": 1,
                "freeThrowsMade": 2, "freeThrowsMissed": 0], turnover: false),
            PossessionRecord(id: UUID(), gameID: game, team: .opponent, number: 1, values: [
                "twosMade": 1, "twosMissed": 0, "threesMade": 0, "threesMissed": 2,
                "freeThrowsMade": 1, "freeThrowsMissed": 1], turnover: false)
        ], completion: GameStatisticsCompletion(ourPossessions: true, opponentPossessions: true))
        XCTAssertEqual(statistics.possessionPoints(team: .ours), .available(9))
        XCTAssertEqual(statistics.possessionPoints(team: .opponent), .available(3))
        XCTAssertEqual(statistics.possessionShotAttempts(.twos, team: .ours), .available(5))
        XCTAssertEqual(statistics.possessionShootingPercentage(.twos, team: .ours), .available(40))
        XCTAssertEqual(statistics.possessionShootingPercentage(.threes, team: .ours), .available(50))
        XCTAssertEqual(statistics.possessionShootingPercentage(.freeThrows, team: .ours), .available(100))
        XCTAssertEqual(statistics.possessionShootingPercentage(.twos, team: .opponent), .available(100))
        XCTAssertEqual(statistics.possessionShootingPercentage(.threes, team: .opponent), .available(0))
        XCTAssertEqual(statistics.possessionShootingPercentage(.freeThrows, team: .opponent), .available(50))
    }

    @MainActor
    func testReconciliationComparesOnlyMatchingCompletedOurTeamData() async {
        let game = UUID()
        let statistics = reconciliationExample(game)
        XCTAssertEqual(statistics.reconcile(), .available([
            StatisticComparison(field: .points, boxScoreTotal: 11, possessionTotal: 11),
            StatisticComparison(field: .twosMade, boxScoreTotal: 2, possessionTotal: 2),
            StatisticComparison(field: .twosMissed, boxScoreTotal: 2, possessionTotal: 2),
            StatisticComparison(field: .threesMade, boxScoreTotal: 1, possessionTotal: 1),
            StatisticComparison(field: .threesMissed, boxScoreTotal: 1, possessionTotal: 1),
            StatisticComparison(field: .freeThrowsMade, boxScoreTotal: 4, possessionTotal: 4),
            StatisticComparison(field: .freeThrowsMissed, boxScoreTotal: 2, possessionTotal: 2)
        ]))
    }

    @MainActor
    func testReconciliationReportsSignedDifferencesWithoutChangingInputs() async {
        let game = UUID()
        let original = reconciliationExample(game)
        var records = original.boxScores
        records[0].values["points"] = 3
        records[0].values["twosMade"] = 0
        records[0].values["threesMissed"] = 2
        let statistics = GameStatistics(gameID: game, boxScores: records,
            coveredPlayerIDs: original.coveredPlayerIDs, possessions: original.possessions,
            completion: original.completion)
        guard case .available(let comparisons) = statistics.reconcile() else {
            XCTFail("Complete matching datasets should produce inspectable comparisons")
            return
        }
        XCTAssertEqual(comparisons[0].boxScoreTotal, 9)
        XCTAssertEqual(comparisons[0].possessionTotal, 11)
        XCTAssertEqual(comparisons[0].difference, -2)
        XCTAssertFalse(comparisons[0].matches)
        XCTAssertEqual(comparisons[1].difference, -1)
        XCTAssertEqual(comparisons[4].difference, 2)
        XCTAssertTrue(comparisons[5].matches)
        XCTAssertEqual(records[0].values["points"], 3)
        XCTAssertEqual(original.boxScores[0].values["points"], 5)
    }

    @MainActor
    func testReconciliationCannotTreatDraftOrMissingDataAsMatchingZeroSums() async {
        let game = UUID()
        let original = reconciliationExample(game)
        for completion in [GameStatisticsCompletion(boxScores: true),
                           GameStatisticsCompletion(ourPossessions: true)] {
            let statistics = GameStatistics(gameID: game, boxScores: original.boxScores,
                coveredPlayerIDs: original.coveredPlayerIDs, possessions: original.possessions,
                completion: completion)
            XCTAssertEqual(statistics.reconcile(), .unavailable(.incompleteDataset))
        }
        let empty = GameStatistics(gameID: game, boxScores: [], coveredPlayerIDs: [], possessions: [],
            completion: original.completion)
        XCTAssertEqual(empty.reconcile(), .unavailable(.missingInput))
        var records = original.boxScores
        records[0].values.removeValue(forKey: "twosMissed")
        let missing = GameStatistics(gameID: game, boxScores: records,
            coveredPlayerIDs: original.coveredPlayerIDs, possessions: original.possessions,
            completion: original.completion)
        XCTAssertEqual(missing.reconcile(), .unavailable(.missingInput))
        let foreign = GameStatistics(gameID: UUID(), boxScores: original.boxScores,
            coveredPlayerIDs: original.coveredPlayerIDs, possessions: original.possessions,
            completion: original.completion)
        XCTAssertEqual(foreign.reconcile(), .unavailable(.invalidInput))
    }

    @MainActor
    func testZeroAttemptsMissingCountsAndDerivedOverflowStayUnavailable() async {
        let game = UUID()
        let cases: [([String: Int], StatisticValue<Int>, StatisticValue<Double>)] = [
            (["twosMade": 0, "twosMissed": 0], .available(0), .unavailable(.zeroAttempts)),
            (["twosMade": 0], .unavailable(.missingInput), .unavailable(.missingInput)),
            (["twosMade": Int.max, "twosMissed": 1], .unavailable(.overflow), .unavailable(.overflow))
        ]
        for (values, attempts, percentage) in cases {
            let statistics = GameStatistics(gameID: game,
                boxScores: [PlayerBoxScore(gameID: game, playerID: "synthetic-a", values: values)],
                coveredPlayerIDs: ["synthetic-a"], possessions: [
                    PossessionRecord(id: UUID(), gameID: game, team: .ours, number: 1,
                                     values: values, turnover: false)
                ], completion: GameStatisticsCompletion(boxScores: true, ourPossessions: true))
            XCTAssertEqual(statistics.boxScoreShotAttempts(.twos), attempts)
            XCTAssertEqual(statistics.boxScoreShootingPercentage(.twos), percentage)
            XCTAssertEqual(statistics.possessionShotAttempts(.twos, team: .ours), attempts)
            XCTAssertEqual(statistics.possessionShootingPercentage(.twos, team: .ours), percentage)
        }
        for (values, expected) in [
            (["offensiveRebounds": 0], StatisticValue<Int>.unavailable(.missingInput)),
            (["offensiveRebounds": Int.max, "defensiveRebounds": 1], .unavailable(.overflow))
        ] {
            let statistics = GameStatistics(gameID: game,
                boxScores: [PlayerBoxScore(gameID: game, playerID: "synthetic-a", values: values)],
                coveredPlayerIDs: ["synthetic-a"], possessions: [],
                completion: GameStatisticsCompletion(boxScores: true))
            XCTAssertEqual(statistics.boxScoreRebounds(), expected)
        }
    }

    @MainActor
    func testPossessionPointWeightAndReconciliationOverflowStayUnavailable() async {
        let game = UUID()
        let cases = [
            ["twosMade": Int.max, "threesMade": 0, "freeThrowsMade": 0],
            ["twosMade": 0, "threesMade": Int.max, "freeThrowsMade": 0],
            ["twosMade": 1, "threesMade": 0, "freeThrowsMade": Int.max]
        ]
        for values in cases {
            let statistics = GameStatistics(gameID: game,
                boxScores: [PlayerBoxScore(gameID: game, playerID: "synthetic-a", values: ["points": 0])],
                coveredPlayerIDs: ["synthetic-a"], possessions: [
                    PossessionRecord(id: UUID(), gameID: game, team: .ours, number: 1,
                                     values: values, turnover: false)
                ], completion: GameStatisticsCompletion(boxScores: true, ourPossessions: true))
            XCTAssertEqual(statistics.possessionPoints(team: .ours), .unavailable(.overflow))
            XCTAssertEqual(statistics.reconcile(), .unavailable(.overflow))
        }
    }

    @MainActor
    func testReconciliationAcceptsExplicitZerosButRejectsMissingPossessionShots() async {
        let game = UUID()
        let zeros = ["points": 0, "twosMade": 0, "twosMissed": 0, "threesMade": 0,
                     "threesMissed": 0, "freeThrowsMade": 0, "freeThrowsMissed": 0]
        let player = PlayerBoxScore(gameID: game, playerID: "synthetic-a", values: zeros)
        var team = PossessionRecord(id: UUID(), gameID: game, team: .ours, number: 1,
                                   values: zeros.filter { $0.key != "points" }, turnover: false)
        let complete = GameStatisticsCompletion(boxScores: true, ourPossessions: true)
        let statistics = GameStatistics(gameID: game, boxScores: [player],
            coveredPlayerIDs: ["synthetic-a"], possessions: [team], completion: complete)
        guard case .available(let comparisons) = statistics.reconcile() else {
            XCTFail("Explicit completed zeros must remain usable")
            return
        }
        XCTAssertEqual(comparisons.count, 7)
        XCTAssertTrue(comparisons.allSatisfy(\.matches))
        XCTAssertTrue(comparisons.allSatisfy { $0.boxScoreTotal == 0 && $0.possessionTotal == 0 })
        team.values.removeValue(forKey: "freeThrowsMissed")
        let missing = GameStatistics(gameID: game, boxScores: [player],
            coveredPlayerIDs: ["synthetic-a"], possessions: [team], completion: complete)
        XCTAssertEqual(missing.reconcile(), .unavailable(.missingInput))
        XCTAssertEqual(missing.possessionShootingPercentage(.freeThrows, team: .ours), .unavailable(.missingInput))
    }

    @MainActor
    private func reconciliationExample(_ game: UUID) -> GameStatistics {
        let a = ["points": 5, "twosMade": 1, "twosMissed": 2, "threesMade": 0,
                 "threesMissed": 0, "freeThrowsMade": 3, "freeThrowsMissed": 1]
        let b = ["points": 6, "twosMade": 1, "twosMissed": 0, "threesMade": 1,
                 "threesMissed": 1, "freeThrowsMade": 1, "freeThrowsMissed": 1]
        return GameStatistics(gameID: game, boxScores: [
            PlayerBoxScore(gameID: game, playerID: "synthetic-a", values: a),
            PlayerBoxScore(gameID: game, playerID: "synthetic-b", values: b)
        ], coveredPlayerIDs: ["synthetic-a", "synthetic-b"], possessions: [
            PossessionRecord(id: UUID(), gameID: game, team: .ours, number: 1,
                values: a.filter { $0.key != "points" }, turnover: false),
            PossessionRecord(id: UUID(), gameID: game, team: .ours, number: 2,
                values: b.filter { $0.key != "points" }, turnover: false),
            PossessionRecord(id: UUID(), gameID: game, team: .opponent, number: 1,
                values: ["twosMade": 100], turnover: nil)
        ], completion: GameStatisticsCompletion(boxScores: true, ourPossessions: true))
    }

    @MainActor
    private func possession(_ game: UUID, _ team: PossessionTeam, _ number: Int,
                            rebounds: Int, turnover: Bool?) -> PossessionRecord {
        PossessionRecord(id: UUID(), gameID: game, team: team, number: number,
                         values: ["offensiveRebounds": rebounds], turnover: turnover)
    }
}
