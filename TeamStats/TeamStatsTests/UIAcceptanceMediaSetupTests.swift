import XCTest
import Foundation
@testable import TeamStats

/// Prepares the isolated full app's default cache through actual authorized retrieval.
/// This is setup evidence, not proof of rendered Keep controls or offline startup.
@MainActor
final class UIAcceptanceMediaSetupTests: XCTestCase {
    func testRetainExistingApprovedLocalClipForRenderedAcceptance() async throws {
        guard let text = ProcessInfo.processInfo.environment["TEAMSTATS_UI_MEDIA_FIXTURE"] else {
            throw XCTSkip("Explicit synthetic media setup fixture is not configured")
        }
        guard Bundle.main.bundleIdentifier == "com.narayanlekhi.TeamStats.UIAcceptance" else {
            throw UIAcceptanceMediaIssue.unsafeHost
        }
        let fixture = try JSONDecoder().decode(UIAcceptanceMediaFixture.self, from: Data(text.utf8))
        guard fixture.publishedClipTitle.hasPrefix("TEST ONLY") else {
            throw UIAcceptanceMediaIssue.unsafeFixture
        }
        let account = BackendAccount()
        await account.restoreIfNeeded()
        guard account.issue == nil, account.verifiedUserID == fixture.syntheticActorUUID,
              account.offlineClipActorID == fixture.syntheticActorUUID,
              let configuration = account.configuration,
              configuration.environment == .localTest,
              configuration.url.host == "127.0.0.1", configuration.url.scheme == "http" else {
            throw UIAcceptanceMediaIssue.unverifiedAccount
        }
        _ = try await account.authenticatedClient()
        let model = PrivateFiles(teamID: fixture.syntheticTeamID, kind: .practice,
            targetID: fixture.syntheticPlayID, account: account)
        await model.load()
        guard model.didLoad, model.issue == nil, !model.contentConcealed,
              model.access?.userID == fixture.syntheticActorUUID,
              let version = model.published.first(where: { $0.id == fixture.publishedClipVersionID }),
              version.teamID == fixture.syntheticTeamID,
              version.title == fixture.publishedClipTitle, version.status == .published,
              let count = version.byteCount, count > 0,
              let digest = version.sha256, !digest.isEmpty,
              let scope = model.clipScope else {
            throw UIAcceptanceMediaIssue.publishedClipUnavailable
        }
        let expectedScope = ClipScope(projectURL: configuration.url,
            actorID: fixture.syntheticActorUUID, teamID: fixture.syntheticTeamID)
        guard scope == expectedScope else { throw UIAcceptanceMediaIssue.invalidIdentity }
        let cache = ClipRetention()
        let priorIDs = Set(try cache.items(scope: scope, actorID: fixture.syntheticActorUUID).map(\.versionID))
        let hadVerifiedCache = try cache.cachedURL(scope: scope, versionID: version.id,
            actorID: fixture.syntheticActorUUID, requireRetained: false,
            expectedCount: count, expectedSHA256: digest) != nil
        guard let retrieved = await model.retrieve(version, keepOnDevice: true), model.issue == nil else {
            throw UIAcceptanceMediaIssue.authorizedRetrievalFailed
        }
        let clips = try model.retainedClips()
        let allRetained = try cache.items(scope: scope, actorID: fixture.syntheticActorUUID)
        let matches = clips.filter { $0.versionID == version.id }
        guard matches.count == 1, let retained = matches.first,
              retained.targetID == fixture.syntheticPlayID, retained.title == fixture.publishedClipTitle,
              retained.keepOnDevice, !retained.denied, retained.byteCount == count,
              retained.sha256 == digest,
              priorIDs.isSubset(of: Set(allRetained.map(\.versionID))),
              let cached = try model.offlineURL(retained), cached == retrieved else {
            throw UIAcceptanceMediaIssue.retentionFailed
        }
        let bytes = try boundedBytes(cached, maximum: PrivateFileKind.practice.maximumBytes)
        guard bytes.count == count, clipDigest(bytes) == digest else {
            throw UIAcceptanceMediaIssue.integrityFailed
        }
        XCTContext.runActivity(named: hadVerifiedCache
            ? "Verified cached clip retained after actual server authorization"
            : "Authorized clip retrieved and retained in the isolated full app cache") { _ in }
        // Keep bytes and verified account state for subsequent rendered/offline checks.
    }
}

private struct UIAcceptanceMediaFixture: Decodable {
    let syntheticActorUUID: UUID
    let syntheticTeamID: UUID
    let syntheticPlayID: UUID
    let publishedClipVersionID: UUID
    let publishedClipTitle: String
}
private enum UIAcceptanceMediaIssue: Error {
    case unsafeHost, unsafeFixture, unverifiedAccount, publishedClipUnavailable
    case invalidIdentity, authorizedRetrievalFailed, retentionFailed, integrityFailed
}
