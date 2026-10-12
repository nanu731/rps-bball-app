import XCTest
import Foundation
import Supabase
@testable import TeamStats

@MainActor
final class ConnectedStatisticsTests: XCTestCase {
    func testPendingExportReadDoesNotBlockNextGameOrReplaceReopenedSnapshot() async throws {
        for sameGame in [false, true] {
            let fixture = StatisticsFixture(mode: .delayedExport)
            let model = fixture.model()
            await model.loadGames()
            let first = try XCTUnwrap(model.games.first)
            await model.loadGame(first)
            let pending = Task { await model.loadExportStatus() }
            for _ in 0..<100 where fixture.exportRequestCount == 0 {
                try await Task.sleep(for: .milliseconds(5))
            }
            XCTAssertEqual(fixture.exportRequestCount, 1)
            await model.loadGame(sameGame ? first : try XCTUnwrap(model.games.last))
            XCTAssertNil(model.issue)
            await model.loadExportStatus()
            await pending.value
            XCTAssertTrue(model.didLoadExportStatus)
            XCTAssertFalse(model.isLoadingExportStatus)
            XCTAssertEqual(fixture.exportRequestCount, 2)
            XCTAssertEqual(model.exportStatus.first?.gameID, model.selectedGame?.id)
            XCTAssertEqual(model.exportStatus.first?.publicationGeneration, 2)
        }
    }
    func testExportStatusShowsServerDeliveryRatherThanAssumingOutboxWasDelivered() async throws {
        let fixture = StatisticsFixture(mode: .exportStates)
        let model = fixture.model()
        await model.loadGames()
        await model.loadGame(try XCTUnwrap(model.games.first))
        await model.loadExportStatus()
        XCTAssertTrue(model.didLoadExportStatus)
        XCTAssertNil(model.exportIssue)
        XCTAssertEqual(model.exportStatus.map(\.state), [.queued, .failed, .delivered])
        XCTAssertEqual(model.exportStatus[1].errorCode, "budget_disabled")
        XCTAssertEqual(model.exportStatus[2].deliveredAt, "2026-10-11T12:00:00Z")
        XCTAssertEqual(fixture.commands.last?.name, "stats_export_status")
    }

