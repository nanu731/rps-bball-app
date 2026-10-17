import XCTest
@testable import TeamStats

@MainActor final class ShotAnalysisTests: XCTestCase {
    func testSamePointsDoNotEstablishAttemptCoverageAndMissingScoreIsUnavailable() throws {
        var document = try ShotCaptureDocument.local(gameID: UUID(), players: [])
        let made = try document.startFieldGoal(team: .opponent, playerID: nil, location: ShotLocation(x: 0.2, y: 0.3), basket: .top)
        var event = try XCTUnwrap(document.events().first { $0.id == made }); event.value = 2; event.outcome = .made; try document.correct(event)
        let before = try ShotAnalysis(document: document, team: .opponent, playerID: nil)
        XCTAssertEqual(before.scoreCheck(official: nil), .unavailable)
        XCTAssertEqual(before.scoreCheck(official: 2), .match)
        let missed = try document.startFieldGoal(team: .opponent, playerID: nil, location: ShotLocation(x: 0.8, y: 0.3), basket: .top)
        event = try XCTUnwrap(document.events().first { $0.id == missed }); event.value = 2; event.outcome = .missed; try document.correct(event)
        let after = try ShotAnalysis(document: document, team: .opponent, playerID: nil)
        XCTAssertEqual(before.points, after.points)
        XCTAssertEqual(after.scoreCheck(official: 2), .match)
        XCTAssertEqual(before.count(.twoAttempts).value, 1)
        XCTAssertEqual(after.count(.twoAttempts).value, 2)
        XCTAssertEqual(after.countCheck(.twoAttempts, official: 1), .disagree)
        XCTAssertFalse(after.coverageEstablished)
    }
    func testPendingFreeThrowsAreAttemptsButNotMissesAndKnownPointsAreLowerBound() throws {
        var doc = try ShotCaptureDocument.local(gameID: UUID(), players: [])
        let ft = try doc.startFreeThrows(team: .opponent, playerID: nil, attempts: 2)
        try doc.answerFreeThrow(seriesID: ft, index: 1, outcome: .made)
        let analysis = try ShotAnalysis(document: doc, team: .opponent, playerID: nil)
        XCTAssertEqual(analysis.count(.freeThrowAttempts).value, 2)
        XCTAssertEqual(analysis.count(.freeThrowMakes).value, 1)
        XCTAssertEqual(analysis.count(.freeThrowMakes).pending, 1)
        XCTAssertEqual(analysis.count(.freeThrowMisses).value, 0)
        XCTAssertEqual(analysis.count(.freeThrowMisses).pending, 1)
        XCTAssertEqual(analysis.scoreCheck(official: 0), .lowerBoundDisagrees)
        XCTAssertEqual(analysis.scoreCheck(official: 1), .incomplete)
        XCTAssertEqual(analysis.countCheck(.freeThrowAttempts, official: 2), .match)
        XCTAssertTrue(analysis.fieldGoals.isEmpty)
        XCTAssertFalse(analysis.coverageEstablished)
    }
    func testUnknownShotValueDoesNotBecomeZeroOrATwoAndBandsAreBasketRelative() throws {
        var doc = try ShotCaptureDocument.local(gameID: UUID(), players: [])
        _ = try doc.startFieldGoal(team: .opponent, playerID: nil, location: ShotLocation(x: 0.2, y: 0.4), basket: .bottom)
        let analysis = try ShotAnalysis(document: doc, team: .opponent, playerID: nil)
        XCTAssertEqual(analysis.count(.twoAttempts).value, 0)
        XCTAssertEqual(analysis.count(.twoAttempts).pending, 1)
        XCTAssertEqual(analysis.countCheck(.twoAttempts, official: 0), .incomplete)
        XCTAssertEqual(analysis.bands.first { $0.id == "right" }?.pending, 1)
        XCTAssertEqual(analysis.scoreCheck(official: 0), .incomplete)
        XCTAssertEqual(ShotOfficialCount.sum([0, nil]).value, nil)
        XCTAssertEqual(ShotOfficialCount.sum([0, 0]).value, 0)
        XCTAssertEqual(ShotOfficialCount.sum([Int.max, 1]).value, nil)
        XCTAssertEqual(ShotOfficialCount.sum([]).value, nil)
    }
}

