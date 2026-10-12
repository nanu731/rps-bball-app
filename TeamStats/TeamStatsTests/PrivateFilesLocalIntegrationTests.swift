import XCTest
import Foundation
import Supabase
import AVFoundation
@testable import TeamStats

@MainActor
final class PrivateFilesLocalIntegrationTests: XCTestCase {
    // This verifies the retained-file/player pipeline across test-host processes.
    // It does not establish current Auth, team rights, or rendered offline app UI.
    func testPreviouslyVerifiedClipPlaysAcrossSeparateOfflineProcesses() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let fixturePath = environment["TEAMSTATS_PRIVATE_FILES_FIXTURE"],
              let markerPath = environment["TEAMSTATS_OFFLINE_PROCESS_MARKER"],
              let phase = environment["TEAMSTATS_OFFLINE_PROCESS_PHASE"] else {
            throw XCTSkip("Explicit prior-verified clip/process fixture is not configured")
        }
        guard phase == "first" || phase == "second" else { XCTFail("Unknown test process phase"); return }
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: fixturePath))) as? [String: Any])
        let project = try XCTUnwrap(URL(string: XCTUnwrap(object["apiRoot"] as? String)))
        XCTAssertTrue(["127.0.0.1", "localhost", "::1"].contains(project.host ?? ""))
        let saved = try AuthClient.Configuration.jsonDecoder.decode(Session.self,
            from: JSONSerialization.data(withJSONObject: XCTUnwrap(object["session"])))
        let team = try XCTUnwrap(UUID(uuidString: XCTUnwrap(object["syntheticTeamID"] as? String)))
        let play = try XCTUnwrap(UUID(uuidString: XCTUnwrap(object["syntheticPlayID"] as? String)))
        let scope = ClipScope(projectURL: project, actorID: saved.user.id, teamID: team)
        let marker = URL(fileURLWithPath: markerPath), pid = ProcessInfo.processInfo.processIdentifier
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL
        func relativePath(_ url: URL) throws -> String {
            let path = url.standardizedFileURL.path, prefix = home.path + "/"
            guard path.hasPrefix(prefix) else { throw ClipRetentionIssue.storage }
            return String(path.dropFirst(prefix.count))
        }
        var receipt: OfflineClipProcessReceipt
        OfflineClipNetworkFence.reset()
        XCTAssertTrue(URLProtocol.registerClass(OfflineClipNetworkFence.self))
        defer { URLProtocol.unregisterClass(OfflineClipNetworkFence.self) }
        if phase == "first" {
            guard !FileManager.default.fileExists(atPath: marker.path) else { XCTFail("Use a fresh owned process-proof marker"); return }
            let candidates = try FileManager.default.contentsOfDirectory(at: FileManager.default.temporaryDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]).filter {
                    $0.lastPathComponent.hasPrefix("TEST-ONLY-CLIPS-")
                }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            var found: OfflineClipProcessReceipt?
            for candidate in candidates {
                let values = try candidate.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
                let cache = ClipRetention(root: candidate)
                guard let clip = try cache.items(scope: scope, actorID: saved.user.id).first(where: {
                    $0.targetID == play && $0.title == "TEST ONLY NATIVE PRIVATE CLIP"
                }), let url = try cache.cachedURL(scope: scope, versionID: clip.versionID, actorID: saved.user.id,
                    requireRetained: true, expectedCount: clip.byteCount, expectedSHA256: clip.sha256) else { continue }
                found = OfflineClipProcessReceipt(firstPID: pid, secondPID: nil, cacheRoot: candidate.path,
                    clipURL: url.path, secondClipURL: nil, cacheRelativePath: try relativePath(candidate),
                    clipRelativePath: try relativePath(url), scope: scope, versionID: clip.versionID,
                    byteCount: clip.byteCount, sha256: clip.sha256)
                break
            }
            receipt = try XCTUnwrap(found, "No previously downloaded verified test clip; do not automatically transfer")
        } else {
            receipt = try JSONDecoder().decode(OfflineClipProcessReceipt.self, from: Data(contentsOf: marker))
            XCTAssertNotEqual(pid, receipt.firstPID)
            XCTAssertNil(receipt.secondPID)
            XCTAssertEqual(receipt.scope, scope)
            XCTAssertTrue(URL(fileURLWithPath: receipt.cacheRoot).lastPathComponent.hasPrefix("TEST-ONLY-CLIPS-"))
            receipt.secondPID = pid
        }
        // Xcode may relocate the simulator app container while reinstalling its host.
        // Bind to the same retained path inside the current container, not a stale absolute base.
        guard receipt.cacheRelativePath.hasPrefix("tmp/TEST-ONLY-CLIPS-"),
              !receipt.cacheRelativePath.split(separator: "/").contains(".."),
              receipt.clipRelativePath.hasPrefix(receipt.cacheRelativePath + "/") else {
            XCTFail("The proof must reference only this owned test-cache subtree"); return
        }
        let cache = ClipRetention(root: home.appendingPathComponent(receipt.cacheRelativePath))
        let url = try XCTUnwrap(cache.cachedURL(scope: scope, versionID: receipt.versionID, actorID: saved.user.id,
            requireRetained: true, expectedCount: receipt.byteCount, expectedSHA256: receipt.sha256))
        XCTAssertEqual(try relativePath(url), receipt.clipRelativePath)
        if phase == "second" { receipt.secondClipURL = url.path }
        else { XCTAssertEqual(url.path, receipt.clipURL) }
        let bytes = try boundedBytes(url, maximum: 10 * 1024 * 1024)
        XCTAssertEqual(bytes.count, receipt.byteCount); XCTAssertEqual(clipDigest(bytes), receipt.sha256)
        let asset = AVURLAsset(url: url, options: [AVURLAssetReferenceRestrictionsKey: AVAssetReferenceRestrictions.forbidAll.rawValue])
        let item = AVPlayerItem(asset: asset), player = AVPlayer(playerItem: item)
        let readyDeadline = Date().addingTimeInterval(10)
        while item.status == .unknown && Date() < readyDeadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(item.status.rawValue, AVPlayerItem.Status.readyToPlay.rawValue)
        let duration = try await asset.load(.duration).seconds
        XCTAssertGreaterThan(duration, 0); XCTAssertLessThanOrEqual(duration, 30)
        player.play()
        let playbackDeadline = Date().addingTimeInterval(5)
        while player.currentTime().seconds < 0.05 && Date() < playbackDeadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertGreaterThan(player.currentTime().seconds, 0.05); player.pause()
        XCTAssertEqual(OfflineClipNetworkFence.requestCount, 0)
        try JSONEncoder().encode(receipt).write(to: marker, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
    }

    func testActualLocalPrivateClipLifecycleDeliveryAndRestartRetention() async throws {
        guard let fixturePath = ProcessInfo.processInfo.environment["TEAMSTATS_PRIVATE_FILES_FIXTURE"],
              let clipPath = ProcessInfo.processInfo.environment["TEAMSTATS_PRIVATE_CLIP_FIXTURE"] else {
            throw XCTSkip("Explicit synthetic loopback file fixture is not configured")
        }
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: fixturePath))) as? [String: Any])
        let root = try XCTUnwrap(object["apiRoot"] as? String)
        let key = try XCTUnwrap(object["publishableKey"] as? String)
        let configuration = try AccountConfiguration(url: root, publicKey: key, environment: .localTest)
        XCTAssertTrue(["127.0.0.1", "localhost", "::1"].contains(configuration.url.host ?? ""))
        let sessionData = try JSONSerialization.data(withJSONObject: XCTUnwrap(object["session"]))
        let verifiedSession = try AuthClient.Configuration.jsonDecoder.decode(Session.self, from: sessionData)
        let actor = verifiedSession.user.id
        let team = try XCTUnwrap(UUID(uuidString: XCTUnwrap(object["syntheticTeamID"] as? String)))
        let play = try XCTUnwrap(UUID(uuidString: XCTUnwrap(object["syntheticPlayID"] as? String)))
        let storage = NativeFileFixtureStorage()
        try storage.store(key: "synthetic-files-session", value: sessionData)
        let client = SupabaseClient(supabaseURL: configuration.url, supabaseKey: key,
            options: .init(auth: .init(storage: storage, storageKey: "synthetic-files-session", autoRefreshToken: false), global: .init(logger: nil)))
        let cacheRoot = FileManager.default.temporaryDirectory.appendingPathComponent("TEST-ONLY-CLIPS-" + UUID().uuidString)
        let retention = ClipRetention(root: cacheRoot)
        let model = PrivateFiles(teamID: team, kind: .practice, targetID: play, configuration: configuration,
            authenticatedClient: {
                let session = try await client.auth.session
                let user = try await client.auth.user(jwt: session.accessToken)
                guard user.id == actor, !user.isAnonymous else { throw AccountIssue.noVerifiedSession }
                return client
            }, offlineActor: { actor }, retention: retention)
        await model.load()
        XCTAssertTrue(model.didLoad); XCTAssertNil(model.issue)
        // Only this synthetic fixture's prior uncertain uploads are reconciled;
        // no body is repeated and prior versions/allocations remain preserved.
        let priorUploads = model.ownDrafts.filter {
            $0.status == .uploading && $0.authorUserID == actor && $0.title == "TEST ONLY NATIVE PRIVATE CLIP"
        }
        for prior in priorUploads {
            let receipt = await model.reconcile(prior)
            if receipt == nil { XCTAssertEqual(model.issue, .missingUpload) }
            else { XCTAssertEqual(receipt?.id, prior.id); XCTAssertEqual(receipt?.status, .ready) }
            guard receipt != nil || model.issue == .missingUpload else { return }
        }
        if !priorUploads.isEmpty {
            await model.load()
            XCTAssertTrue(model.didLoad); XCTAssertNil(model.issue)
            for prior in priorUploads {
                let preserved = try XCTUnwrap(model.versions.first { $0.id == prior.id })
                XCTAssertEqual(model.versions.filter { $0.id == prior.id }.count, 1)
                XCTAssertEqual(preserved.operationID, prior.operationID)
                XCTAssertEqual(preserved.resourceID, prior.resourceID)
            }
        }
        let bytes = try boundedBytes(URL(fileURLWithPath: clipPath), maximum: 10 * 1024 * 1024)
        var input = PrivateFileInput(); input.title = "TEST ONLY NATIVE PRIVATE CLIP"
        let reservation = await model.reserve(data: bytes, input: input)
        XCTAssertNotNil(reservation, model.issue?.message ?? "No server reservation")
        for prior in priorUploads { XCTAssertNotEqual(reservation?.operationID, prior.operationID) }
        let stored = await model.upload()
        XCTAssertNotNil(stored, model.issue?.message ?? "No validated stored receipt")
        guard let stored else { return }
        XCTAssertEqual(stored.status, .ready)
        input.notes = "TEST ONLY edited metadata"
        let edited = await model.save(stored, input: input)
        XCTAssertNotNil(edited, model.issue?.message ?? "No saved revision")
        guard let edited else { return }
        XCTAssertEqual(edited.id, stored.id); XCTAssertGreaterThan(edited.revision, stored.revision)
        let published = await model.transition(edited, action: .publish)
        XCTAssertNotNil(published, model.issue?.message ?? "No publication")
        guard let published else { return }
        await model.load()
        XCTAssertEqual(model.versions.filter { $0.id == published.id }.count, 1)
        let first = await model.retrieve(published, keepOnDevice: true)
        XCTAssertNotNil(first, model.issue?.message ?? "No complete body")
        guard let first else { return }
        XCTAssertEqual(try Data(contentsOf: first), bytes)
        let asset = AVURLAsset(url: first, options: [AVURLAssetReferenceRestrictionsKey: AVAssetReferenceRestrictions.forbidAll.rawValue])
        let playerItem = AVPlayerItem(asset: asset), player = AVPlayer()
        player.replaceCurrentItem(with: playerItem)
        let readyDeadline = Date().addingTimeInterval(10)
        while playerItem.status == .unknown && Date() < readyDeadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(playerItem.status.rawValue, AVPlayerItem.Status.readyToPlay.rawValue)
        let duration = try await asset.load(.duration).seconds
        XCTAssertGreaterThan(duration, 0); XCTAssertLessThanOrEqual(duration, 30)
        player.play()
        let playbackDeadline = Date().addingTimeInterval(5)
        while player.currentTime().seconds < 0.05 && Date() < playbackDeadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertGreaterThan(player.currentTime().seconds, 0.05)
        player.pause()
        let second = await model.retrieve(published, keepOnDevice: true)
        XCTAssertEqual(second, first)
        let scope = ClipScope(projectURL: configuration.url, actorID: actor, teamID: team)
        let restarted = ClipRetention(root: cacheRoot)
        XCTAssertEqual(try restarted.items(scope: scope, actorID: actor).filter { $0.versionID == published.id }.count, 1)
        XCTAssertEqual(try restarted.cachedURL(scope: scope, versionID: published.id, actorID: actor, requireRetained: true), first)
        // Synthetic backend/files are deliberately preserved for inspection; no cleanup command.
    }
}
private final class NativeFileFixtureStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock(); private var values: [String: Data] = [:]
    func store(key: String, value: Data) throws { lock.withLock { values[key] = value } }
    func retrieve(key: String) throws -> Data? { lock.withLock { values[key] } }
    func remove(key: String) throws { lock.withLock { values[key] = nil } }
}

nonisolated private struct OfflineClipProcessReceipt: Codable {
    let firstPID: Int32
    var secondPID: Int32?
    let cacheRoot: String
    let clipURL: String
    var secondClipURL: String?
    let cacheRelativePath: String
    let clipRelativePath: String
    let scope: ClipScope
    let versionID: UUID
    let byteCount: Int
    let sha256: String
}
nonisolated private final class OfflineClipNetworkFence: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var count = 0
    static var requestCount: Int { lock.withLock { count } }
    static func reset() { lock.withLock { count = 0 } }
    override class func canInit(with request: URLRequest) -> Bool { ["http", "https"].contains(request.url?.scheme ?? "") }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.withLock { Self.count += 1 }
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
