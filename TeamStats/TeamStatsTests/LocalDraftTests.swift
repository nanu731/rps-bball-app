import XCTest
@testable import TeamStats

final class LocalDraftTests: XCTestCase {
    @MainActor
    func testPartialContradictionDoesNotRequireMissingMakes() async {
        XCTAssertEqual(boxScoreShotCheck(["points": "4", "threesMade": "7"]),
                       "Points disagree: entered 4; entered made shots imply at least 21.")
        XCTAssertTrue(boxScoreShotCheck(["points": "21", "threesMade": "7"]).hasPrefix("Check incomplete"))
        XCTAssertEqual(boxScoreShotCheck(["points": "0", "twosMade": "0", "threesMade": "0", "freeThrowsMade": "0"]),
                       "Points match made shots (0).")
        XCTAssertTrue(boxScoreShotCheck(["points": "1", "threesMade": String(Int.max)]).hasPrefix("Check unavailable"))
    }

    @MainActor
    func testDraftEditPreservesMissingCountsAndOtherGame() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("test-box-scores.json")
        let game = UUID(), otherGame = UUID()
        let first = PlayerBoxScore(gameID: game, playerID: "synthetic-player", values: ["points": 0])
        let other = PlayerBoxScore(gameID: otherGame, playerID: "synthetic-player", values: ["points": 8])
        try BoxScoreStorage.save([first, other], to: url)
        let edit = PlayerBoxScore(gameID: game, playerID: "synthetic-player", values: ["points": 4, "threesMade": 7])
        try BoxScoreStorage.save(BoxScoreStorage.updating(try BoxScoreStorage.load(from: url), with: [edit]), to: url)
        let saved = try BoxScoreStorage.load(from: url)
        XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(saved.first { $0.gameID == otherGame }?.values["points"], 8)
        XCTAssertNil(saved.first { $0.gameID == game }?.values["twosMade"])
    }

    @MainActor
    func testPaintTouchReloadDistinguishesMissingAndZero() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("test-paint-touches.json")
        let game = UUID()
        try PlayerPaintTouchStorage.save([
            PlayerPaintTouchRecord(gameID: game, playerID: "synthetic-a", total: nil),
            PlayerPaintTouchRecord(gameID: game, playerID: "synthetic-b", total: 0)
        ], to: url)
        let records = try PlayerPaintTouchStorage.load(from: url)
        XCTAssertNil(records[0].total)
        XCTAssertEqual(records[1].total, 0)
    }
}
