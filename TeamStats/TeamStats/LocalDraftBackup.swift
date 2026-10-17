import Foundation

// A copy of saved local drafts. Recovery tooling has no automatic import or upload.
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

    // Offline recovery tooling only; no app navigation or automatic import calls this.
    static func restore(_ data: Data, toNewDirectory destination: URL) throws {
        let backup = try JSONDecoder().decode(Self.self, from: data)
        guard backup.schemaVersion == 1 else { throw CocoaError(.coderReadCorrupt) }
        let gameIDs = Set(backup.games.map(\.id))
        guard backup.boxScores.allSatisfy({ gameIDs.contains($0.gameID) }),
              backup.possessions.allSatisfy({ gameIDs.contains($0.gameID) }),
              backup.playerPaintTouches.allSatisfy({ gameIDs.contains($0.gameID) }) else {
            throw CocoaError(.coderReadCorrupt)
        }
        let files = FileManager.default
        guard destination.isFileURL else { throw CocoaError(.fileWriteUnsupportedScheme) }
        guard !files.fileExists(atPath: destination.path),
              (try? files.destinationOfSymbolicLink(atPath: destination.path)) == nil else {
            throw CocoaError(.fileWriteFileExists)
        }
        // A sibling directory keeps all four stores private until one rename publishes them.
        let staged = destination.deletingLastPathComponent()
            .appendingPathComponent(".teamstats-recovery-\(UUID().uuidString).partial", isDirectory: true)
        try files.createDirectory(at: staged, withIntermediateDirectories: false,
                                  attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: staged) } // Only this invocation's staging directory.
        try GameStorage.save(backup.games, to: staged.appendingPathComponent("games.json"))
        try BoxScoreStorage.save(backup.boxScores, to: staged.appendingPathComponent("box-scores.json"))
        try PossessionStorage.save(backup.possessions, to: staged.appendingPathComponent("possessions.json"))
        try PlayerPaintTouchStorage.save(backup.playerPaintTouches,
                                        to: staged.appendingPathComponent("player-paint-touches.json"))
        for item in try files.contentsOfDirectory(at: staged, includingPropertiesForKeys: nil) {
            try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: item.path)
        }
        _ = try snapshot(from: staged)
        try files.moveItem(at: staged, to: destination)
    }
}
