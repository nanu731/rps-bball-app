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
            if !model.didLoadGames || model.issue == .denied {
                Section {
                    Text("Shared games are unavailable until the server loads successfully.")
                    if model.issue == nil {
                        Button("Reload shared games") { Task { await model.loadGames() } }.disabled(model.isBusy)
                    }
                }
            } else if model.games.isEmpty {
                Section { ContentUnavailableView("No shared games", systemImage: "basketball", description: Text("Add an after-game record with its date, opponent, home/away status and game type.")) }
            } else {
                Section("Shared games") {
                    ForEach(model.games) { game in
                        NavigationLink {
                            ConnectedGameDetailView(account: account, model: model, game: game)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(game.opponent).font(.headline).fixedSize(horizontal: false, vertical: true)
                                Text(game.dateString).font(.subheadline.weight(.semibold)).foregroundStyle(Color.accentColor)
                                Text("\(connectedVenue(game.homeAway)) · \(connectedGameType(game.gameType))")
                                    .font(.subheadline).foregroundStyle(.primary)
                            }.padding(.vertical, 8)
                        }
                    }
                }
            }
            Section {
                Text("Shared server records. Local games and temporary players are preserved separately and are never uploaded automatically.")
                    .foregroundStyle(TeamStatsStyle.secondaryText)
            }
        }
        .navigationTitle("Shared games")
        .navigationBarBackButtonHidden(model.isBusy)
        .toolbar {
            Button("Add game", systemImage: "plus") { showingNewGame = true }
                .disabled(model.isBusy || !model.didLoadGames || model.reloadRequired || model.issue == .denied)
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
                    .foregroundStyle(TeamStatsStyle.errorText).fixedSize(horizontal: false, vertical: true)
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
    @State private var date: Date
    @State private var initialDate: Date
    @State private var confirmDiscard = false
    @State private var opponent = ""
    @State private var venue = "home"
    @State private var kind = "regularSeason"
    @FocusState private var focused: Bool

    init(model: ConnectedStatistics) {
        self.model = model
        let today = Date()
        _date = State(initialValue: today)
        _initialDate = State(initialValue: today)
    }
    private var hasUnsavedDetails: Bool {
        !opponent.isEmpty || venue != "home" || kind != "regularSeason" ||
        connectedDateString(date) != connectedDateString(initialDate)
    }
    private func requestDismiss() {
        guard !model.isBusy else { return }
        if hasUnsavedDetails { confirmDiscard = true } else { dismiss() }
    }

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
                }.disabled(model.isBusy)
                Section {
                    Button("Save game on server") {
                        focused = false
                        Task {
                            if await model.createGame(id: gameID, dateString: connectedDateString(date), opponent: opponent, homeAway: venue, gameType: kind) { dismiss() }
                        }
                    }.disabled(model.isBusy || model.reloadRequired || opponent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text("A game appears in the shared list only after the server confirms it.").foregroundStyle(TeamStatsStyle.secondaryText)
                }
            }
            .navigationTitle("Add shared game")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { requestDismiss() }.disabled(model.isBusy) }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } }
            }
            .interactiveDismissDisabled(model.isBusy || hasUnsavedDetails)
            .confirmationDialog("Discard unsaved game details?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard unsaved details", role: .destructive) { dismiss() }
                Button("Keep editing") { }
            } message: {
                Text("This discards only the details entered in this form. No saved game or statistics are changed.")
            }
        }
    }
}

private struct ConnectedGameDetailView: View {
    let account: BackendAccount
    let model: ConnectedStatistics
    let game: ConnectedGame
    private var hasLoadedGame: Bool { model.didLoadGame && model.selectedGame?.id == game.id }

