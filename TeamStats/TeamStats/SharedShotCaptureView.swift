import SwiftUI
import UniformTypeIdentifiers

struct SharedShotCaptureView: View {
    let account: BackendAccount
    let game: ConnectedGame
    let roster: [ServerRosterEntry]
    @State private var model: SharedShotCapture?
    var body: some View {
        Group {
            if let model { SharedShotControls(model: model, roster: roster) }
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
                    if let issue = model.issue { Label(issue, systemImage: "exclamationmark.triangle").fixedSize(horizontal: false, vertical: true) }
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
                            NavigationLink("Inspect saved capture") { ShotCaptureReadOnlyView(document: doc, status: state.status, isVisible: { model.contentCurrent && model.state != nil }) }
                        }
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
    var isVisible: () -> Bool = { true }
    var body: some View {
        if !isVisible() { ContentUnavailableView("Capture concealed", systemImage: "lock") } else { List {
            Section { Text(status).font(.headline); Text("Read-only saved observations. Coverage remains unverified; these do not replace official after-game statistics.").font(.footnote) }
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
