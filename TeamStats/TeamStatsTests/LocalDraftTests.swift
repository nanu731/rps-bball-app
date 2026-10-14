import XCTest
@testable import TeamStats

final class LocalDraftTests: XCTestCase {
    @MainActor
    func testExplicitDraftSavesUseCompleteProtectionIncludingReplacement() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Simulator does not expose file protection classes. Verify saved protection on a physical device; device lock behavior remains a separate check.")
        #else
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let game = UUID()
        let saves: [(String, (URL) throws -> Void)] = [
            ("box-scores.json", { try BoxScoreStorage.save([
                PlayerBoxScore(gameID: game, playerID: "synthetic-protection", values: [:])
            ], to: $0) }),
            ("possessions.json", { try PossessionStorage.save([
                PossessionRecord(id: UUID(), gameID: game, team: .ours, number: 1,
                                 values: [:], turnover: nil)
            ], to: $0) }),
            ("player-paint-touches.json", { try PlayerPaintTouchStorage.save([
                PlayerPaintTouchRecord(gameID: game, playerID: "synthetic-protection", total: nil)
            ], to: $0) })
        ]
        for (name, save) in saves {
            let url = folder.appendingPathComponent(name)
            try save(url)
            let newAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
            XCTAssertEqual(newAttributes[.protectionKey] as? FileProtectionType, .complete, name)
            // An atomic replacement must carry the protection class as well as a first save.
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                                  ofItemAtPath: url.path)
            try save(url)
            let replacedAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
            XCTAssertEqual(replacedAttributes[.protectionKey] as? FileProtectionType, .complete, name)
        }
        #endif
    }

    @MainActor
    func testPossessionReloadPreservesIdentityIndependentNumberingAndMissingAnswers() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("test-possessions.json")
        let game = UUID(), first = UUID(), opponent = UUID(), second = UUID()
        try PossessionStorage.save([
            PossessionRecord(id: first, gameID: game, team: .ours, number: 1,
                             values: ["paintTouches": 0], turnover: nil),
            PossessionRecord(id: opponent, gameID: game, team: .opponent, number: 1,
                             values: [:], turnover: false),
            PossessionRecord(id: second, gameID: game, team: .ours, number: 2,
                             values: ["twosMade": 1], turnover: true)
        ], to: url)
        let saved = try PossessionStorage.load(from: url)
        XCTAssertEqual(saved.map(\.id), [first, opponent, second])
        XCTAssertEqual(saved.map(\.gameID), [game, game, game])
        XCTAssertEqual(saved.map(\.team), [.ours, .opponent, .ours])
        XCTAssertEqual(saved.map(\.number), [1, 1, 2])
        XCTAssertEqual(saved[0].values["paintTouches"], 0)
        XCTAssertNil(saved[0].values["offensiveRebounds"])
        XCTAssertNil(saved[0].turnover)
        XCTAssertTrue(saved[1].values.isEmpty)
        XCTAssertEqual(saved[1].turnover, false)
        XCTAssertEqual(saved[2].values["twosMade"], 1)
        XCTAssertEqual(saved[2].turnover, true)
    }

    @MainActor
    func testReadingLegacyDraftsPreservesExactBytesAndProtection() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let gameID = UUID(uuidString: "B0000000-0000-4000-8000-000000000001")!
        let possessionID = UUID(uuidString: "B0000000-0000-4000-8000-000000000002")!
        let fixtures: [(String, String, (URL) throws -> Void)] = [
            ("box-scores.json", """
                [ { "playerID": "temporary-legacy", "values": {"points": 0},
                    "gameID": "B0000000-0000-4000-8000-000000000001" } ]
                """, { url in
                    let records = try BoxScoreStorage.load(from: url)
                    XCTAssertEqual(records.count, 1)
                    XCTAssertEqual(records.first?.gameID, gameID)
                    XCTAssertEqual(records.first?.playerID, "temporary-legacy")
                    XCTAssertEqual(records.first?.values["points"], 0)
                    XCTAssertNil(records.first?.values["twosMade"])
                }),
            ("possessions.json", """
                [ { "id": "B0000000-0000-4000-8000-000000000002",
                    "gameID": "B0000000-0000-4000-8000-000000000001", "team": "ours",
                    "number": 1, "values": {"paintTouches": 0} } ]
                """, { url in
                    let records = try PossessionStorage.load(from: url)
                    XCTAssertEqual(records.count, 1)
                    XCTAssertEqual(records.first?.id, possessionID)
                    XCTAssertEqual(records.first?.gameID, gameID)
                    XCTAssertEqual(records.first?.values["paintTouches"], 0)
                    XCTAssertNil(records.first?.values["offensiveRebounds"])
                    XCTAssertNil(records.first?.turnover)
                }),
            ("player-paint-touches.json", """
                [ { "gameID": "B0000000-0000-4000-8000-000000000001",
                    "playerID": "temporary-legacy" } ]
                """, { url in
                    let records = try PlayerPaintTouchStorage.load(from: url)
                    XCTAssertEqual(records.count, 1)
                    XCTAssertEqual(records.first?.gameID, gameID)
                    XCTAssertEqual(records.first?.playerID, "temporary-legacy")
                    XCTAssertNil(records.first?.total)
                })
        ]
        for (name, fixture, load) in fixtures {
            let url = folder.appendingPathComponent(name)
            let bytes = Data(fixture.utf8)
            try bytes.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            let before = try FileManager.default.attributesOfItem(atPath: url.path)
            try load(url)
            XCTAssertEqual(try Data(contentsOf: url), bytes, name)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType,
                           before[.protectionKey] as? FileProtectionType, name)
        }
    }

    @MainActor
    func testRejectedDraftSavesPreservePreviouslySavedBytes() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let game = UUID()
        let saves: [(String, (URL) throws -> Void, (URL) throws -> Void)] = [
            ("box-scores.json",
             { try BoxScoreStorage.save([PlayerBoxScore(gameID: game, playerID: "temporary-save", values: ["points": 0])], to: $0) },
             { try BoxScoreStorage.save([PlayerBoxScore(gameID: game, playerID: "temporary-save", values: ["points": -1])], to: $0) }),
            ("possessions.json",
             { try PossessionStorage.save([PossessionRecord(id: UUID(), gameID: game, team: .ours, number: 1, values: [:], turnover: nil)], to: $0) },
             { try PossessionStorage.save([PossessionRecord(id: UUID(), gameID: game, team: .ours, number: 0, values: [:], turnover: nil)], to: $0) }),
            ("player-paint-touches.json",
             { try PlayerPaintTouchStorage.save([PlayerPaintTouchRecord(gameID: game, playerID: "temporary-save", total: nil)], to: $0) },
             { try PlayerPaintTouchStorage.save([PlayerPaintTouchRecord(gameID: game, playerID: "temporary-save", total: -1)], to: $0) })
        ]
        for (name, saveValid, saveInvalid) in saves {
            let url = folder.appendingPathComponent(name)
            try saveValid(url)
            let bytes = try Data(contentsOf: url)
            XCTAssertThrowsError(try saveInvalid(url), name)
            XCTAssertEqual(try Data(contentsOf: url), bytes, name)
        }
    }

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
