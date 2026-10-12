import XCTest
import Foundation
import CryptoKit
@testable import TeamStats

final class ClipRetentionTests: XCTestCase {
    let actor = UUID(uuidString: "a1000000-0000-4000-8000-000000000001")!
    let team = UUID(uuidString: "a2000000-0000-4000-8000-000000000001")!
    let version = UUID(uuidString: "a3000000-0000-4000-8000-000000000001")!
    let target = UUID(uuidString: "a4000000-0000-4000-8000-000000000001")!
    func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    func scope() -> ClipScope { ClipScope(projectURL: URL(string: "https://synthetic.invalid")!, actorID: actor, teamID: team) }
    let bytes = Data("TEST ONLY retained clip bytes".utf8)
    var digest: String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    func store(_ cache: ClipRetention) throws -> URL {
        try cache.store(bytes, scope: scope(), versionID: version, targetID: target, title: "TEST ONLY CLIP",
            expectedCount: bytes.count, expectedSHA256: digest, keepOnDevice: true)
    }
    func testUnverifiableCopyIsPreservedWhenFreshValidatedBytesRepairTheVersion() throws {
        let root = try directory(), cache = ClipRetention(root: root), old = try store(cache)
        let corrupt = Data("TEST ONLY damaged copy".utf8); try corrupt.write(to: old)
        XCTAssertThrowsError(try cache.cachedURL(scope: scope(), versionID: version, actorID: actor, requireRetained: true))
        let repaired = try store(cache)
        XCTAssertNotEqual(repaired, old); XCTAssertEqual(try Data(contentsOf: old), corrupt)
        XCTAssertEqual(try Data(contentsOf: repaired), bytes)
        XCTAssertEqual(try cache.items(scope: scope(), actorID: actor).count, 1)
    }

    func testKnownDenialPersistsWhileExistingFileRemainsUntouched() throws {
        let root = try directory(), cache = ClipRetention(root: root), url = try store(cache)
        try cache.recordDenial(scope: scope())
        XCTAssertTrue(try cache.items(scope: scope(), actorID: actor).isEmpty)
        XCTAssertThrowsError(try cache.cachedURL(scope: scope(), versionID: version, actorID: actor, requireRetained: true))
        XCTAssertTrue(try ClipRetention(root: root).items(scope: scope(), actorID: actor).isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        try cache.confirmMembership(scope: scope())
        XCTAssertEqual(try cache.cachedURL(scope: scope(), versionID: version, actorID: actor, requireRetained: true), url)
    }
    func testInsufficientSpaceAndWrongIntegrityCannotCreatePlayableCopy() throws {
        let root = try directory(), cache = ClipRetention(root: root, availableBytes: { 0 })
        XCTAssertThrowsError(try store(cache)) { XCTAssertEqual($0 as? ClipRetentionIssue, .insufficientSpace) }
        XCTAssertTrue(try cache.items(scope: scope(), actorID: actor).isEmpty)
        XCTAssertThrowsError(try ClipRetention(root: root).store(bytes, scope: scope(), versionID: version, targetID: target,
            title: "TEST ONLY", expectedCount: bytes.count, expectedSHA256: String(repeating: "0", count: 64), keepOnDevice: true))
    }
    func testOfflineCatalogDiscoversOnlyThisProjectActorAndRetainedScopes() throws {
        let root = try directory(), cache = ClipRetention(root: root)
        _ = try store(cache)
        XCTAssertEqual(try cache.scopes(projectURL: URL(string: "https://synthetic.invalid")!, actorID: actor), [scope()])
        XCTAssertTrue(try cache.scopes(projectURL: URL(string: "https://other.invalid")!, actorID: actor).isEmpty)
        try cache.recordDenial(scope: scope())
        XCTAssertTrue(try cache.scopes(projectURL: URL(string: "https://synthetic.invalid")!, actorID: actor).isEmpty)
    }

    func testRetainedClipSurvivesRestartAndAccountProjectTeamScopesStaySeparate() throws {
        let root = try directory(), cache = ClipRetention(root: root)
        let url = try store(cache)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        let restarted = ClipRetention(root: root)
        XCTAssertEqual(try restarted.items(scope: scope(), actorID: actor).map(\.versionID), [version])
        XCTAssertEqual(try restarted.cachedURL(scope: scope(), versionID: version, actorID: actor, requireRetained: true), url)
        let other = UUID(uuidString: "a1000000-0000-4000-8000-000000000002")!
        XCTAssertTrue(try restarted.items(scope: scope(), actorID: other).isEmpty)
        XCTAssertTrue(try restarted.items(scope: ClipScope(projectURL: URL(string: "https://other.invalid")!, actorID: actor, teamID: team), actorID: actor).isEmpty)
        XCTAssertTrue(try restarted.items(scope: ClipScope(projectURL: URL(string: "https://synthetic.invalid")!, actorID: actor, teamID: other), actorID: actor).isEmpty)
    }
}
