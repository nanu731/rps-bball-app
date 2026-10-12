import Foundation
import SwiftUI

struct ConnectedGamesView: View {
    let account: BackendAccount
    @State private var model: ConnectedStatistics
    @State private var showingNewGame = false

    init(account: BackendAccount, teamID: UUID) {
        self.account = account
        _model = State(initialValue: ConnectedStatistics(account: account, teamID: teamID))
    }

    var body: some View {
        List {
            ConnectedStatisticsFeedback(model: model, retryGames: true)
            if !model.didLoadGames {
                Section { Text("Shared games are unavailable until the server loads successfully.") }
            } else if model.games.isEmpty {
                Section { ContentUnavailableView("No shared games", systemImage: "basketball", description: Text("Add an after-game record with its date, opponent, home/away status and game type.")) }
            } else {
                Section("Shared games") {
                    ForEach(model.games) { game in
                        NavigationLink {
                            ConnectedGameDetailView(account: account, model: model, game: game)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(game.opponent).font(.headline)
                                Text(game.dateString).foregroundStyle(.secondary)
                                Text("\(connectedVenue(game.homeAway)) · \(connectedGameType(game.gameType))")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }
                    }
                }
            }
            Section {
                Text("Shared server records. Local games and temporary players are preserved separately and are never uploaded automatically.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Shared games")
        .toolbar {
            Button("Add game", systemImage: "plus") { showingNewGame = true }
                .disabled(model.isBusy || !model.didLoadGames || model.reloadRequired)
        }
        .sheet(isPresented: $showingNewGame) { ConnectedNewGameView(model: model) }
        .task { await model.loadGames() }
    }
}

struct ConnectedStatisticsFeedback: View {
    let model: ConnectedStatistics
    var retryGames = false
    var body: some View {
        if model.isBusy { Section { ProgressView("Contacting statistics server…") } }
        if let issue = model.issue {
            Section {
                Label(issue.localizedDescription, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                Button("Reload / Retry") { Task { if retryGames { await model.loadGames() } else { await model.reload() } } }.disabled(model.isBusy)
            }
        }
        if let confirmation = model.confirmation {
            Section { Label(confirmation, systemImage: "checkmark.circle") }
        }
    }
}

private struct ConnectedNewGameView: View {
    let model: ConnectedStatistics
    @Environment(\.dismiss) private var dismiss
    @State private var gameID = UUID()
    @State private var date = Date()
    @State private var opponent = ""
    @State private var venue = "home"
    @State private var kind = "regularSeason"
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                ConnectedStatisticsFeedback(model: model, retryGames: true)
                Section("Game details") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Opponent", text: $opponent).focused($focused)
                    Picker("Our team", selection: $venue) {
                        Text("Home").tag("home")
                        Text("Away").tag("away")
                    }
                    Picker("Game type", selection: $kind) {
                        Text("Regular season").tag("regularSeason")
                        Text("Playoff").tag("playoff")
                    }
                }
                Section {
                    Button("Save game on server") {
                        focused = false
                        Task {
                            if await model.createGame(id: gameID, dateString: connectedDateString(date), opponent: opponent, homeAway: venue, gameType: kind) { dismiss() }
                        }
                    }.disabled(model.isBusy || model.reloadRequired || opponent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text("A game appears in the shared list only after the server confirms it.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add shared game")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(model.isBusy) }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } }
            }
            .interactiveDismissDisabled(model.isBusy)
        }
    }
}

private struct ConnectedGameDetailView: View {
    let account: BackendAccount
    let model: ConnectedStatistics
    let game: ConnectedGame

