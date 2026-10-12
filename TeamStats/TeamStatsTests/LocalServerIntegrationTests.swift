import XCTest
import Foundation
import Supabase
@testable import TeamStats

/// Opt-in, synthetic loopback services only. A trusted generated test OTP proves
/// native SDK/session/RPC compatibility, not typed inbox or real SMS delivery.
@MainActor
final class LocalServerIntegrationTests: XCTestCase {
    func testDefaultEmailLinkWithRealLocalAuthAndDevicePKCE() async throws {
        guard let text = ProcessInfo.processInfo.environment["TEAMSTATS_LOCAL_TEST_FIXTURE"] else {
            throw XCTSkip("Isolated local server fixture is not configured.")
        }
        let fixture = try JSONDecoder().decode(LocalServerFixture.self, from: Data(text.utf8))
        guard let mail = fixture.mailpitURL, mail.host == "127.0.0.1", mail.scheme == "http",
              let api = URL(string: fixture.apiRoot), api.host == "127.0.0.1",
              fixture.syntheticEmail.hasSuffix("@example.invalid") else { throw LocalFixtureIssue.unsafeConfiguration }
        let email = "synthetic-native-signup-" + UUID().uuidString.lowercased() + "@example.invalid"
        let store = SecureSessionStorage(service: "TeamStats.local-email.tests." + UUID().uuidString)
        let account = BackendAccount(storage: store)
        await account.configure(url: fixture.apiRoot, publicKey: fixture.publishableKey, environment: .localTest)
        await account.requestCode(method: .email, identifier: email)
        XCTAssertNil(account.issue)
        XCTAssertEqual(account.pendingMethod, .email)
        var messageID: String?
        for _ in 0..<10 {
            let (bytes, response) = try await URLSession.shared.data(from: mail.appendingPathComponent("api/v1/messages"))
            guard (response as? HTTPURLResponse)?.statusCode == 200, bytes.count < 1_048_576 else { throw LocalFixtureIssue.unavailable }
            let list = try JSONDecoder().decode(LocalMailList.self, from: bytes)
            messageID = list.messages.first { $0.to.contains { $0.address == email } }?.id
            if messageID != nil { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        let id = try XCTUnwrap(messageID)
        let (bytes, response) = try await URLSession.shared.data(from: mail.appendingPathComponent("api/v1/message/" + id))
        guard (response as? HTTPURLResponse)?.statusCode == 200, bytes.count < 1_048_576 else { throw LocalFixtureIssue.unavailable }
        let message = try JSONDecoder().decode(LocalMailBody.self, from: bytes)
        let html = message.html.replacingOccurrences(of: "&amp;", with: "&")
        let regex = try NSRegularExpression(pattern: "https?[^\\s\"<>]+")
        let links = regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { Range($0.range, in: html).flatMap { URL(string: String(html[$0])) } }
        let link = try XCTUnwrap(links.first { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "token" } == true })
        guard link.host == api.host, link.port == api.port,
              URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "redirect_to" })?.value == BackendAccount.emailRedirectURL.absoluteString else { throw LocalFixtureIssue.unsafeConfiguration }
        // Capture the real server redirect without opening a browser or exposing its code.
        let session = URLSession(configuration: .ephemeral, delegate: LocalRedirectStopper(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (_, redirectResponse) = try await session.data(from: link)
        let http = try XCTUnwrap(redirectResponse as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 303)
        let callback = try XCTUnwrap(http.value(forHTTPHeaderField: "Location").flatMap(URL.init(string:)))
        let restarted = BackendAccount(storage: store)
        await restarted.handleEmailLink(callback)
        XCTAssertNil(restarted.issue)
        let newUserID = try XCTUnwrap(restarted.verifiedUserID)
        XCTAssertNotEqual(newUserID, fixture.syntheticOwnerAuthUUID)
        let admission = TeamAdministration(account: restarted)
        await admission.loadTeams()
        XCTAssertNil(admission.issue)
        XCTAssertTrue(admission.teams.isEmpty, "A verified new signup must not acquire team or owner authority")
        await restarted.signOut()
        XCTAssertEqual(restarted.state, .signedOut)
    }

    func testNativeVerifiedSessionRosterAndStatisticsRoundTrip() async throws {
        guard let text = ProcessInfo.processInfo.environment["TEAMSTATS_LOCAL_TEST_FIXTURE"] else {
            throw XCTSkip("Isolated local server fixture is not configured.")
        }
        let fixture = try JSONDecoder().decode(LocalServerFixture.self, from: Data(text.utf8))
        guard let url = URL(string: fixture.apiRoot), url.host == "127.0.0.1",
              fixture.syntheticEmail.hasSuffix("@example.invalid") else {
            throw LocalFixtureIssue.unsafeConfiguration
        }
        let storage = SecureSessionStorage(service: "TeamStats.local-server.tests." + UUID().uuidString)
        let options = SupabaseClientOptions(auth: .init(storage: storage, storageKey: "synthetic-session", autoRefreshToken: false), global: .init(logger: nil))
        defer { try? storage.remove(key: "synthetic-session") }
        let client = SupabaseClient(supabaseURL: url, supabaseKey: fixture.publishableKey, options: options)
        let verified = try await client.auth.verifyOTP(email: fixture.syntheticEmail, token: fixture.syntheticEmailTestCode, type: .email)
        XCTAssertEqual(verified.user.id, fixture.syntheticOwnerAuthUUID)
        let restarted = SupabaseClient(supabaseURL: url, supabaseKey: fixture.publishableKey, options: options)
        let restoredUser = try await restarted.auth.user()
        XCTAssertEqual(restoredUser.id, fixture.syntheticOwnerAuthUUID)

        let model = TeamAdministration(authenticatedClient: { client })
        await model.loadTeams()
        XCTAssertNil(model.issue)
        let team = try XCTUnwrap(model.teams.first { $0.id == fixture.syntheticTeamID })
        await model.selectTeam(team)
        XCTAssertEqual(model.access?.isOwner, true)
        XCTAssertNil(model.issue)
        let previousIDs = Set(model.roster.map(\.id))
        let label = "TEST ONLY native integration " + UUID().uuidString.prefix(8)
        let saved = await model.saveRoster(entry: nil, displayName: label, jerseyNumber: "0")
        XCTAssertTrue(saved)
        XCTAssertNil(model.issue)
        let entry = try XCTUnwrap(model.roster.first { $0.displayName == label })
        XCTAssertFalse(previousIDs.contains(entry.id))
        let edited = await model.saveRoster(entry: entry, displayName: label + " edited", jerseyNumber: "00")
        XCTAssertTrue(edited)
        XCTAssertNil(model.issue)
        let updated = try XCTUnwrap(model.roster.first { $0.id == entry.id })
        XCTAssertEqual(updated.version, entry.version + 1)
        XCTAssertEqual(model.roster.filter { $0.id == entry.id }.count, 1)
        await model.archiveRoster(updated)
        XCTAssertNil(model.issue)
        XCTAssertNotNil(model.roster.first { $0.id == entry.id }?.archivedAt)
        XCTAssertTrue(previousIDs.isSubset(of: Set(model.roster.map(\.id))))
        let history: [RosterVersion] = try await client.from("roster_entry_revisions").select("version")
            .eq("roster_id", value: entry.id.uuidString).order("version").execute().value
        XCTAssertEqual(history.map(\.version), [1, 2, 3])

        let stats = ConnectedStatistics(teamID: fixture.syntheticTeamID, authenticatedClient: { client })
        await stats.loadGames()
        XCTAssertNil(stats.issue)
        let previousGameIDs = Set(stats.games.map(\.id))
        let gameID = UUID()
        let created = await stats.createGame(id: gameID, dateString: "2026-10-11", opponent: "TEST ONLY native stats " + UUID().uuidString.prefix(8), homeAway: "home", gameType: "regularSeason")
        XCTAssertTrue(created)
        let game = try XCTUnwrap(stats.games.first { $0.id == gameID })
        await stats.loadGame(game)
        XCTAssertNil(stats.issue)
        var drafts: [ConnectedDatasetType: ConnectedVersion] = [:]
        for kind in ConnectedDatasetType.allCases {
            drafts[kind] = await stats.openDraft(kind)
            XCTAssertNil(stats.issue)
        }
        let coverage = [ConnectedCoveredPlayer(id: entry.id, version: 1)]
        let box: AnyJSON = .object(["gameID": .string(gameID.uuidString), "playerID": .string(entry.id.uuidString), "values": .object([
            "points": .integer(3), "offensiveRebounds": .integer(1), "defensiveRebounds": .integer(2), "assists": .null,
            "twosMade": .integer(0), "twosMissed": .integer(1), "threesMade": .integer(1), "threesMissed": .integer(0), "freeThrowsMade": .integer(0), "freeThrowsMissed": .integer(0)])])
        let paint: AnyJSON = .object(["gameID": .string(gameID.uuidString), "playerID": .string(entry.id.uuidString), "total": .integer(0)])
        func possession(_ side: String, _ number: Int, turnover: Bool, values: [String: AnyJSON]) -> AnyJSON {
            .object(["id": .string(UUID().uuidString), "gameID": .string(gameID.uuidString), "team": .string(side), "number": .integer(number), "values": .object(values), "turnover": .bool(turnover)])
        }
        let ours = possession("ours", 1, turnover: false, values: ["paintTouches": .null, "offensiveRebounds": .integer(1), "twosMissed": .integer(1), "threesMade": .integer(1)])
        let opponent = [possession("opponent", 1, turnover: true, values: [:]), possession("opponent", 2, turnover: false, values: ["twosMissed": .integer(1)])]
        let batchSaved = await stats.saveDraftBatch([
            ConnectedDraftSave(version: try XCTUnwrap(drafts[.boxScores]), records: [box], coveredRoster: coverage),
            ConnectedDraftSave(version: try XCTUnwrap(drafts[.playerPaintTouches]), records: [paint], coveredRoster: coverage),
            ConnectedDraftSave(version: try XCTUnwrap(drafts[.ourPossessions]), records: [ours]),
            ConnectedDraftSave(version: try XCTUnwrap(drafts[.opponentPossessions]), records: opponent)])
        XCTAssertTrue(batchSaved)
        XCTAssertNil(stats.issue)
        XCTAssertEqual(stats.ownVersions.count, 4)
        let savedBox = try XCTUnwrap(stats.ownVersions.first { $0.datasetType == .boxScores })
        XCTAssertTrue(savedBox.records[0].objectValue?["values"]?.objectValue?["assists"]?.isNil == true)
        XCTAssertEqual(stats.rosterLabels(for: savedBox).first?.name, label)
        let savedOurs = try XCTUnwrap(stats.ownVersions.first { $0.datasetType == .ourPossessions })
        XCTAssertTrue(savedOurs.records[0].objectValue?["values"]?.objectValue?["paintTouches"]?.isNil == true)
        let savedPaint = try XCTUnwrap(stats.ownVersions.first { $0.datasetType == .playerPaintTouches })
        XCTAssertEqual(try savedPaint.paintTouches().first?.total, 0)
        for kind in ConnectedDatasetType.allCases {
            let draft = try XCTUnwrap(stats.ownVersions.first { $0.datasetType == kind })
            let completed = await stats.complete(draft, confirmRoster: kind == .boxScores || kind == .playerPaintTouches, confirmNumericZeros: kind == .ourPossessions || kind == .opponentPossessions)
            XCTAssertTrue(completed)
            XCTAssertNil(stats.issue)
            let version = try XCTUnwrap(stats.ownVersions.first { $0.id == draft.id })
            let published = await stats.publish(version)
            XCTAssertTrue(published)
            XCTAssertNil(stats.issue)
        }
        let reopened = ConnectedStatistics(teamID: fixture.syntheticTeamID, authenticatedClient: { restarted })
        await reopened.loadGame(game)
        XCTAssertNil(reopened.issue)
        XCTAssertEqual(reopened.publishedVersions.count, 4)
        XCTAssertEqual(reopened.exportOutbox.count, 4, "Queued export is not delivery")
        await reopened.loadExportStatus()
        XCTAssertTrue(reopened.didLoadExportStatus)
        XCTAssertNil(reopened.exportIssue)
        XCTAssertEqual(reopened.exportStatus.count, 4)
        XCTAssertTrue(reopened.exportStatus.allSatisfy { $0.state == .queued && $0.deliveredAt == nil })
        let numbers = try XCTUnwrap(reopened.publishedStatistics())
        XCTAssertEqual(numbers.boxScoreTotal(.points), .available(3))
        XCTAssertEqual(numbers.boxScoreTotal(.assists), .unavailable(.missingInput))
        XCTAssertEqual(numbers.boxScoreRebounds(), .available(3))
        XCTAssertEqual(numbers.realPossessions(team: .ours), .available(2))
        XCTAssertEqual(numbers.realPossessions(team: .opponent), .available(1))
        if case .available(let checks) = numbers.reconcile() { XCTAssertEqual(checks.count, 7); XCTAssertTrue(checks.allSatisfy(\.matches)) }
        else { XCTFail("Complete matching saved shot inputs must reconcile") }
        await stats.loadGames()
        XCTAssertTrue(previousGameIDs.isSubset(of: Set(stats.games.map(\.id))))
        let plays = Playbook(teamID: fixture.syntheticTeamID, authenticatedClient: { client })
        await plays.load()
        XCTAssertNil(plays.issue)
        let existingPlayIDs = Set(plays.plays.map(\.id))
        let openedPlay = await plays.openDraft(playID: UUID())
        let playDraft = try XCTUnwrap(openedPlay)
        var diagram = PlayDiagram(); diagram.addMarker(); diagram.addStep()
        let markerID = diagram.markers[0].id
        diagram.move(markerID: markerID, step: 1, to: CourtPoint(x: 0.8, y: 0.2))
        let savedPlay = await plays.save(playDraft, title: "TEST ONLY native play verification", diagram: diagram)
        XCTAssertTrue(savedPlay)
        XCTAssertNil(plays.issue)
        let savedPlayVersion = try XCTUnwrap(plays.ownDrafts.first { $0.id == playDraft.id })
        let publishedPlay = await plays.transition(savedPlayVersion, action: "publish")
        XCTAssertTrue(publishedPlay)
        let reopenedPlays = Playbook(teamID: fixture.syntheticTeamID, authenticatedClient: { client })
        await reopenedPlays.load()
        let acceptedPlay = try XCTUnwrap(reopenedPlays.published.first { $0.playID == playDraft.playID })
        XCTAssertEqual(acceptedPlay.diagram, diagram)
        XCTAssertEqual(acceptedPlay.diagram.positions(at: 0.5).first?.point.x ?? 0, 0.65, accuracy: 0.0001)
        let openedRevision = await reopenedPlays.openDraft(playID: acceptedPlay.playID, source: acceptedPlay)
        let successor = try XCTUnwrap(openedRevision)
        XCTAssertNotEqual(successor.id, acceptedPlay.id)
        XCTAssertEqual(successor.basePublishedVersionID, acceptedPlay.id)
        XCTAssertEqual(successor.diagram.markers[0].id, markerID)
        XCTAssertEqual(reopenedPlays.published.first { $0.playID == acceptedPlay.playID }?.id, acceptedPlay.id)
        XCTAssertTrue(existingPlayIDs.isSubset(of: Set(reopenedPlays.plays.map(\.id))))
        try await client.auth.signOut(scope: .local)
    }
}

private struct LocalServerFixture: Decodable {
    let apiRoot: String
    let publishableKey: String
    let syntheticEmail: String
    let syntheticEmailTestCode: String
    let syntheticOwnerAuthUUID: UUID
    let syntheticTeamID: UUID
    let mailpitURL: URL?
}
private struct RosterVersion: Decodable { let version: Int64 }
private enum LocalFixtureIssue: Error { case unsafeConfiguration, unavailable }
private struct LocalMailList: Decodable {
    let messages: [Message]
    struct Message: Decodable {
        let id: String
        let to: [Recipient]
        enum CodingKeys: String, CodingKey { case id = "ID", to = "To" }
    }
    struct Recipient: Decodable {
        let address: String
        enum CodingKeys: String, CodingKey { case address = "Address" }
    }
}
private struct LocalMailBody: Decodable {
    let html: String
    enum CodingKeys: String, CodingKey { case html = "HTML" }
}
private final class LocalRedirectStopper: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