    var body: some View {
        List {
            ConnectedStatisticsFeedback(model: model)
            if !hasLoadedGame {
                Section { Text("Statistics are unavailable until this game loads successfully.").foregroundStyle(TeamStatsStyle.secondaryText) }
            } else {
                Section {
                    GameIdentity(opponent: game.opponent, date: game.dateString,
                        venue: connectedVenue(game.homeAway), kind: connectedGameType(game.gameType),
                        location: "Shared team records")
                    Text("Dataset completion, submission and publication are separate states.").font(.footnote)
                }
                Section("Your entry") {
                    NavigationLink { ConnectedStatEntryView(model: model, game: game, initialDataset: .boxScores) } label: {
                        TeamTaskLabel(title: "Player box scores", detail: "Single-player or roster table entry", symbol: "tablecells")
                    }
                    NavigationLink { ConnectedStatEntryView(model: model, game: game, initialDataset: .ourPossessions) } label: {
                        TeamTaskLabel(title: "Paired possession sheets", detail: "Independent records for each team", symbol: "rectangle.split.2x1")
                    }
                    NavigationLink { ConnectedStatEntryView(model: model, game: game, initialDataset: .playerPaintTouches) } label: {
                        TeamTaskLabel(title: "Player paint-touch totals", detail: "Independently collected game totals", symbol: "person.crop.rectangle")
                    }
                    ForEach(model.ownVersions.filter { $0.status != .draft }) { version in
                        NavigationLink("\(version.datasetType.label) · \(version.status.rawValue.capitalized)") {
                            ConnectedVersionDetailView(model: model, version: version)
                        }
                    }
                    Text("Drafts are incomplete and unreviewed. Completion, submission and publication are separate server actions.")
                        .font(.footnote).foregroundStyle(TeamStatsStyle.secondaryText)
                }
                Section("Published statistics") {
                    NavigationLink { PublishedStatisticsView(model: model, game: game) } label: {
                        TeamTaskLabel(title: "View accepted statistics", detail: "Current server-confirmed accepted versions", symbol: "checkmark.seal")
                    }
                    Text("Only the current accepted version of each dataset contributes to this summary. A published dataset does not mean every dataset is complete.")
                        .font(.footnote).foregroundStyle(TeamStatsStyle.secondaryText)
                }
                Section("Game Film") {
                    NavigationLink("Hudl shortcuts and owner review") {
                        MediaResourcesView(teamID: game.teamID, kind: .film, targetID: game.id,
                            targetTitle: game.opponent, account: account)
                    }
                    Text("Full-game films stay on Hudl. A shortcut opens Hudl separately; its account and film permissions still apply.")
                        .font(.footnote).foregroundStyle(TeamStatsStyle.secondaryText)
                }
                Section("Scouting") {
                    NavigationLink("Scouting PDFs") {
                        PrivateFilesView(teamID: game.teamID, kind: .scouting, targetID: game.id,
                            targetTitle: game.opponent, account: account)
                    }
                    Text("Report viewing and uploading use separate team permissions; the owner approves publication.")
                        .font(.footnote).foregroundStyle(TeamStatsStyle.secondaryText)
                }
                Section("Actual roster") {
                    if model.roster.filter({ $0.archivedAt == nil }).isEmpty {
                        Text("TODO_TEAM_ROSTER — no active actual roster entries on the server.").foregroundStyle(TeamStatsStyle.secondaryText)
                    }
                    ForEach(model.roster.filter { $0.archivedAt == nil }) { player in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(player.displayName) · #\(player.jerseyNumber)")
                            Text("Roster version \(player.version)").font(.caption).foregroundStyle(TeamStatsStyle.secondaryText)
                        }
                    }
                }
                if model.access?.can(.statsReview) == true {
                    Section("Statistics review") {
                        if model.reviewQueue.isEmpty { Text("No submitted datasets available for your review.").foregroundStyle(TeamStatsStyle.secondaryText) }
                        ForEach(model.reviewQueue) { version in
                            NavigationLink(version.datasetType.label) { ConnectedVersionDetailView(model: model, version: version) }
                        }
                    }
                }
                Section("Your edit requests") {
                    let requests = model.editRequests.filter { $0.requesterUserID == model.access?.userID }
                    if requests.isEmpty { Text("No edit requests for this game.").foregroundStyle(TeamStatsStyle.secondaryText) }
                    ForEach(requests) { request in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(request.status.rawValue.capitalized)
                            if !request.reason.isEmpty { Text(request.reason) }
                            if !request.reviewReason.isEmpty { Text(request.reviewReason).foregroundStyle(TeamStatsStyle.secondaryText) }
                        }
                    }
                }
                if model.access?.can(.datasetsReopen) == true {
                    Section("Completed-data edit review") {
                        if model.editReviewQueue.isEmpty { Text("No pending edit requests available for your review.").foregroundStyle(TeamStatsStyle.secondaryText) }
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
        .disabled(model.isBusy)
        .navigationTitle(hasLoadedGame ? game.opponent : "Shared game")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.isBusy)
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
                    Text("Read-only saved version. Completed data requires an approved edit request before it can change.").foregroundStyle(TeamStatsStyle.secondaryText)
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
        .disabled(model.isBusy)
        .navigationTitle(current.datasetType.label)
        .navigationBarBackButtonHidden(model.isBusy)
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
    @State private var confirmDiscard = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    private func requestDismiss() {
        guard !model.isBusy else { return }
        if !reason.isEmpty { confirmDiscard = true } else { dismiss() }
    }
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
                }.disabled(model.isBusy)
            }
            .navigationTitle(action.label)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Go back") { requestDismiss() }.disabled(model.isBusy) }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } }
            }
            .interactiveDismissDisabled(model.isBusy || !reason.isEmpty)
            .confirmationDialog("Discard unsaved reason?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard unsaved reason", role: .destructive) { dismiss() }
                Button("Keep editing") { }
            } message: {
                Text("This discards only this form's unsaved reason. Saved statistics and server decisions are unchanged.")
            }
        }
    }
}

private struct ConnectedEditRequestReviewView: View {
    let model: ConnectedStatistics
    let request: ConnectedEditRequest
    @State private var reason = ""
    @State private var approving: Bool?
    @State private var confirmDiscard = false
    @Environment(\.dismiss) private var dismiss
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
                } else { Text("The source dataset has not loaded. Reload before deciding.").foregroundStyle(TeamStatsStyle.secondaryText) }
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
        .disabled(model.isBusy)
        .navigationTitle("Review edit request")
        .navigationBarBackButtonHidden(model.isBusy || !reason.isEmpty)
        .toolbar {
            if !reason.isEmpty && !model.isBusy {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back", systemImage: "chevron.left") { confirmDiscard = true }
                }
            }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } }
        }
        .confirmationDialog("Discard unsaved review reason?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard unsaved reason", role: .destructive) { dismiss() }
            Button("Keep editing") { }
        } message: {
            Text("This discards only your unsaved review reason. The edit request and any saved server decision are unchanged.")
        }
        .confirmationDialog(approving == true ? "Approve reopening?" : "Reject edit request?", isPresented: Binding(get: { approving != nil }, set: { if !$0 { approving = nil } }), titleVisibility: .visible) {
            Button(approving == true ? "Approve reopening" : "Reject edit request") {
                let approve = approving == true
                approving = nil
                focused = false
                Task {
                    if await model.reviewEdit(current, approve: approve, reason: reason) { reason = "" }
                }
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