    var body: some View {
        List {
            ConnectedStatisticsFeedback(model: model)
            Section("Game details") {
                LabeledContent("Date", value: game.dateString)
                LabeledContent("Opponent", value: game.opponent)
                LabeledContent("Our team", value: connectedVenue(game.homeAway))
                LabeledContent("Game type", value: connectedGameType(game.gameType))
            }
            Section("Game Film") {
                NavigationLink("Video links and owner review") {
                    MediaResourcesView(teamID: game.teamID, kind: .film, targetID: game.id,
                        targetTitle: game.opponent, account: account)
                }
                Text("Links require access at the video provider. Saving a link does not upload a file or verify playback.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !model.didLoadGame || model.selectedGame?.id != game.id {
                Section { Text("Statistics are unavailable until this game loads successfully.").foregroundStyle(.secondary) }
            } else {
                Section("Published statistics") {
                    NavigationLink("View accepted statistics") { PublishedStatisticsView(model: model, game: game) }
                    Text("Only the current accepted version of each dataset contributes to this summary. A published dataset does not mean every dataset is complete.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Your entry") {
                    NavigationLink("Player box scores") { ConnectedStatEntryView(model: model, game: game, initialDataset: .boxScores) }
                    NavigationLink("Paired possession sheets") { ConnectedStatEntryView(model: model, game: game, initialDataset: .ourPossessions) }
                    NavigationLink("Player paint-touch totals") { ConnectedStatEntryView(model: model, game: game, initialDataset: .playerPaintTouches) }
                    ForEach(model.ownVersions.filter { $0.status != .draft }) { version in
                        NavigationLink("\(version.datasetType.label) · \(version.status.rawValue.capitalized)") {
                            ConnectedVersionDetailView(model: model, version: version)
                        }
                    }
                    Text("Drafts are incomplete and unreviewed. Completion, submission and publication are separate server actions.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Actual roster") {
                    if model.roster.filter({ $0.archivedAt == nil }).isEmpty {
                        Text("TODO_TEAM_ROSTER — no active actual roster entries on the server.").foregroundStyle(.secondary)
                    }
                    ForEach(model.roster.filter { $0.archivedAt == nil }) { player in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(player.displayName) · #\(player.jerseyNumber)")
                            Text("Roster version \(player.version)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if model.access?.can(.statsReview) == true {
                    Section("Statistics review") {
                        if model.reviewQueue.isEmpty { Text("No submitted datasets available for your review.").foregroundStyle(.secondary) }
                        ForEach(model.reviewQueue) { version in
                            NavigationLink(version.datasetType.label) { ConnectedVersionDetailView(model: model, version: version) }
                        }
                    }
                }
                Section("Your edit requests") {
                    let requests = model.editRequests.filter { $0.requesterUserID == model.access?.userID }
                    if requests.isEmpty { Text("No edit requests for this game.").foregroundStyle(.secondary) }
                    ForEach(requests) { request in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(request.status.rawValue.capitalized)
                            if !request.reason.isEmpty { Text(request.reason) }
                            if !request.reviewReason.isEmpty { Text(request.reviewReason).foregroundStyle(.secondary) }
                        }
                    }
                }
                if model.access?.can(.datasetsReopen) == true {
                    Section("Completed-data edit review") {
                        if model.editReviewQueue.isEmpty { Text("No pending edit requests available for your review.").foregroundStyle(.secondary) }
                        ForEach(model.editReviewQueue) { request in
                            NavigationLink("Review edit request") { ConnectedEditRequestReviewView(model: model, request: request) }
                        }
                    }
                }
                if model.access?.isOwner == true {
                    Section { NavigationLink("Sheets export status") { ConnectedExportQueueView(model: model) } }
                }
            }
        }
        .navigationTitle(game.opponent)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadGame(game) }
    }
}

struct ConnectedVersionDetailView: View {
    let model: ConnectedStatistics
    let version: ConnectedVersion
    @State private var action: ConnectedReviewAction?
    private var current: ConnectedVersion { model.versions.first { $0.id == version.id } ?? version }
    var body: some View {
        List {
            ConnectedStatisticsFeedback(model: model)
            if model.didLoadGame && model.versions.contains(where: { $0.id == version.id }) {
                Section("Dataset status") {
                    Text(current.datasetType.label).font(.headline)
                    LabeledContent("Server state", value: current.status.rawValue.capitalized)
                    LabeledContent("Revision", value: String(current.revision))
                    Text("Read-only saved version. Completed data requires an approved edit request before it can change.").foregroundStyle(.secondary)
                }
                ConnectedVersionRecords(model: model, version: current, labels: model.rosterLabels(for: current))
                Section("Server actions") {
                    if current.authorUserID == model.access?.userID && current.status == .completed {
                        Button("Submit for review") { Task { _ = await model.submit(current) } }
                    }
                    if current.authorUserID == model.access?.userID &&
                        (current.status == .completed || current.status == .submitted) && model.access?.can(.statsPublish) == true {
                        Button("Publish accepted version") { action = .publish }
                    }
                    if current.status == .submitted && model.access?.can(.statsReview) == true &&
                        (current.authorUserID != model.access?.userID || model.access?.isOwner == true) {
                        Button("Approve and publish") { action = .approve }
                        Button("Reject submission") { action = .reject }
                    }
                    if current.status.isComplete && (current.status == .published || current.authorUserID == model.access?.userID) {
                        Button("Request permission to edit") { action = .requestEdit }
                    }
                }.disabled(model.isBusy || model.reloadRequired)
            } else {
                Section { Text("Saved dataset unavailable. Reload current authorized server data before viewing it.") }
            }
        }
        .navigationTitle(current.datasetType.label)
        .sheet(item: $action) { action in ConnectedVersionActionSheet(model: model, version: current, action: action) }
    }
}

enum ConnectedReviewAction: String, Identifiable {
    case publish, approve, reject, requestEdit
    var id: String { rawValue }
    var label: String {
        switch self {
        case .publish: "Publish dataset"
        case .approve: "Approve and publish"
        case .reject: "Reject submission"
        case .requestEdit: "Request permission to edit"
        }
    }
}

struct ConnectedVersionActionSheet: View {
    let model: ConnectedStatistics
    let version: ConnectedVersion
    let action: ConnectedReviewAction
    @State private var reason = ""
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            Form {
                ConnectedStatisticsFeedback(model: model)
                Section {
                    Text(version.datasetType.label).font(.headline)
                    Text("Server revision \(version.revision)")
                    if action == .approve || action == .publish {
                        Text("Accept this completed dataset as the current shared version. Other datasets retain their own status. The server rechecks permission and the published base before accepting it.")
                    } else if action == .reject {
                        Text("The submitted dataset remains read-only. An accepted published version stays available.")
                    } else {
                        Text("A reviewer must approve reopening. The current saved and accepted versions stay unchanged while the request is pending.")
                    }
                    if action == .reject || action == .requestEdit {
                        TextField("Optional reason", text: $reason, axis: .vertical).focused($focused)
                    }
                    Button(action.label) {
                        focused = false
                        Task {
                            let success: Bool
                            switch action {
                            case .publish: success = await model.publish(version)
                            case .approve: success = await model.review(version, approve: true, reason: reason)
                            case .reject: success = await model.review(version, approve: false, reason: reason)
                            case .requestEdit: success = await model.requestEdit(version, reason: reason)
                            }
                            if success { dismiss() }
                        }
                    }.disabled(model.isBusy || model.reloadRequired)
                }
            }
            .navigationTitle(action.label)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Go back") { dismiss() }.disabled(model.isBusy) }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } }
            }
            .interactiveDismissDisabled(model.isBusy)
        }
    }
}

