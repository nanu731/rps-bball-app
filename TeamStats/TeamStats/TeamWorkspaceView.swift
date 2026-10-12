import SwiftUI

/// Member tasks live here; administration is a separate, server-authorized destination.
struct TeamWorkspaceView: View {
    let account: BackendAccount
    let openAccount: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var model: TeamAdministration
    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var pendingTeam: ServerTeam?
    @State private var confirmTeamChange = false
    @State private var reloadTeamsRequested = false
    @State private var showingAdmission = false

    init(account: BackendAccount, openAccount: @escaping () -> Void) {
        self.account = account
        self.openAccount = openAccount
        _model = State(initialValue: TeamAdministration(account: account))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            List {
                if account.sessionContextID == nil {
                    Section {
                        Text("Sign in to request admission or open your shared team.")
                        Button("Open Account", action: openAccount)
                    }
                } else {
                    if model.isBusy { Section { ProgressView("Loading your teams…") } }
                    if let issue = model.issue {
                        Section {
                            Label(issue.localizedDescription, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                            Button("Retry", action: requestReload).disabled(model.isBusy)
                        }
                    }
                    Section("Your teams") {
                        if model.didLoadTeams && model.teams.isEmpty {
                            Text("No active team is available. Use your administrator’s invitation code to request admission.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(model.teams) { team in
                            Button {
                                if let selected = model.selectedTeam, selected.id != team.id {
                                    pendingTeam = team
                                    confirmTeamChange = true
                                } else if model.selectedTeam?.id == team.id {
                                    columns = sizeClass == .compact ? .detailOnly : .all
                                }
                                else { select(team) }
                            } label: {
                                HStack {
                                    Text(team.name).fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                    if model.selectedTeam?.id == team.id {
                                        Image(systemName: "checkmark").accessibilityLabel("Selected team")
                                    }
                                }.frame(minHeight: 44)
                            }.disabled(model.isBusy)
                        }
                        Button("Reload teams", action: requestReload).disabled(model.isBusy)
                    }
                    Button { showingAdmission = true } label: {
                        Label("Request team admission", systemImage: "person.badge.plus")
                    }.disabled(model.isBusy)
                }
                Section {
                    Text("Shared team records are separate from device-local drafts. Signing in never uploads your local games.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Team")
            .navigationSplitViewColumnWidth(min: 240, ideal: 320, max: 420)
        } detail: {
            NavigationStack {
                if let team = model.selectedTeam, let access = model.access {
                    List {
                        Section {
                            Text(team.name).font(.headline)
                            Label("Active membership confirmed by server", systemImage: "checkmark.circle")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Section("Team activities") {
                            NavigationLink { ConnectedGamesView(account: account, teamID: team.id) } label: {
                                Label("Shared games and statistics", systemImage: "basketball")
                            }
                            NavigationLink { PlaybookView(account: account, teamID: team.id) } label: {
                                Label("Playbook", systemImage: "book.closed")
                            }
                            NavigationLink { TeamRosterOverview(account: account, team: team) } label: {
                                Label("Team roster", systemImage: "person.3")
                            }
                        }
                        if access.canReadAdministration || access.can(.rosterManage) {
                            Section("Authorized administration") {
                                NavigationLink {
                                    TeamAdministrationView(account: account, initialTeamID: team.id)
                                } label: { Label("Manage team", systemImage: "person.badge.key") }
                                Text("Available controls depend on current server permissions.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .navigationTitle("Team home")
                } else if model.isBusy {
                    ProgressView("Loading your team…")
                } else {
                    ContentUnavailableView("Choose your team", systemImage: "person.3",
                        description: Text(account.sessionContextID == nil
                            ? "Sign in through Account to use shared features."
                            : "Choose a server-confirmed team, or request admission with an invitation code."))
                }
            }
            .id(model.selectedTeam?.id)
        }
        .confirmationDialog("Close this team’s screens?", isPresented: $confirmTeamChange, titleVisibility: .visible) {
            Button("Close screens and continue", role: .destructive) {
                if reloadTeamsRequested { Task { await loadTeams() } }
                else if let team = pendingTeam { select(team) }
                pendingTeam = nil
                reloadTeamsRequested = false
            }
            Button("Keep current screens", role: .cancel) {
                pendingTeam = nil
                reloadTeamsRequested = false
            }
        } message: {
            Text("Unsent edits in these screens will close. Saved local and shared drafts remain unchanged.")
        }
        .sheet(isPresented: $showingAdmission) { NavigationStack { TeamAdmissionView(model: model) } }
        .task {
            await account.restoreIfNeeded()
            if account.sessionContextID != nil { await loadTeams() }
        }
    }

    private func loadTeams() async {
        await model.loadTeams()
        if model.teams.count == 1, let team = model.teams.first { await model.selectTeam(team) }
    }

    private func select(_ team: ServerTeam) {
        Task {
            await model.selectTeam(team)
            if model.selectedTeam?.id == team.id { columns = sizeClass == .compact ? .detailOnly : .all }
        }
    }

    private func requestReload() {
        if model.selectedTeam != nil {
            reloadTeamsRequested = true
            confirmTeamChange = true
        } else { Task { await model.reload() } }
    }
}

private struct TeamAdmissionView: View {
    let model: TeamAdministration
    @State private var invitation = ""
    @State private var submittedInvitation = ""
    @State private var confirmClose = false
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    private var hasUnsentCode: Bool { invitation != submittedInvitation }
    var body: some View {
        Form {
            Section("Private invitation") {
                TextField("Team invitation code", text: $invitation)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused)
                Button("Request admission") {
                    focused = false
                    Task {
                        await model.requestAdmission(teamID: invitation)
                        if model.admissionStatus != nil && model.issue == nil { submittedInvitation = invitation }
                    }
                }.disabled(model.isBusy || UUID(uuidString: invitation.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
                Text("Use the code provided by your administrator. A request does not activate membership.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.disabled(model.isBusy)
            if model.isBusy { Section { ProgressView("Requesting admission…") } }
            if let issue = model.issue {
                Section { Label(issue.localizedDescription, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }
            if let confirmation = model.confirmation { Section { Text(confirmation) } }
        }
        .navigationTitle("Team admission")
        .interactiveDismissDisabled(model.isBusy || hasUnsentCode)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { if hasUnsentCode { confirmClose = true } else { dismiss() } }
                    .disabled(model.isBusy)
            }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } }
        }
        .confirmationDialog("Discard the unsent invitation code?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Discard code", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
    }
}

private struct TeamRosterOverview: View {
    let team: ServerTeam
    @State private var model: TeamAdministration
    init(account: BackendAccount, team: ServerTeam) {
        self.team = team
        _model = State(initialValue: TeamAdministration(account: account))
    }
    var body: some View {
        List {
            if model.isBusy { ProgressView("Loading team roster…") }
            if let issue = model.issue {
                Label(issue.localizedDescription, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                Button("Retry") { Task { await model.selectTeam(team) } }.disabled(model.isBusy)
            }
            if model.access == nil {
                Label("Team roster is unavailable. Reload your team to check access.", systemImage: "exclamationmark.triangle")
            } else {
                let active = model.roster.filter { $0.archivedAt == nil }
                if active.isEmpty { ContentUnavailableView("No active roster entries", systemImage: "person.3") }
                ForEach(active) { player in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(player.displayName).font(.headline)
                        Text("Jersey \(player.jerseyNumber)").foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Team roster")
        .task { await model.selectTeam(team) }
    }
}
