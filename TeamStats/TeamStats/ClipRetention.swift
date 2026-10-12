import Foundation
import CryptoKit

/// A local identity namespace, never authority for a remote command.
nonisolated struct ClipScope: Codable, Equatable, Sendable {
    let project: String
    let actorID: UUID
    let teamID: UUID
    init(projectURL: URL, actorID: UUID, teamID: UUID) {
        project = clipDigest(Data(projectURL.absoluteString.utf8))
        self.actorID = actorID; self.teamID = teamID
    }
}
nonisolated struct RetainedClip: Codable, Identifiable, Sendable {
    let versionID: UUID
    let targetID: UUID
    let title: String
    let byteCount: Int
    let sha256: String
    var fileID: UUID? = nil
    var keepOnDevice: Bool
    var denied: Bool
    var id: UUID { versionID }
}
nonisolated enum ClipRetentionIssue: Error, Equatable {
    case locked, integrity, storage, insufficientSpace
    var message: String {
        switch self {
        case .locked: "This device copy is locked for the current account or known access restriction. Files are preserved."
        case .integrity: "The device copy could not be verified. Its file is preserved; retrieve a new authorized copy before playback."
        case .storage: "Device clip storage is unavailable. Existing copies are preserved."
        case .insufficientSpace: "There is not enough free device space for this clip. Existing copies are preserved."
        }
    }
}
nonisolated private struct ClipManifest: Codable {
    var scope: ClipScope?
    var entries: [RetainedClip] = []
    var scopeDenied = false
}
/// Immutable files plus one atomic manifest. No eviction, deletion or automatic transfer.
/// Callers supply only an Auth-verified actor (or the private last-verified offline stamp).
nonisolated final class ClipRetention: @unchecked Sendable {
    private let root: URL
    private let availableBytes: @Sendable () throws -> Int64
    private let lock = NSLock()
    init(root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RetainedClips"),
         availableBytes: (@Sendable () throws -> Int64)? = nil) {
        self.root = root
        self.availableBytes = availableBytes ?? {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            return (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        }
    }
    func scopes(projectURL: URL, actorID: UUID) throws -> [ClipScope] {
        try lock.withLock {
            let probe = ClipScope(projectURL: projectURL, actorID: actorID, teamID: UUID())
            let actorFolder = root.appendingPathComponent(probe.project).appendingPathComponent(actorID.uuidString)
            guard FileManager.default.fileExists(atPath: actorFolder.path) else { return [] }
            do {
                let folders = try FileManager.default.contentsOfDirectory(at: actorFolder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                var result: [ClipScope] = []
                for folder in folders {
                    guard let teamID = UUID(uuidString: folder.lastPathComponent), folder.lastPathComponent == teamID.uuidString else { continue }
                    let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    guard values.isDirectory == true, values.isSymbolicLink != true else { throw ClipRetentionIssue.storage }
                    let scope = ClipScope(projectURL: projectURL, actorID: actorID, teamID: teamID), manifest = try read(scope)
                    if !manifest.scopeDenied && manifest.entries.contains(where: { $0.keepOnDevice && !$0.denied }) { result.append(scope) }
                }
                return result.sorted { $0.teamID.uuidString < $1.teamID.uuidString }
            } catch { throw ClipRetentionIssue.storage }
        }
    }
    func items(scope: ClipScope, actorID: UUID?) throws -> [RetainedClip] {
        try lock.withLock {
            guard actorID == scope.actorID else { return [] }
            let manifest = try read(scope)
            guard !manifest.scopeDenied else { return [] }
            return manifest.entries.filter { $0.keepOnDevice && !$0.denied }
        }
    }
    func cachedURL(scope: ClipScope, versionID: UUID, actorID: UUID?, requireRetained: Bool, expectedCount: Int? = nil, expectedSHA256: String? = nil) throws -> URL? {
        try lock.withLock {
            guard actorID == scope.actorID else { throw ClipRetentionIssue.locked }
            let manifest = try read(scope)
            guard !manifest.scopeDenied else { throw ClipRetentionIssue.locked }
            guard let item = manifest.entries.first(where: { $0.versionID == versionID }) else { return nil }
            guard !item.denied else { throw ClipRetentionIssue.locked }
            guard expectedCount == nil || expectedCount == item.byteCount,
                  expectedSHA256 == nil || expectedSHA256 == item.sha256 else { throw ClipRetentionIssue.integrity }
            guard !requireRetained || item.keepOnDevice else { return nil }
            let url = directory(scope).appendingPathComponent((item.fileID ?? versionID).uuidString + ".mp4")
            let bytes = try boundedBytes(url, maximum: 10 * 1024 * 1024)
            guard bytes.count == item.byteCount, clipDigest(bytes) == item.sha256 else { throw ClipRetentionIssue.integrity }
            return url
        }
    }
    /// Only call with a currently authorized published practice clip's complete verified body.
    @discardableResult
    func store(_ bytes: Data, scope: ClipScope, versionID: UUID, targetID: UUID, title: String,
               expectedCount: Int, expectedSHA256: String, keepOnDevice: Bool) throws -> URL {
        try lock.withLock {
            guard expectedCount > 0, expectedCount <= 10 * 1024 * 1024, bytes.count == expectedCount,
                  clipDigest(bytes) == expectedSHA256 else { throw ClipRetentionIssue.integrity }
            var manifest = try read(scope)
            let folder = directory(scope)
            var fileID = manifest.entries.first(where: { $0.versionID == versionID })?.fileID
            var url = folder.appendingPathComponent((fileID ?? versionID).uuidString + ".mp4")
            var needsWrite = !FileManager.default.fileExists(atPath: url.path)
            if !needsWrite {
                let existing = try? boundedBytes(url, maximum: expectedCount)
                if existing != bytes {
                    // Preserve an unverifiable old copy; a new immutable file repairs this version.
                    fileID = UUID(); url = folder.appendingPathComponent(fileID!.uuidString + ".mp4"); needsWrite = true
                }
            }
            if needsWrite {
                // Allow the complete body, atomic staging and a small manifest reserve.
                guard try availableBytes() >= Int64(expectedCount) * 2 + 65_536 else { throw ClipRetentionIssue.insufficientSpace }
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    try bytes.write(to: url, options: .atomic)
                    try protect(url)
                } catch { throw ClipRetentionIssue.storage }
            }
            let kept = keepOnDevice || manifest.entries.first(where: { $0.versionID == versionID })?.keepOnDevice == true
            manifest.entries.removeAll { $0.versionID == versionID }
            manifest.entries.append(RetainedClip(versionID: versionID, targetID: targetID, title: title,
                byteCount: expectedCount, sha256: expectedSHA256, fileID: fileID, keepOnDevice: kept, denied: false))
            manifest.scopeDenied = false
            try write(manifest, scope)
            return url
        }
    }
    func keep(scope: ClipScope, versionID: UUID, actorID: UUID?) throws {
        try lock.withLock {
            guard actorID == scope.actorID else { throw ClipRetentionIssue.locked }
            var manifest = try read(scope)
            guard !manifest.scopeDenied, let index = manifest.entries.firstIndex(where: { $0.versionID == versionID }), !manifest.entries[index].denied else { throw ClipRetentionIssue.locked }
            manifest.entries[index].keepOnDevice = true
            try write(manifest, scope)
        }
    }
    func recordDenial(scope: ClipScope, versionID: UUID? = nil) throws {
        try lock.withLock {
            var manifest = try read(scope)
            if let versionID {
                for index in manifest.entries.indices where manifest.entries[index].versionID == versionID { manifest.entries[index].denied = true }
            } else { manifest.scopeDenied = true }
            try write(manifest, scope)
        }
    }
    // A version may be unlocked only after its current published visibility was rechecked.
    func confirmMembership(scope: ClipScope, visibleVersionID: UUID? = nil) throws {
        try lock.withLock {
            var manifest = try read(scope); manifest.scopeDenied = false
            if let visibleVersionID {
                for index in manifest.entries.indices where manifest.entries[index].versionID == visibleVersionID {
                    manifest.entries[index].denied = false
                }
            }
            try write(manifest, scope)
        }
    }
    private func directory(_ scope: ClipScope) -> URL {
        root.appendingPathComponent(scope.project).appendingPathComponent(scope.actorID.uuidString).appendingPathComponent(scope.teamID.uuidString)
    }
    private func read(_ scope: ClipScope) throws -> ClipManifest {
        let url = directory(scope).appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return ClipManifest() }
        do {
            let bytes = try boundedBytes(url, maximum: 1024 * 1024)
            let manifest = try JSONDecoder().decode(ClipManifest.self, from: bytes)
            guard manifest.scope == scope, Set(manifest.entries.map(\.versionID)).count == manifest.entries.count,
                manifest.entries.allSatisfy({ $0.byteCount > 0 && $0.byteCount <= 10 * 1024 * 1024 && $0.sha256.count == 64 }) else { throw ClipRetentionIssue.storage }
            return manifest
        } catch { throw ClipRetentionIssue.storage }
    }
    private func write(_ manifest: ClipManifest, _ scope: ClipScope) throws {
        do {
            let folder = directory(scope)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            var manifest = manifest; manifest.scope = scope
            let bytes = try JSONEncoder().encode(manifest)
            guard bytes.count <= 1024 * 1024 else { throw ClipRetentionIssue.storage }
            let url = folder.appendingPathComponent("manifest.json")
            try bytes.write(to: url, options: .atomic); try protect(url)
        } catch { throw ClipRetentionIssue.storage }
    }
    private func protect(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        #endif
    }
}
nonisolated func clipDigest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
nonisolated func boundedBytes(_ url: URL, maximum: Int) throws -> Data {
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize, size >= 0, size <= maximum else { throw ClipRetentionIssue.integrity }
    let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
    let bytes = try handle.read(upToCount: maximum + 1) ?? Data()
    guard bytes.count == size, bytes.count <= maximum else { throw ClipRetentionIssue.integrity }
    return bytes
}