private struct ConnectedEditRequestReviewView: View {
    let model: ConnectedStatistics
    let request: ConnectedEditRequest
    @State private var reason = ""
    @State private var approving: Bool?
    @FocusState private var focused: Bool
    private var current: ConnectedEditRequest { model.editRequests.first { $0.id == request.id } ?? request }
    private var mayReview: Bool {
        model.access?.can(.datasetsReopen) == true &&
        (current.requesterUserID != model.access?.userID || model.access?.isOwner == true)
    }
    var body: some View {
        List {
            ConnectedStatisticsFeedback(model: model)
            if model.didLoadGame {
            Section("Edit request") {
                Text(current.status.rawValue.capitalized)
                if !current.reason.isEmpty { Text(current.reason) }
                if let source = model.versions.first(where: { $0.id == current.sourceVersionID }) {
                    NavigationLink("View frozen source dataset") { ConnectedVersionDetailView(model: model, version: source) }
                } else { Text("The source dataset has not loaded. Reload before deciding.").foregroundStyle(.secondary) }
            }
            if current.status.rawValue == "pending" && mayReview {
                Section("Review") {
                    TextField("Optional review reason", text: $reason, axis: .vertical).focused($focused)
                    Button("Approve reopening") { approving = true }
                    Button("Reject edit request") { approving = false }
                }.disabled(model.isBusy || model.reloadRequired || !model.versions.contains { $0.id == current.sourceVersionID })
            } else if !mayReview {
                Section { Text("Independent review is required. You cannot approve your own edit request unless you are the owner.") }
            }
            } else { Section { Text("Edit request unavailable. Reload current authorized server data.") } }
        }
        .navigationTitle("Review edit request")
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } } }
        .confirmationDialog(approving == true ? "Approve reopening?" : "Reject edit request?", isPresented: Binding(get: { approving != nil }, set: { if !$0 { approving = nil } }), titleVisibility: .visible) {
            Button(approving == true ? "Approve reopening" : "Reject edit request") {
                let approve = approving == true
                approving = nil
                focused = false
                Task { _ = await model.reviewEdit(current, approve: approve, reason: reason) }
            }
            Button("Go back", role: .cancel) { approving = nil }
        } message: { Text("The server confirms the decision. Approval creates an editable working revision and preserves the published version.") }
    }
}

func connectedVenue(_ raw: String) -> String { raw == "home" ? "Home" : "Away" }
func connectedGameType(_ raw: String) -> String { raw == "playoff" ? "Playoff" : "Regular season" }
func connectedDateString(_ date: Date) -> String {
    ConnectedGame.dateString(date)
}