    func testExportFailureKeepsStatisticsUsableAndRetryLoadsStatus() async throws {
        let fixture = StatisticsFixture(mode: .exportFailureOnce)
        let model = fixture.model()
        await model.loadGames()
        await model.loadGame(try XCTUnwrap(model.games.first))
        let savedVersions = model.versions.map(\.id)
        await model.loadExportStatus()
        XCTAssertFalse(model.didLoadExportStatus)
        XCTAssertEqual(model.exportIssue, .server)
        XCTAssertTrue(model.didLoadGame)
        XCTAssertNil(model.issue)
        XCTAssertEqual(model.versions.map(\.id), savedVersions)
        await model.loadExportStatus()
        XCTAssertTrue(model.didLoadExportStatus)
        XCTAssertNil(model.exportIssue)
        XCTAssertEqual(model.exportStatus.count, 3)
    }
    func testGameDiscoveryAndStableIdentityRetryUseServerRows() async throws {
        let fixture = StatisticsFixture()
        let model = fixture.model()
        await model.loadGames()
        XCTAssertTrue(model.didLoadGames)
        XCTAssertEqual(model.games.first?.dateString, "2026-10-11")
        let id = statsGameID
        let first = await model.createGame(id: id, dateString: "2026-10-11", opponent: "Synthetic opponent", homeAway: "home", gameType: "regularSeason")
        let second = await model.createGame(id: id, dateString: "2026-10-11", opponent: "Synthetic opponent", homeAway: "home", gameType: "regularSeason")
        XCTAssertTrue(first); XCTAssertTrue(second)
        XCTAssertEqual(fixture.commands.map { $0.parameters["p_game_id"] as? String }, [id.uuidString, id.uuidString])
        XCTAssertEqual(model.games.count, 1)
    }
    func testSnapshotPreservesNullZeroAndHistoricalCoveredRosterLabels() async throws {
        let fixture = StatisticsFixture()
        let model = fixture.model()
        await model.loadGames()
        await model.loadGame(try XCTUnwrap(model.games.first))
        XCTAssertTrue(model.didLoadGame)
        let version = try XCTUnwrap(model.ownVersions.first)
        let records = try version.boxScores()
        XCTAssertNil(records.first?.values["points"])
        XCTAssertEqual(records.first?.values["twosMade"], 0)
        XCTAssertEqual(version.records.first?.objectValue?["values"]?.objectValue?["points"], .null)
        let save = try ConnectedDraftSave(version: version, boxScores: records, coveredRoster: version.coveredRoster)
        XCTAssertEqual(save.records.first?.objectValue?["values"]?.objectValue?["points"], .null)
        XCTAssertEqual(model.rosterLabels(for: version).first?.name, "Original synthetic name")
        XCTAssertEqual(model.roster.first?.displayName, "New synthetic name")
        XCTAssertTrue(model.publishedVersions.isEmpty)
        XCTAssertEqual(try model.publishedStatistics()?.boxScoreTotal(.points), .unavailable(.incompleteDataset))
    }
    func testOpenAndAtomicSaveUseExpectedRevisionAndPreserveBlankPayload() async throws {
        let fixture = StatisticsFixture()
        let model = fixture.model()
        await model.loadGames()
        await model.loadGame(try XCTUnwrap(model.games.first))
        let opened = await model.openDraft(.boxScores)
        let version = try XCTUnwrap(opened)
        let save = try ConnectedDraftSave(version: version, boxScores: version.boxScores(), coveredRoster: version.coveredRoster)
        let saved = await model.saveDraftBatch([save])
        XCTAssertTrue(saved)
        XCTAssertEqual(model.ownVersions.first?.revision, 2)
        XCTAssertNotNil(model.confirmation)
        XCTAssertEqual(fixture.commands.map(\.name), ["stats_open_draft", "stats_save_drafts"])
        let items = try XCTUnwrap(fixture.commands.last?.parameters["p_items"] as? [[String: Any]])
        XCTAssertEqual(items.first?["expected_revision"] as? Int, 1)
        let records = try XCTUnwrap(items.first?["records"] as? [[String: Any]])
        let values = try XCTUnwrap(records.first?["values"] as? [String: Any])
        XCTAssertTrue(values["points"] is NSNull)
        XCTAssertEqual(values["twosMade"] as? Int, 0)
    }
    func testCompletionConfirmationsAndPublicationUseServerStatusOnly() async throws {
        let fixture = StatisticsFixture()
        let model = fixture.model()
        await model.loadGames(); await model.loadGame(try XCTUnwrap(model.games.first))
        let draft = try XCTUnwrap(model.ownVersions.first)
        let completed = await model.complete(draft, confirmRoster: true, confirmNumericZeros: false, suppressNumericWarning: false)
        XCTAssertTrue(completed)
        XCTAssertEqual(model.ownVersions.first?.status, .completed)
        XCTAssertTrue(model.publishedVersions.isEmpty)
        let saved = await model.saveDraftBatch([ConnectedDraftSave(version: try XCTUnwrap(model.ownVersions.first), records: draft.records, coveredRoster: draft.coveredRoster)])
        XCTAssertFalse(saved)
        XCTAssertEqual(fixture.commands.count, 1)
        await model.reload()
        let published = await model.publish(try XCTUnwrap(model.ownVersions.first))
        XCTAssertTrue(published)
        XCTAssertEqual(model.publishedVersions[.boxScores]?.status, .published)
        let command = try XCTUnwrap(fixture.commands.first)
        XCTAssertEqual(command.parameters["p_confirm_roster"] as? Bool, true)
        XCTAssertEqual(command.parameters["p_confirm_numeric_zeros"] as? Bool, false)
        XCTAssertEqual(command.parameters["p_suppress_numeric_warning"] as? Bool, false)
        XCTAssertEqual(command.parameters["p_expected_revision"] as? Int, 1)
    }
    func testSubmissionReviewAndApprovedEditKeepAcceptedVersionVisible() async throws {
        let fixture = StatisticsFixture()
        let model = fixture.model()
        await model.loadGames(); await model.loadGame(try XCTUnwrap(model.games.first))
        _ = await model.complete(try XCTUnwrap(model.ownVersions.first), confirmRoster: true)
        let submitted = await model.submit(try XCTUnwrap(model.ownVersions.first))
        XCTAssertTrue(submitted)
        XCTAssertEqual(model.reviewQueue.first?.status, .submitted)
        let reviewed = await model.review(try XCTUnwrap(model.reviewQueue.first), approve: true, reason: "Synthetic review")
        XCTAssertTrue(reviewed)
        let accepted = try XCTUnwrap(model.publishedVersions[.boxScores])
        let requested = await model.requestEdit(accepted, reason: "Synthetic correction")
        XCTAssertTrue(requested)
        let request = try XCTUnwrap(model.editReviewQueue.first)
        let approved = await model.reviewEdit(request, approve: true, reason: "Synthetic approval")
        XCTAssertTrue(approved)
        XCTAssertEqual(model.publishedVersions[.boxScores]?.id, accepted.id)
        XCTAssertTrue(model.ownVersions.contains { $0.status == .draft && $0.id != accepted.id })
        XCTAssertEqual(fixture.commands.map(\.name), ["stats_complete", "stats_submit", "stats_review", "stats_request_edit", "stats_review_edit"])
        XCTAssertEqual(fixture.commands.last?.parameters["p_request_id"] as? String, statsRequestID.uuidString)
        XCTAssertEqual(fixture.commands.last?.parameters["p_expected_revision"] as? Int, 1)
        XCTAssertEqual(fixture.commands.last?.parameters["p_approve"] as? Bool, true)
    }
    func testLowercaseUUIDAdapterPreservesNullsAndMatchesCoveredRoster() async throws {
        let fixture = StatisticsFixture(mode: .lowercaseIdentity)
        let model = fixture.model()
        await model.loadGames(); await model.loadGame(try XCTUnwrap(model.games.first))
        let version = try XCTUnwrap(model.ownVersions.first)
        let records = try version.boxScores()
        XCTAssertEqual(records.first?.playerID, statsPlayerID.uuidString)
        let save = try ConnectedDraftSave(version: version, boxScores: records, coveredRoster: version.coveredRoster)
        XCTAssertEqual(save.records.first?.objectValue?["values"]?.objectValue?["points"], .null)
        _ = await model.complete(version, confirmRoster: true)
        _ = await model.publish(try XCTUnwrap(model.ownVersions.first))
        XCTAssertEqual(try model.publishedStatistics()?.boxScoreTotal(.twosMade), .available(0))
    }
    func testDisplayAdapterRejectsMalformedNegativeCount() async throws {
        let fixture = StatisticsFixture(mode: .negativeCount)
        let model = fixture.model()
        await model.loadGames(); await model.loadGame(try XCTUnwrap(model.games.first))
        XCTAssertThrowsError(try XCTUnwrap(model.ownVersions.first).boxScores())
    }
    func testConflictHTTP500RequiresReloadAndNeverReplaysPost() async throws {
        let fixture = StatisticsFixture(mode: .conflictOnce)
        let model = fixture.model()
        await model.loadGames(); await model.loadGame(try XCTUnwrap(model.games.first))
        let draft = try XCTUnwrap(model.ownVersions.first)
        let item = ConnectedDraftSave(version: draft, records: draft.records, coveredRoster: draft.coveredRoster)
        let saved = await model.saveDraftBatch([item])
        XCTAssertFalse(saved); XCTAssertEqual(model.issue, .conflict)
        XCTAssertNil(model.confirmation); XCTAssertTrue(model.reloadRequired)
        XCTAssertFalse(model.didLoadGame)
        XCTAssertFalse(model.issue!.localizedDescription.contains("SENSITIVE_FIXTURE_PAYLOAD"))
        let repeated = await model.saveDraftBatch([item])
        XCTAssertFalse(repeated); XCTAssertEqual(fixture.commands.count, 1)
        await model.reload()
        XCTAssertEqual(model.ownVersions.first?.revision, 2)
        let current = try XCTUnwrap(model.ownVersions.first)
        let retried = await model.saveDraftBatch([ConnectedDraftSave(version: current, records: current.records, coveredRoster: current.coveredRoster)])
        XCTAssertTrue(retried); XCTAssertEqual(fixture.commands.count, 2)
        XCTAssertEqual(fixture.commands.last?.parameters["p_items"].flatMap { $0 as? [[String: Any]] }?.first?["expected_revision"] as? Int, 2)
    }
    func testAmbiguousServerFailureAndDeniedAccessNeverClaimSuccess() async throws {
        for mode in [StatisticsFixture.Mode.serverFailure, .denied] {
            let fixture = StatisticsFixture(mode: mode)
            let model = fixture.model()
            await model.loadGames(); await model.loadGame(try XCTUnwrap(model.games.first))
            let version = try XCTUnwrap(model.ownVersions.first)
            let saved = await model.saveDraftBatch([ConnectedDraftSave(version: version, records: version.records, coveredRoster: version.coveredRoster)])
            XCTAssertFalse(saved); XCTAssertNil(model.confirmation)
            XCTAssertEqual(model.issue, mode == .denied ? .denied : .server)
            XCTAssertEqual(fixture.commands.count, 1)
            XCTAssertTrue(model.reloadRequired)
        }
    }
    func testPairedDraftSaveUsesOnePostForBothSheets() async throws {
        let fixture = StatisticsFixture(mode: .paired)
        let model = fixture.model()
        await model.loadGames(); await model.loadGame(try XCTUnwrap(model.games.first))
        let items = model.ownVersions.map { ConnectedDraftSave(version: $0, records: $0.records, coveredRoster: $0.coveredRoster) }
        XCTAssertEqual(items.count, 2)
        let before = fixture.requestCount
        let saved = await model.saveDraftBatch(items)
        XCTAssertTrue(saved)
        XCTAssertEqual(fixture.commands.count, 1)
        XCTAssertEqual(fixture.commands.first?.name, "stats_save_drafts")
        XCTAssertEqual((fixture.commands.first?.parameters["p_items"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual(Set(model.ownVersions.map(\.revision)), [2])
        XCTAssertEqual(fixture.requestCount - before, 10) // One POST plus nine snapshot reads; transport fixture, not latency evidence.
    }
    func testPossessionCompletionSendsExplicitZeroAndWarningConfirmations() async throws {
        let fixture = StatisticsFixture(mode: .possession)
        let model = fixture.model()
        await model.loadGames(); await model.loadGame(try XCTUnwrap(model.games.first))
        XCTAssertFalse(model.suppressNumericWarning)
        let draft = try XCTUnwrap(model.ownVersions.first)
        XCTAssertNil(try draft.possessions().first?.values["paintTouches"])
        let completed = await model.complete(draft, confirmNumericZeros: true, suppressNumericWarning: true)
        XCTAssertTrue(completed)
        XCTAssertTrue(model.suppressNumericWarning)
        XCTAssertEqual(model.ownVersions.first?.status, .completed)
        XCTAssertEqual(try model.ownVersions.first?.possessions().first?.values["paintTouches"], 0)
        XCTAssertNil(try draft.possessions().first?.values["paintTouches"])
        XCTAssertEqual(fixture.commands.first?.parameters["p_confirm_numeric_zeros"] as? Bool, true)
        XCTAssertEqual(fixture.commands.first?.parameters["p_suppress_numeric_warning"] as? Bool, true)
        XCTAssertTrue(model.publishedVersions.isEmpty)
    }
    func testRejectedSubmissionAndEditReturnFrozenStateWithoutPublishedData() async throws {
        let fixture = StatisticsFixture()
        let model = fixture.model()
        await model.loadGames(); await model.loadGame(try XCTUnwrap(model.games.first))
        _ = await model.complete(try XCTUnwrap(model.ownVersions.first), confirmRoster: true)
        _ = await model.submit(try XCTUnwrap(model.ownVersions.first))
        let rejected = await model.review(try XCTUnwrap(model.reviewQueue.first), approve: false, reason: "Synthetic rejection")
        XCTAssertTrue(rejected)
        XCTAssertEqual(model.ownVersions.first?.status, .rejected)
        XCTAssertTrue(model.publishedVersions.isEmpty)
        _ = await model.requestEdit(try XCTUnwrap(model.ownVersions.first), reason: "Synthetic correction")
        let editRejected = await model.reviewEdit(try XCTUnwrap(model.editReviewQueue.first), approve: false)
        XCTAssertTrue(editRejected)
        XCTAssertEqual(model.editRequests.first?.status, .rejected)
        XCTAssertFalse(model.ownVersions.contains { $0.status == .draft })
    }
    func testPagedReadsDoNotSilentlyDropTheSecondPage() async throws {
        let fixture = StatisticsFixture(mode: .pagination)
        let model = fixture.model()
        await model.loadGames()
        XCTAssertEqual(model.games.count, 101)
        XCTAssertTrue(model.didLoadGames)
        XCTAssertEqual(fixture.gameOffsets, [0, 100])
    }
    func testSupersededStatisticsRetainMissingValuesWithoutClaimingCompletion() async throws {
        let fixture = StatisticsFixture(mode: .supersededRecovery)
        let model = fixture.model()
        await model.loadGames(); await model.loadGame(try XCTUnwrap(model.games.first))
        guard model.didLoadGame else { XCTFail("Server-confirmed superseded saved draft must remain readable"); return }
        let retained = try XCTUnwrap(model.ownVersions.first { $0.id == statsVersionID })
        XCTAssertEqual(retained.status.rawValue, "superseded")
        XCTAssertFalse(retained.status.isComplete)
        XCTAssertEqual(retained.records.first?.objectValue?["values"]?.objectValue?["points"], .null)
        XCTAssertEqual(try retained.boxScores().first?.values["twosMade"], 0)
        XCTAssertEqual(model.publishedVersions[.boxScores]?.id, statsRecoveryPublishedID)
    }
    func testUncertainApprovedRecoveryReloadFindsDraftWithoutRepeatingApproval() async throws {
        for mode in [StatisticsFixture.Mode.recoveryLostReply, .recoveryReadFailure] {
            let fixture = StatisticsFixture(mode: mode)
            let model = fixture.model()
            await model.loadGames(); await model.loadGame(try XCTUnwrap(model.games.first))
            let retained = try XCTUnwrap(model.ownVersions.first { $0.id == statsVersionID })
            let request = try XCTUnwrap(model.editReviewQueue.first)
            let uncertain = await model.reviewEdit(request, approve: true)
            XCTAssertFalse(uncertain); XCTAssertNil(model.confirmation); XCTAssertTrue(model.reloadRequired)
            XCTAssertThrowsError(try model.approvedRecoveryDraft(for: retained))
            fixture.allowRecoveryRead()
            await model.reload()
            XCTAssertTrue(model.didLoadGame)
            let approved = try model.approvedRecoveryDraft(for: retained)
            XCTAssertEqual(approved.id, statsWorkingID)
            XCTAssertEqual(approved.recoverySourceVersionID, retained.id)
            XCTAssertEqual(approved.basePublishedVersionID, statsRecoveryPublishedID)
            XCTAssertEqual(model.versions.first { $0.id == retained.id }?.status, .superseded)
            XCTAssertEqual(fixture.commands.filter { $0.name == "stats_review_edit" }.count, 1)
            var typed = try retained.boxScores()
            typed[0].values["assists"] = 7
            let item = try ConnectedDraftSave(version: approved, boxScores: typed, coveredRoster: retained.coveredRoster)
            let saved = await model.saveDraftBatch([item])
            XCTAssertTrue(saved)
            let current = try model.approvedRecoveryDraft(for: retained)
            XCTAssertEqual(try current.boxScores().first?.values["assists"], 7)
            XCTAssertNil(try current.boxScores().first?.values["points"])
            XCTAssertEqual(model.versions.first { $0.id == retained.id }?.records, retained.records)
            XCTAssertEqual(model.publishedVersions[.boxScores]?.id, statsRecoveryPublishedID)
            XCTAssertEqual(fixture.commands.filter { $0.name == "stats_review_edit" }.count, 1)
        }
    }
    func testApprovedRecoveryLookupRejectsMissingForkedCyclicOrUnapprovedLineageAndRevokedAccess() async throws {
        let fixture = StatisticsFixture(mode: .supersededRecovery)
        let model = fixture.model()
        await model.loadGames(); await model.loadGame(try XCTUnwrap(model.games.first))
        let retained = try XCTUnwrap(model.ownVersions.first { $0.id == statsVersionID })
        XCTAssertEqual(try model.approvedRecoveryDraft(for: retained).id, statsWorkingID)
        for fault in [StatisticsFixture.LineageFault.missing, .fork, .cycle, .unapproved] {
            fixture.setLineageFault(fault)
            await model.reload()
            XCTAssertTrue(model.didLoadGame)
            XCTAssertThrowsError(try model.approvedRecoveryDraft(for: retained))
        }
        fixture.setLineageFault(.none); fixture.revokeAccess()
        await model.reload()
        XCTAssertFalse(model.didLoadGame)
        XCTAssertThrowsError(try model.approvedRecoveryDraft(for: retained))
        XCTAssertTrue(fixture.commands.filter { $0.name == "stats_review_edit" }.isEmpty)
    }
    func testFailedDiscoveryIsNotConfirmedEmpty() async {
        let model = ConnectedStatistics(teamID: statsTeamID, authenticatedClient: { throw AccountIssue.provider })
        await model.loadGames()
        XCTAssertFalse(model.didLoadGames)
        XCTAssertEqual(model.issue, .server)
        XCTAssertNil(model.confirmation)
    }
}
private let statsTeamID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

private let statsGameID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
private let statsOtherGameID = UUID(uuidString: "33333333-3333-4333-8333-333333333334")!
private let statsUserID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
private let statsPlayerID = UUID(uuidString: "AAAA4444-4444-4444-8444-444444444444")!
private let statsVersionID = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
private let statsDatasetID = UUID(uuidString: "66666666-6666-4666-8666-666666666666")!
private let statsRequestID = UUID(uuidString: "77777777-7777-4777-8777-777777777777")!
private let statsWorkingID = UUID(uuidString: "88888888-8888-4888-8888-888888888888")!
private let statsRecoveryPublishedID = UUID(uuidString: "DDDD0001-DDDD-4DDD-8DDD-000000000001")!
private let statsRecoveryBaseID = UUID(uuidString: "DDDD0001-DDDD-4DDD-8DDD-000000000002")!
private let statsSecondDatasetID = UUID(uuidString: "99999999-9999-4999-8999-999999999999")!
private let statsSecondVersionID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
private let statsPossessionID = UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!
// Synthetic HTTP responses verify the real SDK/model seam, not deployed authorization or delivery.
private final class StatisticsFixture: @unchecked Sendable {
    enum Mode { case standard, lowercaseIdentity, negativeCount, conflictOnce, serverFailure, denied, paired, possession, pagination, exportStates, exportFailureOnce, delayedExport, supersededRecovery, recoveryLostReply, recoveryReadFailure }
    private let mode: Mode
    init(mode: Mode = .standard) {
        self.mode = mode
        if mode == .supersededRecovery { versionStatus = "superseded"; revision = 2; editStatus = "approved"; workingVersion = recoveryWorking() }
        if mode == .recoveryLostReply || mode == .recoveryReadFailure { editStatus = "pending" }
    }
    enum LineageFault { case none, missing, fork, cycle, unapproved }
    private var lineageFault: LineageFault = .none
    private var recoveryReadDenied = false
    private var accessRevoked = false
    private var isRecoveryMode: Bool { [.supersededRecovery, .recoveryLostReply, .recoveryReadFailure].contains(mode) }
    func allowRecoveryRead() { lock.withLock { recoveryReadDenied = false } }
    func setLineageFault(_ fault: LineageFault) { lock.withLock { lineageFault = fault } }
    func revokeAccess() { lock.withLock { accessRevoked = true } }
    private var didFail = false
    private var requests = 0
    private var exportReads = 0
    private var fixtureGameID = statsGameID
    var exportRequestCount: Int { lock.withLock { exportReads } }
    func responseDelay(_ request: URLRequest) -> TimeInterval {
        lock.withLock { mode == .delayedExport && request.url?.lastPathComponent == "stats_export_status" && exportReads == 1 ? 0.3 : 0 }
    }
    private var offsets: [Int] = []
    private var suppressWarning = false
    struct Command { let name: String; let parameters: [String: Any] }
    let key = UUID().uuidString
    private let lock = NSLock()
    private var commandValues: [Command] = []
    private var revision = 1
    private var versionStatus = "draft"
    private var editStatus: String?
    private var workingVersion: [String: Any]?
    var commands: [Command] { lock.withLock { commandValues } }
    var requestCount: Int { lock.withLock { requests } }
    var gameOffsets: [Int] { lock.withLock { offsets } }
    @MainActor func model() -> ConnectedStatistics {
        StatisticsProtocol.registry.insert(self)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StatisticsProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Statistics-Fixture": key]
        let client = SupabaseClient(supabaseURL: URL(string: "https://statistics.invalid")!, supabaseKey: "sb_publishable_synthetic_fixture", options: .init(auth: .init(autoRefreshToken: false), global: .init(session: URLSession(configuration: configuration), logger: nil)))
        return ConnectedStatistics(teamID: statsTeamID, authenticatedClient: { client })
    }
    func response(_ request: URLRequest) -> (Int, Data) {
        lock.lock(); defer { lock.unlock() }
        requests += 1
        let name = request.url!.lastPathComponent
        if request.url!.path.contains("/rpc/") {
            if name == "team_access", accessRevoked { return json(["code": "42501", "message": "Synthetic revoked access"], status: 403) }
            if name == "team_access" { return json(["team_id": statsTeamID.uuidString, "user_id": statsUserID.uuidString, "is_owner": true, "access_revision": 7, "capabilities": [], "grant_envelopes": []]) }
            if name == "stats_preferences" { return json(["suppress_numeric_warning": suppressWarning]) }
            let parameters = (try? JSONSerialization.jsonObject(with: request.httpBody ?? body(request.httpBodyStream))) as? [String: Any] ?? [:]
            commandValues.append(Command(name: name, parameters: parameters))
            if name == "stats_export_status" {
                exportReads += 1
                if mode == .delayedExport {
                    return json([statsGameID, statsOtherGameID].map { gameID in
                        ["job_id": gameID.uuidString, "game_id": gameID.uuidString,
                         "accepted_version_id": statsVersionID.uuidString, "dataset_type": "box_scores",
                         "publication_generation": exportReads, "state": "queued", "attempts": 0,
                         "error_code": NSNull(), "delivered_at": NSNull()] as [String: Any]
                    })
                }
                if mode == .exportFailureOnce && !didFail {
                    didFail = true
                    return json(["code": "XX000", "message": "SENSITIVE_FIXTURE_PAYLOAD"], status: 500)
                }
                return json(["queued", "failed", "delivered"].enumerated().map { index, state in
                    ["job_id": String(format: "CCCCCCCC-CCCC-4CCC-8CCC-%012d", index),
                     "game_id": fixtureGameID.uuidString, "accepted_version_id": statsVersionID.uuidString,
                     "dataset_type": "box_scores", "publication_generation": index + 1,
                     "state": state, "attempts": index,
                     "error_code": state == "failed" ? "budget_disabled" : NSNull(),
                     "delivered_at": state == "delivered" ? "2026-10-11T12:00:00Z" : NSNull()] as [String: Any]
                })
            }
            if name == "stats_save_drafts", mode == .denied || mode == .serverFailure || (mode == .conflictOnce && !didFail) {
                didFail = true; revision = 2
                return json(["code": mode == .conflictOnce ? "40001" : mode == .denied ? "42501" : "XX000", "message": "SENSITIVE_FIXTURE_PAYLOAD", "details": "SENSITIVE_FIXTURE_PAYLOAD", "hint": NSNull()], status: 500)
            }
            if name == "stats_create_game" { return json(game()) }
            if name == "stats_save_drafts", isRecoveryMode, var working = workingVersion,
               let items = parameters["p_items"] as? [[String: Any]], let item = items.first {
                working["revision"] = (working["revision"] as! Int) + 1
                working["records"] = item["records"]; working["covered_roster"] = item["covered_roster"]
                workingVersion = working; return json([working])
            }
            if name == "stats_save_drafts" {
                revision += 1
                return json([version(status: versionStatus, revision: revision)] + (mode == .paired ? [secondVersion()] : []))
            }
            if name == "stats_complete" {
                revision += 1; versionStatus = "completed"
                if mode == .possession { suppressWarning = parameters["p_confirm_numeric_zeros"] as? Bool == true && parameters["p_suppress_numeric_warning"] as? Bool == true }
            }
            if name == "stats_submit" { revision += 1; versionStatus = "submitted" }
            if name == "stats_request_edit" { editStatus = "pending"; return json(editRequest()) }
            if name == "stats_review_edit", isRecoveryMode {
                revision += 1; versionStatus = "superseded"; editStatus = "approved"; workingVersion = recoveryWorking()
                if mode == .recoveryLostReply { return (0, Data()) }
                if mode == .recoveryReadFailure { recoveryReadDenied = true }
                return json(["request": editRequest(), "version": workingVersion!])
            }
            if name == "stats_review_edit" {
                editStatus = parameters["p_approve"] as? Bool == true ? "approved" : "rejected"
                if editStatus == "rejected" { return json(["request": editRequest(), "version": NSNull()]) }
                var draft = version(status: "draft", revision: 1)
                draft["id"] = statsWorkingID.uuidString
                draft["base_published_version_id"] = statsVersionID.uuidString
                workingVersion = draft
                return json(["request": editRequest(), "version": draft])
            }
            if name == "stats_publish" || name == "stats_review" { revision += 1; versionStatus = name == "stats_review" && parameters["p_approve"] as? Bool == false ? "rejected" : "published" }
            return json(version(status: versionStatus, revision: revision))
        }
        if name == "games" {
            if mode == .delayedExport {
                let requested = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "id" }?.value
                if let requested, let id = UUID(uuidString: String(requested.dropFirst(3))) { fixtureGameID = id }
                return json([statsGameID, statsOtherGameID].filter { requested == nil || requested == "eq." + $0.uuidString }.map { id in
                    var row = game(); row["id"] = id.uuidString; return row
                })
            }
            let offset = Int(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "offset" })?.value ?? "0") ?? 0
            offsets.append(offset)
            if mode == .pagination {
                return json((offset..<min(offset + 100, 101)).map { index -> [String: Any] in
                    var row = game(); row["id"] = String(format: "33333333-3333-4333-8333-%012d", index); return row
                })
            }
            return json([game()])
        }
        if name == "roster_entries" { return json([["id": statsPlayerID.uuidString, "team_id": statsTeamID.uuidString, "display_name": "New synthetic name", "jersey_number": "13", "version": 2, "archived_at": NSNull()]]) }
        if name == "roster_entry_revisions" { return json([["roster_id": statsPlayerID.uuidString, "team_id": statsTeamID.uuidString, "display_name": "Original synthetic name", "jersey_number": "12", "version": 1]]) }
        if name == "stat_versions", isRecoveryMode {
            if recoveryReadDenied { return json(["code": "42501", "message": "Synthetic read failure"], status: 403) }
            var retained = version(status: versionStatus, revision: revision)
            var working = workingVersion
            if lineageFault == .missing { working?["recovery_source_version_id"] = NSNull() }
            if lineageFault == .cycle { retained["recovery_source_version_id"] = statsWorkingID.uuidString }
            var rows = [retained, recoveryPublished(id: statsRecoveryBaseID), recoveryPublished(id: statsRecoveryPublishedID)] + (working.map { [$0] } ?? [])
            if lineageFault == .fork, var fork = working { fork["id"] = "DDDD0001-DDDD-4DDD-8DDD-000000000003"; rows.append(fork) }
            return json(rows)
        }
        if name == "stat_datasets", isRecoveryMode {
            return json([["id": statsDatasetID.uuidString, "team_id": statsTeamID.uuidString, "game_id": fixtureGameID.uuidString, "dataset_type": "box_scores", "published_version_id": statsRecoveryPublishedID.uuidString]])
        }
        if name == "stat_versions" { return json([version(status: versionStatus, revision: revision)] + (workingVersion.map { [$0] } ?? []) + (mode == .paired ? [secondVersion()] : [])) }
        if name == "stat_edit_requests" {
            var request = editRequest()
            if lineageFault == .unapproved { request["status"] = "pending" }
            return json(editStatus == nil ? [] : [request])
        }
        if name == "stat_datasets" { return json([["id": statsDatasetID.uuidString, "team_id": statsTeamID.uuidString, "game_id": fixtureGameID.uuidString, "dataset_type": mode == .possession ? "our_possessions" : "box_scores", "published_version_id": versionStatus == "published" ? statsVersionID.uuidString as Any : NSNull()]] + (mode == .paired ? [["id": statsSecondDatasetID.uuidString, "team_id": statsTeamID.uuidString, "game_id": fixtureGameID.uuidString, "dataset_type": "opponent_possessions", "published_version_id": NSNull()]] : [])) }
        return json([])
    }
    func version(status: String = "draft", revision: Int = 1) -> [String: Any] {
        if mode == .possession {
            var result = secondVersion()
            result["id"] = statsVersionID.uuidString; result["dataset_id"] = statsDatasetID.uuidString
            result["dataset_type"] = "our_possessions"; result["status"] = status; result["revision"] = revision
            var record = possessionRecord(team: "ours")
            if status != "draft" { record["values"] = Dictionary(uniqueKeysWithValues: PossessionField.allCases.map { ($0.rawValue, 0) }) }
            result["records"] = [record]
            return result
        }
        return ["id": statsVersionID.uuidString, "team_id": statsTeamID.uuidString, "game_id": fixtureGameID.uuidString, "dataset_id": statsDatasetID.uuidString, "dataset_type": "box_scores", "author_user_id": statsUserID.uuidString, "revision": revision, "status": status, "records": [["gameID": fixtureGameID.uuidString, "playerID": mode == .lowercaseIdentity ? statsPlayerID.uuidString.lowercased() : statsPlayerID.uuidString, "values": ["points": NSNull(), "twosMade": mode == .negativeCount ? -1 : 0]]], "covered_roster": [["id": statsPlayerID.uuidString, "version": 1]], "base_published_version_id": isRecoveryMode ? statsRecoveryBaseID.uuidString as Any : NSNull()]
    }
    private func recoveryPublished(id: UUID) -> [String: Any] {
        var row = version(status: "published", revision: 4)
        row["id"] = id.uuidString; row["author_user_id"] = "11111111-1111-4111-8111-111111111112"
        row["base_published_version_id"] = id == statsRecoveryBaseID ? NSNull() : statsRecoveryBaseID.uuidString as Any
        if id == statsRecoveryPublishedID { row["records"] = [["gameID": statsGameID.uuidString, "playerID": statsPlayerID.uuidString, "values": ["points": 2, "twosMade": 1]]] }
        return row
    }
    private func recoveryWorking() -> [String: Any] {
        var row = recoveryPublished(id: statsRecoveryPublishedID)
        row["status"] = "draft"; row["revision"] = 1; row["author_user_id"] = statsUserID.uuidString
        row["id"] = statsWorkingID.uuidString; row["base_published_version_id"] = statsRecoveryPublishedID.uuidString
        row["recovery_source_version_id"] = statsVersionID.uuidString
        return row
    }
    private func possessionRecord(team: String) -> [String: Any] {
        ["id": statsPossessionID.uuidString, "gameID": fixtureGameID.uuidString, "team": team, "number": 1, "values": [:] as [String: Any], "turnover": false]
    }
    private func secondVersion() -> [String: Any] {
        ["id": statsSecondVersionID.uuidString, "team_id": statsTeamID.uuidString, "game_id": fixtureGameID.uuidString,
         "dataset_id": statsSecondDatasetID.uuidString, "dataset_type": "opponent_possessions", "author_user_id": statsUserID.uuidString,
         "revision": revision, "status": "draft", "records": [possessionRecord(team: "opponent")], "covered_roster": [], "base_published_version_id": NSNull()]
    }
    private func editRequest() -> [String: Any] {
        ["id": statsRequestID.uuidString, "team_id": statsTeamID.uuidString, "source_version_id": isRecoveryMode ? statsRecoveryPublishedID.uuidString : statsVersionID.uuidString,
         "requester_user_id": statsUserID.uuidString, "revision": editStatus == "approved" || editStatus == "rejected" ? 2 : 1,
         "status": editStatus ?? "pending", "reason": "Synthetic correction", "review_reason": "", "working_version_id": workingVersion == nil ? NSNull() : statsWorkingID.uuidString as Any]
    }
    private func game() -> [String: Any] { ["id": statsGameID.uuidString, "team_id": statsTeamID.uuidString, "date": "2026-10-11", "opponent": "Synthetic opponent", "home_away": "home", "game_type": "regularSeason", "publication_generation": 0] }
    private func json(_ object: Any, status: Int = 200) -> (Int, Data) { (status, try! JSONSerialization.data(withJSONObject: object)) }
    private func body(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(buffer, count: count) }
        return data
    }
}
private final class StatisticsRegistry: @unchecked Sendable {
    private let lock = NSLock(); private var fixtures: [String: StatisticsFixture] = [:]
    func insert(_ fixture: StatisticsFixture) { lock.withLock { fixtures[fixture.key] = fixture } }
    func get(_ key: String) -> StatisticsFixture? { lock.withLock { fixtures[key] } }
}
private final class StatisticsProtocol: URLProtocol, @unchecked Sendable {
    static let registry = StatisticsRegistry()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let fixture = Self.registry.get(request.value(forHTTPHeaderField: "X-Statistics-Fixture") ?? "") else { client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return }
        let (status, body) = fixture.response(request)
        let delay = fixture.responseDelay(request)
        if delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in deliver(status: status, body: body) }
        } else { deliver(status: status, body: body) }
    }
    private func deliver(status: Int, body: Data) {
        if status == 0 { client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
