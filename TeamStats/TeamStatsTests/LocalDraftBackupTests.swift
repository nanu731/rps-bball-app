import XCTest
@testable import TeamStats

final class LocalDraftBackupTests: XCTestCase {
    @MainActor
    func testBackupPreservesSavedIdentityMissingValuesAndHistoricalTurnover() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let gameID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let possessionID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let game = Game(id: gameID, date: Date(timeIntervalSince1970: 1_700_000_000),
                        opponent: "Synthetic opponent", venue: .away, kind: .playoff)
        try JSONEncoder().encode([game]).write(to: folder.appendingPathComponent("games.json"))
        try BoxScoreStorage.save([
            PlayerBoxScore(gameID: gameID, playerID: "temporary-01", values: ["points": 0])
        ], to: folder.appendingPathComponent("box-scores.json"))
        try PossessionStorage.save([
            PossessionRecord(id: possessionID, gameID: gameID, team: .ours, number: 1,
                             values: ["paintTouches": 0], turnover: nil)
        ], to: folder.appendingPathComponent("possessions.json"))
        try PlayerPaintTouchStorage.save([
            PlayerPaintTouchRecord(gameID: gameID, playerID: "temporary-01", total: nil),
            PlayerPaintTouchRecord(gameID: gameID, playerID: "temporary-02", total: 0)
        ], to: folder.appendingPathComponent("player-paint-touches.json"))

        let backup = try LocalDraftBackup.snapshot(from: folder)
        let decoded = try JSONDecoder().decode(LocalDraftBackup.self, from: backup.encodedData())
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.games.first?.id, gameID)
        XCTAssertEqual(decoded.games.first?.date, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(decoded.games.first?.opponent, "Synthetic opponent")
        XCTAssertEqual(decoded.games.first?.venue, .away)
        XCTAssertEqual(decoded.games.first?.kind, .playoff)
        XCTAssertEqual(decoded.boxScores.first?.gameID, gameID)
        XCTAssertEqual(decoded.boxScores.first?.playerID, "temporary-01")
        XCTAssertEqual(decoded.boxScores.first?.values["points"], 0)
        XCTAssertNil(decoded.boxScores.first?.values["twosMade"])
        XCTAssertEqual(decoded.possessions.first?.id, possessionID)
        XCTAssertEqual(decoded.possessions.first?.gameID, gameID)
        XCTAssertEqual(decoded.possessions.first?.team, .ours)
        XCTAssertEqual(decoded.possessions.first?.number, 1)
        XCTAssertEqual(decoded.possessions.first?.values["paintTouches"], 0)
        XCTAssertNil(decoded.possessions.first?.values["offensiveRebounds"])
        XCTAssertNil(decoded.possessions.first?.turnover)
        XCTAssertEqual(decoded.playerPaintTouches.map(\.playerID), ["temporary-01", "temporary-02"])
        XCTAssertNil(decoded.playerPaintTouches[0].total)
        XCTAssertEqual(decoded.playerPaintTouches[1].total, 0)
    }

    @MainActor
    func testBackupReadsOnlyLocalDraftFilesAndNeverChangesSourceBytes() throws {
        let folder = try fixtureFolder()
        let game = Game(id: UUID(), date: Date(timeIntervalSince1970: 1_700_000_000),
                        opponent: "Synthetic opponent", venue: .home, kind: .regularSeason)
        let gamesURL = folder.appendingPathComponent("games.json")
        let gamesBytes = try JSONEncoder().encode([game])
        try gamesBytes.write(to: gamesURL)
        let excluded = ["session.json", "configuration.json", "shared-cache.json", "retained-clip.mp4"]
        let excludedBytes = Data("SYNTHETIC_EXCLUDED_BYTES".utf8)
        for filename in excluded {
            try excludedBytes.write(to: folder.appendingPathComponent(filename))
        }

        let data = try LocalDraftBackup.snapshot(from: folder).encodedData()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "exportedAt", "games", "boxScores",
                                          "possessions", "playerPaintTouches"])
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("SYNTHETIC_EXCLUDED_BYTES"))
        XCTAssertEqual(try Data(contentsOf: gamesURL), gamesBytes)
        for filename in excluded {
            XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(filename)), excludedBytes)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("box-scores.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("possessions.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("player-paint-touches.json").path))
    }

    @MainActor
    func testCorruptSourceAbortsBackupWithoutRepairOrEmptySubstitution() throws {
        for filename in ["games.json", "box-scores.json", "possessions.json", "player-paint-touches.json"] {
            let folder = try fixtureFolder()
            let url = folder.appendingPathComponent(filename)
            let bytes = Data("NOT JSON — SYNTHETIC CORRUPT SOURCE".utf8)
            try bytes.write(to: url)
            XCTAssertThrowsError(try LocalDraftBackup.snapshot(from: folder), filename)
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
    }

    @MainActor
    func testGameLoadRejectsDuplicateIDsWithoutChangingSavedBytes() throws {
        let folder = try fixtureFolder()
        let url = folder.appendingPathComponent("games.json")
        let id = UUID()
        let games = [
            Game(id: id, date: Date(timeIntervalSince1970: 1_700_000_000),
                 opponent: "Synthetic first opponent", venue: .home, kind: .regularSeason),
            Game(id: id, date: Date(timeIntervalSince1970: 1_700_086_400),
                 opponent: "Synthetic second opponent", venue: .away, kind: .playoff)
        ]
        let bytes = try JSONEncoder().encode(games)
        try bytes.write(to: url)
        XCTAssertThrowsError(try GameStorage.load(from: url))
        XCTAssertThrowsError(try LocalDraftBackup.snapshot(from: folder))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    @MainActor
    func testGameLoadRejectsWhitespaceOpponentWithoutChangingSavedBytes() throws {
        let folder = try fixtureFolder()
        let url = folder.appendingPathComponent("games.json")
        let game = Game(id: UUID(), date: Date(timeIntervalSince1970: 1_700_000_000),
                        opponent: " \n\t ", venue: .home, kind: .regularSeason)
        let bytes = try JSONEncoder().encode([game])
        try bytes.write(to: url)
        XCTAssertThrowsError(try GameStorage.load(from: url))
        XCTAssertThrowsError(try LocalDraftBackup.snapshot(from: folder))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    @MainActor
    private func fixtureFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
