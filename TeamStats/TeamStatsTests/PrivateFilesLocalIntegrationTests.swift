import XCTest
import Foundation
import Supabase
import AVFoundation
@testable import TeamStats

@MainActor
final class PrivateFilesLocalIntegrationTests: XCTestCase {
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
