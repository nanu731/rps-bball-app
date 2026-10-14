import Foundation

// A read-only copy of saved local drafts. It has no upload or restore behavior.
struct LocalDraftBackup: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let games: [Game]
    let boxScores: [PlayerBoxScore]
    let possessions: [PossessionRecord]
    let playerPaintTouches: [PlayerPaintTouchRecord]

    private init(games: [Game], boxScores: [PlayerBoxScore],
                 possessions: [PossessionRecord], playerPaintTouches: [PlayerPaintTouchRecord]) {
        schemaVersion = 1
        exportedAt = Date()
        self.games = games
        self.boxScores = boxScores
        self.possessions = possessions
        self.playerPaintTouches = playerPaintTouches
    }

    static func snapshot() throws -> LocalDraftBackup {
        let folder = try FileManager.default.url(for: .applicationSupportDirectory,
                                                in: .userDomainMask,
                                                appropriateFor: nil, create: false)
        return try snapshot(from: folder)
    }

    static func snapshot(from folder: URL) throws -> LocalDraftBackup {
        // An explicit allowlist excludes sessions/configuration, shared caches and clip bytes.
        // Every loader validates its complete store; any error aborts the entire backup.
        let games = try GameStorage.load(from: folder.appendingPathComponent("games.json"))
        let boxScores = try BoxScoreStorage.load(from: folder.appendingPathComponent("box-scores.json"))
        let possessions = try PossessionStorage.load(from: folder.appendingPathComponent("possessions.json"))
        let playerPaintTouches = try PlayerPaintTouchStorage.load(
            from: folder.appendingPathComponent("player-paint-touches.json"))
        return LocalDraftBackup(games: games, boxScores: boxScores,
                                possessions: possessions, playerPaintTouches: playerPaintTouches)
    }

    func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