extension ShotAnalysisTests {
    func testPlayerFilterCorrectionAndOfficialMissingVersusZeroRemainIndependent() throws {
        let game = UUID(), player = ShotCapturePlayer(id: "TEST-chart-player", name: "TEST ONLY chart", number: "91", temporary: true)
        var doc = try ShotCaptureDocument.local(gameID: game, players: [player])
        let eventID = try doc.startFieldGoal(team: .our, playerID: player.id, location: ShotLocation(x: 0.4, y: 0.2), basket: .top)
        var event = try XCTUnwrap(doc.events().first { $0.id == eventID }); event.value = 3; event.outcome = .made; try doc.correct(event)
        let ft = try doc.startFreeThrows(team: .opponent, playerID: nil, attempts: 2)
        try doc.answerFreeThrow(seriesID: ft, index: 1, outcome: .made); try doc.answerFreeThrow(seriesID: ft, index: 2, outcome: .missed)
        let playerChart = try ShotAnalysis(document: doc, team: .our, playerID: player.id)
        XCTAssertEqual(playerChart.points, 3); XCTAssertEqual(playerChart.count(.freeThrowAttempts).value, 0)
        let opponent = try ShotAnalysis(document: doc, team: .opponent, playerID: nil)
        XCTAssertEqual(opponent.count(.freeThrowMisses).value, 1)
        XCTAssertEqual(opponent.points, 1); XCTAssertEqual(opponent.pending, 0); XCTAssertEqual(opponent.scoreCheck(official: 1), .match)
        let source = [PlayerBoxScore(gameID: game, playerID: player.id, values: ["threesMade": 0])]
        let independent = ShotOfficialSource.boxes(source, expectedPlayerIDs: [player.id], label: "TEST ONLY independent")
        XCTAssertEqual(independent.counts[.threeMakes]?.value, 0)
        XCTAssertNil(independent.counts[.threeAttempts]?.value)
        XCTAssertEqual(playerChart.countCheck(.threeMakes, official: independent.counts[.threeMakes]?.value), .disagree)
        XCTAssertEqual(source[0].values, ["threesMade": 0])
        event.outcome = .missed; try doc.correct(event)
        let corrected = try ShotAnalysis(document: doc, team: .our, playerID: player.id)
        XCTAssertEqual(corrected.points, 0); XCTAssertEqual(corrected.count(.threeAttempts).value, 1)
        try doc.undo()
        XCTAssertEqual(try ShotAnalysis(document: doc, team: .our, playerID: player.id).points, 3)
    }
}

extension ShotAnalysisTests {
    func testOfficialAttemptOverflowIsUnavailableRatherThanReportedAsMissing() throws {
        let game = UUID()
        let record = PlayerBoxScore(gameID: game, playerID: "TEST-overflow", values: ["twosMade": Int.max, "twosMissed": 1])
        let reference = ShotOfficialSource.boxes([record], expectedPlayerIDs: [record.playerID], label: "TEST ONLY overflow")
        XCTAssertNil(reference.counts[.twoAttempts]?.value)
        XCTAssertEqual(reference.counts[.twoAttempts]?.missing, 0)
        XCTAssertEqual(reference.counts[.twoAttempts]?.unavailable, true)
        var document = try ShotCaptureDocument.local(gameID: game, players: [])
        for _ in 0..<2 { _ = try document.startFreeThrows(team: .opponent, playerID: nil, attempts: ShotCaptureDocument.maximumAttempts) }
        let analysis = try ShotAnalysis(document: document, team: .opponent, playerID: nil)
        XCTAssertEqual(analysis.count(.freeThrowAttempts).value, 2 * ShotCaptureDocument.maximumAttempts)
        XCTAssertEqual(analysis.pending, 2 * ShotCaptureDocument.maximumAttempts)
    }
}
