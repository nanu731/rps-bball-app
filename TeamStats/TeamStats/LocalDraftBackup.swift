import Foundation

// A copy of saved local drafts. Recovery tooling has no automatic import or upload.
struct LocalDraftBackup: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let games: [Game]
    let boxScores: [PlayerBoxScore]
    let possessions: [PossessionRecord]
    let playerPaintTouches: [PlayerPaintTouchRecord]
    let shotCaptures: [ShotCaptureDocument]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, exportedAt, games, boxScores, possessions, playerPaintTouches, shotCaptures
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == 1 || schemaVersion == 2 else { throw CocoaError(.coderReadCorrupt) }
        exportedAt = try values.decode(Date.self, forKey: .exportedAt)
        games = try values.decode([Game].self, forKey: .games)
        boxScores = try values.decode([PlayerBoxScore].self, forKey: .boxScores)
        possessions = try values.decode([PossessionRecord].self, forKey: .possessions)
        playerPaintTouches = try values.decode([PlayerPaintTouchRecord].self, forKey: .playerPaintTouches)
        if schemaVersion == 1 {
            guard !values.contains(.shotCaptures) else { throw CocoaError(.coderReadCorrupt) }
            shotCaptures = []
        } else {
            shotCaptures = try values.decode([ShotCaptureDocument].self, forKey: .shotCaptures)
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(exportedAt, forKey: .exportedAt)
        try values.encode(games, forKey: .games)
        try values.encode(boxScores, forKey: .boxScores)
        try values.encode(possessions, forKey: .possessions)
        try values.encode(playerPaintTouches, forKey: .playerPaintTouches)
        if schemaVersion == 2 { try values.encode(shotCaptures, forKey: .shotCaptures) }
    }

    private init(games: [Game], boxScores: [PlayerBoxScore],
                 possessions: [PossessionRecord], playerPaintTouches: [PlayerPaintTouchRecord],
                 shotCaptures: [ShotCaptureDocument]) {
        schemaVersion = 2
        exportedAt = Date()
        self.games = games
        self.boxScores = boxScores
        self.possessions = possessions
        self.playerPaintTouches = playerPaintTouches
        self.shotCaptures = shotCaptures
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
        let shotFiles = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("shot-local-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let shots = try shotFiles.map { url -> ShotCaptureDocument in
            let name = String(url.deletingPathExtension().lastPathComponent.dropFirst("shot-local-".count))
            guard let id = UUID(uuidString: name), url.lastPathComponent == shotFilename(id) else {
                throw ShotCaptureIssue.corrupt
            }
            return try ShotCaptureStorage.load(from: url, context: ShotCaptureContext(
                gameID: id, teamID: nil, actorID: nil, assignmentRevision: nil))
        }
        let backup = LocalDraftBackup(games: games, boxScores: boxScores,
            possessions: possessions, playerPaintTouches: playerPaintTouches, shotCaptures: shots)
        try backup.validateRelationships()
        return backup
    }

    func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    private static func shotFilename(_ gameID: UUID) -> String { "shot-local-\(gameID.uuidString).json" }

    private func validateRelationships() throws {
        let gameIDs = Set(games.map(\.id))
        guard boxScores.allSatisfy({ gameIDs.contains($0.gameID) }),
              possessions.allSatisfy({ gameIDs.contains($0.gameID) }),
              playerPaintTouches.allSatisfy({ gameIDs.contains($0.gameID) }),
              Set(shotCaptures.map { $0.context.gameID }).count == shotCaptures.count,
              Set(shotCaptures.map(\.id)).count == shotCaptures.count else { throw CocoaError(.coderReadCorrupt) }
        for document in shotCaptures {
            guard !document.context.isShared, gameIDs.contains(document.context.gameID) else { throw ShotCaptureIssue.corrupt }
            _ = try ShotCaptureStorage.encoded(document) // Same validation and per-journal bound as ordinary saving.
        }
    }

    // Offline recovery tooling only; no app navigation or automatic import calls this.
    static func restore(_ data: Data, toNewDirectory destination: URL) throws {
        let backup = try JSONDecoder().decode(Self.self, from: data)
        try backup.validateRelationships()
        let files = FileManager.default
        guard destination.isFileURL else { throw CocoaError(.fileWriteUnsupportedScheme) }
        guard !files.fileExists(atPath: destination.path),
              (try? files.destinationOfSymbolicLink(atPath: destination.path)) == nil else {
            throw CocoaError(.fileWriteFileExists)
        }
        // A sibling directory keeps all saved stores private until one rename publishes them.
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
        for document in backup.shotCaptures {
            try ShotCaptureStorage.create(document, at: staged.appendingPathComponent(shotFilename(document.context.gameID)))
        }
        for item in try files.contentsOfDirectory(at: staged, includingPropertiesForKeys: nil) {
            try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: item.path)
        }
        _ = try snapshot(from: staged)
        try files.moveItem(at: staged, to: destination)
    }
}
