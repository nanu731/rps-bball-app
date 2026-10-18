import SwiftUI
import UniformTypeIdentifiers

struct SharedShotCaptureView: View {
    let account: BackendAccount
    let game: ConnectedGame
    let roster: [ServerRosterEntry]
    var statistics: ConnectedStatistics? = nil
    @State private var model: SharedShotCapture?
    var body: some View {
        Group {
            if let model { SharedShotControls(model: model, roster: roster, statistics: statistics) }
            else { ProgressView("Opening shared capture") }
        }
        .navigationTitle("Shared shots").navigationBarTitleDisplayMode(.inline)
        .task {
            guard model == nil, let configuration = account.configuration, let actor = account.offlineClipActorID else { return }
            let value = SharedShotCapture(account: account,
                scope: ShotDeviceScope(environment: configuration.url.absoluteString, actorID: actor, teamID: game.teamID), gameID: game.id, title: game.opponent)
            model = value; await value.refresh()
        }
    }
}

struct SharedShotControls: View {
    let model: SharedShotCapture
    let roster: [ServerRosterEntry]
    var statistics: ConnectedStatistics? = nil
    @State private var showingScore = false
    @State private var recorderID = ""
    @State private var reason = ""
    @State private var importing = false
    @State private var importIssue: String?
    var body: some View {
        List {
            if !model.isCurrent { Section { Label("Capture concealed for this account", systemImage: "lock") } }
            else {
                Section {
                    if model.contentCurrent { Text(model.title).font(.headline) }
                    Text("Device recording, shared draft saving, review and publication are separate. No local game or temporary roster is uploaded.")
                        .font(.footnote)
                    if model.offline {
                        Label("Prepared device capture · current authority unverified", systemImage: "wifi.slash")
                        Text("Continue this journal without a connection. Reconnect and verify the current recorder before submitting. Remote revocation cannot be discovered offline.").font(.footnote)
                    }
                    if let issue = model.issue { Label(issue, systemImage: model.feedbackConfirmed ? "checkmark.circle" : "exclamationmark.triangle").fixedSize(horizontal: false, vertical: true) }
                    if model.isBusy { ProgressView("Checking current authority") }
                    Button("Refresh current access and capture") { Task { await model.refresh() } }
                        .disabled(model.isBusy || model.recorder?.needsSave == true)
                }
                if model.pending != nil {
                    Section("Unconfirmed command") {
                        Text("The exact command is preserved on this device. Recover its receipt before sending anything else.")
                        Button("Recover command receipt") { Task { await model.recoverReceipt() } }
                        if model.rejectedCommand { Button("Retain unresolved command and allow recovery") { Task { await model.archiveRejected() } }
                            Text("Preserves the frozen command as a separate protected file. Refresh and review any overlaps before proposing a new branch; this does not erase server history.").font(.footnote)
                        }
                        if model.receiptNotFound { Button("Retry same frozen command") { Task { await model.sendPending() } } }
                    }.disabled(model.isBusy)
                }
                if model.contentCurrent, let retained = model.retainedBranchURL { Section { ShareLink("Export retained recovery branch", item: retained) } }
                if model.contentCurrent, model.localConflict {
                    Section("Separate device branch preserved") {
                        Text("This journal differs from the server head. It was not merged or overwritten. A reviewer can inspect a recovery proposal and explicitly choose which branch to adopt.")
                        if let document = model.deviceDocument {
                            NavigationLink("Inspect preserved device branch") { ShotCaptureReadOnlyView(document: document, status: "Device recovery branch · not accepted", isVisible: { model.contentCurrent }) }
                            Button("Retain device branch and use saved server head") { Task { await model.retainBranchAndUseServer() } }.disabled(model.pending != nil)
                            Button("Propose this branch for recovery review") { Task { await model.save(document, recovery: true) } }
                        }
                    }
                }
                if let recorder = model.recorder, model.canRecord {
                    Section("Courtside entry") {
                        NavigationLink("Open device shot recorder") { ShotCaptureWorkspace(recorder: recorder, title: model.title) }
                        if let doc = recorder.visibleDocument { NavigationLink("Device journal charts") { ShotChartsView(document: doc, status: "Device draft · incomplete and unreviewed", score: model.score, officialSources: sources, isVisible: { model.contentCurrent }) } }
                        Text("Every change saves to this device first. Shared submission is explicit.").font(.footnote)
                        if !model.offline, let doc = recorder.visibleDocument {
                            Button("Save captured journal as shared draft") { Task { await model.save(doc, recovery: false) } }.disabled(model.pending != nil)
                        }
                    }
                }
                if model.contentCurrent, let state = model.state {
                    Section("Server-confirmed state") {
                        LabeledContent("State", value: state.status.replacingOccurrences(of: "_", with: " "))
                        LabeledContent("Recorder", value: state.recorder_user_id?.uuidString ?? "Not designated")
                        LabeledContent("Assignment revision", value: String(state.assignment_revision))
                        Text("A handoff changes who may submit. Device forks may overlap and require explicit review; stable IDs cannot identify two independently recorded observations of the same attempt.").font(.footnote)
                        if state.can_record, state.document == nil { Button("Prepare actual-roster capture on this device") { Task { await model.register(players: roster) } } }
                        if let doc = state.document {
                            NavigationLink("Saved capture charts") { ShotChartsView(document: doc, status: "Saved shared snapshot · \(state.status)", score: model.score, coverage: state.coverage, officialSources: sources, isVisible: { model.contentCurrent && model.state != nil }) }
                            NavigationLink("Inspect saved capture") { ShotCaptureReadOnlyView(document: doc, status: state.status, coverage: state.coverage, isVisible: { model.contentCurrent && model.state != nil }) }
                        }
                    }
                    Section("Attempt coverage · saved version") {
                        if let coverage = state.coverage {
                            Text(coverage.summary).font(.headline).fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("shot.coverage.status")
                            if let snapshot = state.snapshot_id {
                                Text("Capture revision \(state.document?.revision ?? 0) · version \(snapshot.uuidString)")
                                    .font(.footnote).fixedSize(horizontal: false, vertical: true)
                            }
                            Text("The designated manager confirms every field-goal and free-throw attempt, then the owner or a current statistics reviewer approves this saved version. Later saved changes need renewed confirmation and review; original approvals remain attached to their versions.")
                                .font(.footnote)
                            if coverage.can_confirm {
                                Button("Confirm every field-goal and free-throw attempt was recorded") { Task { await model.decideCoverage("confirm") } }
                                    .frame(minHeight: 44).accessibilityIdentifier("shot.coverage.confirm")
                            }
                            if coverage.can_approve {
                                Button("Approve attempt coverage for this saved version") { Task { await model.decideCoverage("approve") } }
                                    .frame(minHeight: 44).accessibilityIdentifier("shot.coverage.approve")
                            }
                        } else { Text("Coverage signoff is unavailable on this server. No coverage approval is implied.") }
                        Text("Coverage approval does not publish data, resolve pending outcomes or reconcile independent scores.").font(.footnote)
                    }.disabled(model.pending != nil)
                    Section("Independent score reference") {
                        if let score = model.score {
                            LabeledContent("Our confirmed score", value: score.our_points.map(String.init) ?? "Unavailable")
                            LabeledContent("Opponent confirmed score", value: score.opponent_points.map(String.init) ?? "Unavailable")
                            if let note = score.source_note { Text("Reference revision \(score.revision): \(note)").font(.footnote) }
                            if score.can_confirm {
                                Button("Enter independently confirmed score reference") { showingScore = true }
                                    .disabled(model.pending != nil)
                            }
                        } else { Text(model.scoreIssue ?? "Official score unavailable — no reference loaded.") }
                        Button("Refresh capture and accepted sources") { Task { await model.refresh(); await statistics?.reload() } }
                    }
                    if state.can_review {
                        Section("Recorder designation / handoff") {
                            TextField("Verified recorder Auth UUID", text: $recorderID).textInputAutocapitalization(.never).autocorrectionDisabled()
                            Text("Use an existing active member’s verified UUID. This does not grant recording permission; Manage team remains the grant authority.").font(.footnote)
                            TextField("Handoff / review reason", text: $reason, axis: .vertical)
                            Button("Confirm designated recorder") {
                                if let id = UUID(uuidString: recorderID) { Task { await model.assign(id, reason: reason) } }
                            }.disabled(model.pending != nil || UUID(uuidString: recorderID) == nil || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    if state.snapshot_id != nil {
                        Section("Explicit server decisions") {
                            if state.can_record { Button("Submit saved snapshot for review") { Task { await model.decide("submit", reason: "") } } }
                            if state.can_review {
                                Button("Approve resolved submitted snapshot") { Task { await model.decide("approve", reason: reason) } }
                                Button("Reject with reason") { Task { await model.decide("reject", reason: reason) } }.disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            if state.can_publish { Button("Publish resolved own snapshot without review") { Task { await model.decide("publish", reason: reason) } } }
                            Text("Decisions apply to the saved snapshot, not newer device entries. Pending outcomes prevent publication. Accepted partial coverage is still partial; score agreement never establishes attempt coverage.").font(.footnote)
                        }.disabled(model.pending != nil)
                    }
                    if state.can_review || state.can_record {
                        Section("Explicit recovery review") {
                            Button("Import preserved capture as a recovery proposal") { importing = true }
                            if let importIssue { Text(importIssue) }
                            ForEach(model.proposals) { proposal in
                                NavigationLink("Inspect recovery branch · \(proposal.local_revision) changes") {
                                    ShotRecoveryInspection(model: model, id: proposal.id)
                                }
                                if state.can_review {
                                    Button("Adopt this branch instead of current head") { Task { await model.decide("adopt", snapshot: proposal.id, reason: reason) } }
                                        .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                            if model.hasMoreProposals { Button("Load more recovery proposals") { Task { await model.moreProposals() } } }
                            Text("Adoption retains the displaced snapshot and reason. It replaces the chosen head; it does not automatically merge or deduplicate overlapping attempts.").font(.footnote)
                        }
                    }
                }
            }
        }
        .disabled(model.isBusy)
        .navigationTitle("Shared shots")
        .sheet(isPresented: $showingScore) { ShotScoreReferenceForm(model: model) }
        .task(id: model.knownExpiry) { await model.watchExpiry() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get(), access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let bytes = try ShotPreparationStore.readBounded(url, maximum: 10 * 1024 * 1024)
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                let document = try decoder.decode(ShotCaptureDocument.self, from: bytes); try document.validate()
                guard document.context.gameID == model.gameID, document.context.teamID == model.scope.teamID else { throw ShotCaptureIssue.invalid }
                importIssue = nil; Task { await model.save(document, recovery: true) }
            } catch { importIssue = "Recovery file could not be validated. No proposal was sent." }
        }
    }
    private func sources(_ team: ShotTeam, _ player: String?) -> [ShotOfficialSource] {
        guard let statistics, statistics.didLoadGame, statistics.selectedGame?.id == model.gameID else { return [] }
        var result: [ShotOfficialSource] = []
        if team == .our, let version = statistics.publishedVersions[.boxScores], let rows = try? version.boxScores() {
            result.append(.boxes(rows, expectedPlayerIDs: player.map { [$0] } ?? version.coveredRoster.map { $0.id.uuidString }, label: "Loaded accepted box score · revision \(version.revision) · version \(version.id)"))
        }
        if player == nil, let version = statistics.publishedVersions[team == .our ? .ourPossessions : .opponentPossessions], let rows = try? version.possessions() {
            result.append(.possessions(rows, label: "Loaded accepted possession sheet · revision \(version.revision) · version \(version.id)"))
        }
        return result
    }
}

struct PreparedShotCapturesView: View {
    let account: BackendAccount
    @State private var rows: [ShotPreparedRow] = []
    @State private var issue: String?
    var body: some View {
        List {
            Section {
                Text("Only previously prepared shared captures for this device account appear here. This does not discover new teams or upload records. Unknown remote changes remain unverified while offline.").font(.footnote)
                if let issue { Label(issue, systemImage: "exclamationmark.triangle") }
                Button("Reload device preparations") { Task { await load() } }
            }
            if account.offlineClipActorID == nil { Text("Verify the account online before opening prepared captures.") }
            else if rows.isEmpty { Text("No available prepared captures. Open an authorized shared game online to prepare one.") }
            else {
                ForEach(rows) { row in
                    NavigationLink(row.entry.title) { PreparedShotCaptureDetail(account: account, row: row) }
                }
            }
        }
        .navigationTitle("Device shot captures")
        .task { await load() }
        .onChange(of: account.offlineClipActorID) { _, _ in rows = []; Task { await load() } }
    }
    private func load() async {
        rows = []; issue = nil
        guard let actor = account.offlineClipActorID, let environment = account.configuration?.url.absoluteString else { return }
        do {
            let result = try await ShotPreparationStore.shared.catalog(environment: environment, actorID: actor)
            guard account.offlineClipActorID == actor, account.configuration?.url.absoluteString == environment else { return }
            rows = result
        } catch { issue = "Device preparation could not be read. Saved capture files were preserved; reconnect through the shared game to recover." }
    }
}
private struct PreparedShotCaptureDetail: View {
    let account: BackendAccount
    let row: ShotPreparedRow
    @State private var model: SharedShotCapture?
    var body: some View {
        Group {
            if let model { SharedShotControls(model: model, roster: []) }
            else { ProgressView("Opening prepared capture") }
        }.task {
            guard model == nil else { return }
            let value = SharedShotCapture(account: account, scope: row.scope, gameID: row.entry.gameID, title: row.entry.title)
            model = value; await value.openPrepared(row.entry)
        }
    }
}

struct ShotCaptureReadOnlyView: View {
    let document: ShotCaptureDocument
    let status: String
    var coverage: ShotCoverageState? = nil
    var isVisible: () -> Bool = { true }
    var body: some View {
        if !isVisible() { ContentUnavailableView("Capture concealed", systemImage: "lock") } else { List {
            Section { Text(status).font(.headline); Text((coverage?.summary ?? "Attempt coverage unverified for this device journal.") + " Read-only observations do not replace official after-game statistics.").font(.footnote) }
            ForEach(ShotTeam.allCases, id: \.self) { team in
                Section(team == .our ? "Our team" : "Opponent") {
                    if let totals = try? document.totals(team: team) {
                        LabeledContent("Entered scoring subtotal", value: String(totals.points))
                        LabeledContent("Pending outcomes", value: String(totals.pending))
                        LabeledContent("Free throws", value: "\(totals.madeFreeThrows) made · \(totals.missedFreeThrows) missed")
                    }
                }
            }
            ForEach((try? document.events()) ?? []) { event in
                VStack(alignment: .leading) {
                    Text(event.team == .our ? document.players.first(where: { $0.id == event.playerID })?.name ?? "Player unavailable" : "Opponent")
                    if event.kind == .fieldGoal { Text("\(event.value.map(String.init) ?? "Unentered value") · \(event.outcome?.rawValue ?? "Pending")") }
                    else { Text("Free throws: \(event.answers.filter { $0.outcome == .made }.count)/\(event.freeThrowAttempts ?? 0) · \(event.answers.count) answered") }
                }
            }
        }.navigationTitle("Captured shots") }
    }
}

private struct ShotRecoveryInspection: View {
    let model: SharedShotCapture
    let id: UUID
    var body: some View {
        Group {
            if model.contentCurrent, let doc = model.inspectedProposal { ShotCaptureReadOnlyView(document: doc, status: "Recovery proposal · possible overlap", isVisible: { model.contentCurrent && model.inspectedProposal != nil }) }
            else if let issue = model.issue { ContentUnavailableView("Recovery unavailable", systemImage: "lock", description: Text(issue)) }
            else { ProgressView("Checking recovery access") }
        }.task { await model.loadProposal(id) }
    }
}

private struct ShotScoreReferenceForm: View {
    let model: SharedShotCapture
    @Environment(\.dismiss) private var dismiss
    @State private var our: String
    @State private var opponent: String
    @State private var source: String
    @State private var confirmed = false
    @State private var frozen = false
    @State private var confirmingDiscard = false
    @FocusState private var focused: Bool
    private let initialOur: String, initialOpponent: String, initialSource: String
    init(model: SharedShotCapture) {
        self.model = model
        let our = model.score?.our_points.map(String.init) ?? "", opponent = model.score?.opponent_points.map(String.init) ?? "", source = model.score?.source_note ?? ""
        _our = State(initialValue: our); _opponent = State(initialValue: opponent); _source = State(initialValue: source)
        initialOur = our; initialOpponent = opponent; initialSource = source
    }
    private var dirty: Bool { !frozen && (our != initialOur || opponent != initialOpponent || source != initialSource || confirmed) }
    private func value(_ text: String) -> Int? { BoxScoreCount(text).number }
    private var valid: Bool {
        let values = [BoxScoreCount(our), BoxScoreCount(opponent)]
        return !values.contains(.invalid) && values.contains { $0.number != nil } && values.allSatisfy { ($0.number ?? 0) <= Int(Int32.max) }
            && !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && source.count <= 200
    }
    var body: some View {
        NavigationStack {
            Form {
                if model.contentCurrent {
                    Section("Independent final score reference") {
                        TextField("Our official points", text: $our).keyboardType(.numberPad).focused($focused)
                        TextField("Opponent official points", text: $opponent).keyboardType(.numberPad).focused($focused)
                        Text("Blank is unavailable for that team; explicit zero is0. Enter at least one independently confirmed score.").font(.footnote)
                        TextField("Independent score source", text: $source, axis: .vertical).focused($focused).accessibilityIdentifier("shot.score.source")
                        Toggle("I independently confirmed each entered score", isOn: $confirmed)
                        Text("Use the independent scorebook or official result. Never copy captured points just to force a match. This appends a reference; it does not rewrite statistics or establish attempt coverage.").font(.footnote)
                        if !valid { Text("Enter a nonnegative whole-number score within the supported integer range and an independent source of at most200 characters.").font(.footnote) }
                        Button("Confirm score reference") {
                            focused = false
                            Task {
                                let before = model.lastConfirmedBatch
                                await model.confirmScore(our: value(our), opponent: value(opponent), source: source)
                                frozen = model.pending != nil || model.lastConfirmedBatch != before
                            }
                        }.disabled(!valid || !confirmed || model.isBusy || model.pending != nil || frozen)
                    }.disabled(model.isBusy || frozen)
                }
                if model.isBusy { ProgressView("Saving reference; do not enter it again") }
                if let issue = model.issue { Label(issue, systemImage: model.feedbackConfirmed ? "checkmark.circle" : "info.circle").fixedSize(horizontal: false, vertical: true) }
                if model.pending != nil { Button("Recover command receipt") { Task { await model.recoverReceipt() } } }
                if !model.contentCurrent { Text("Entered fields are concealed until current access is verified. Any frozen command remains preserved.") }
            }
            .navigationTitle("Official score reference").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { requestClose() }.disabled(model.isBusy) }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } }
            }
            .confirmationDialog("Leave this unfinished reference?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Keep editing", role: .cancel) {}
                Button("Discard unsaved input", role: .destructive) { dismiss() }
            } message: { Text("Only this unfinished form is discarded. Existing saved records and frozen commands remain preserved.") }
        }.interactiveDismissDisabled(dirty || model.isBusy)
    }
    private func requestClose() {
        if dirty { confirmingDiscard = true } else { dismiss() }
    }
}
