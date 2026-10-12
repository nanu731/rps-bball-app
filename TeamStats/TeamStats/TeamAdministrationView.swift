import SwiftUI

struct TeamAdministrationView: View {
    let account: BackendAccount
    @State private var model: TeamAdministration
    @State private var invitationID = ""
    @FocusState private var invitationFocused: Bool

    init(account: BackendAccount) {
        self.account = account
        _model = State(initialValue: TeamAdministration(account: account))
    }

    var body: some View {
        Form {
            AdministrationFeedback(model: model)
            Section("Teams") {
                if model.teams.isEmpty && model.didLoadTeams {
                    Text("No active team is available from the server.").foregroundStyle(.secondary)
                } else if !model.didLoadTeams && !model.isBusy {
                    Text("The team list has not loaded. Reload to check server data.").foregroundStyle(.secondary)
                }
                ForEach(model.teams) { team in
                    Button {
                        invitationFocused = false
                        Task { await model.selectTeam(team) }
                    } label: {
                        HStack {
                            Text(team.name)
                            Spacer()
                            if model.selectedTeam?.id == team.id { Image(systemName: "checkmark").accessibilityLabel("Selected") }
                        }
                    }
                    .disabled(model.isBusy)
                }
                Button("Reload teams") { Task { await model.loadTeams() } }.disabled(model.isBusy)
            }
            if let team = model.selectedTeam, let access = model.access {
                Section(team.name) {
                    Text(access.isOwner ? "Owner access confirmed by server" : "Active membership confirmed by server")
                    if access.can(.membersManage) {
                        LabeledContent("Team invitation code") {
                            Text(team.id.uuidString).font(.caption).textSelection(.enabled)
                        }
                        Text("Share this code privately. A join request still needs administrator admission.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    NavigationLink("Shared games and statistics") {
                        ConnectedGamesView(account: account, teamID: team.id)
                    }
                    NavigationLink("Playbook") { PlaybookView(account: account, teamID: team.id) }
                    NavigationLink("Roster") { AdministrationRosterView(model: model) }
                    if access.can(.membersManage) {
                        NavigationLink("Membership") { AdministrationMembershipView(model: model) }
                    }
                    if !access.grantableCapabilities.isEmpty {
                        NavigationLink("Grant or revoke a capability") { AdministrationCapabilityView(model: model) }
                    }
                    if access.isOwner {
                        NavigationLink("Delegate permission administration") { AdministrationDelegationView(model: model) }
                    }
                    if !access.isOwner {
                        ForEach(access.capabilities) { capability in Text(capability.label).foregroundStyle(.secondary) }
                    }
                }
            }
            Section {
                TextField("Invitation team UUID", text: $invitationID)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($invitationFocused)
                Button("Request admission") {
                    invitationFocused = false
                    Task { await model.requestAdmission(teamID: invitationID) }
                }.disabled(model.isBusy || UUID(uuidString: invitationID.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
                if let status = model.admissionStatus {
                    Text("Your server status: \(status.rawValue)")
                }
            } header: { Text("Team invitation") } footer: {
                Text("Use the team UUID supplied by your administrator. A request does not activate membership. Actual team setup requires the verified owner account on the server.")
            }
            Section {
                Text("Server roster identities are separate from the temporary local roster. Local records are preserved and are never uploaded by this screen.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Team administration")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { invitationFocused = false }
            }
        }
        .task(id: account.verifiedUserID) { await model.loadTeams() }
    }
}

private struct AdministrationFeedback: View {
    let model: TeamAdministration
    var body: some View {
        if model.isBusy {
            Section { ProgressView("Contacting team server…") }
        }
        if let issue = model.issue {
            Section {
                Label(issue.localizedDescription, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).accessibilityIdentifier("administration.error")
                Button("Reload / Retry") { Task { await model.reload() } }
                    .disabled(model.isBusy)
            }
        }
        if let confirmation = model.confirmation {
            Section { Label(confirmation, systemImage: "checkmark.circle") }
        }
    }
}

private struct AdministrationRosterView: View {
    let model: TeamAdministration
    @State private var archiveCandidate: ServerRosterEntry?
    var body: some View {
        List {
            AdministrationFeedback(model: model)
            if model.access?.can(.rosterManage) == true {
                Section { NavigationLink("Add actual player") { AdministrationRosterEditor(model: model, entry: nil) } }
            }
            if model.access == nil {
                Section {
                    Text("Roster data is unavailable until the team reloads successfully.")
                        .foregroundStyle(.secondary)
                    Button("Reload team") { Task { await model.reload() } }.disabled(model.isBusy)
                }
            } else {
                Section("Active roster") {
                    let entries = model.roster.filter { $0.archivedAt == nil }
                    if entries.isEmpty { Text("No actual server roster entries.").foregroundStyle(.secondary) }
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.displayName).font(.headline)
                            Text("Jersey \(entry.jerseyNumber)")
                            if model.access?.can(.rosterManage) == true {
                                NavigationLink("Edit player") { AdministrationRosterEditor(model: model, entry: entry) }
                                Button("Archive player", role: .destructive) { archiveCandidate = entry }
                                    .disabled(model.isBusy)
                            }
                        }.padding(.vertical, 4)
                    }
                }
                Section("Archived roster") {
                    let entries = model.roster.filter { $0.archivedAt != nil }
                    if entries.isEmpty { Text("No archived entries.").foregroundStyle(.secondary) }
                    ForEach(entries) { entry in
                        VStack(alignment: .leading) {
                            Text(entry.displayName)
                            Text("Jersey \(entry.jerseyNumber) • Archived").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Roster")
        .confirmationDialog("Archive this player?", isPresented: Binding(get: { archiveCandidate != nil }, set: { if !$0 { archiveCandidate = nil } }), titleVisibility: .visible) {
            if let entry = archiveCandidate {
                Button("Archive player", role: .destructive) {
                    archiveCandidate = nil
                    Task { await model.archiveRoster(entry) }
                }
            }
            Button("Cancel", role: .cancel) { archiveCandidate = nil }
        } message: { Text("The player leaves the active roster. Their stable identity and historical records are retained.") }
    }
}

private struct AdministrationRosterEditor: View {
    let model: TeamAdministration
    let entry: ServerRosterEntry?
    @State private var name: String
    @State private var number: String
    @FocusState private var focusedField: Field?
    @Environment(\.dismiss) private var dismiss
    @State private var baseEntry: ServerRosterEntry?
    private enum Field { case name, number }
    init(model: TeamAdministration, entry: ServerRosterEntry?) {
        self.model = model
        self.entry = entry
        _name = State(initialValue: entry?.displayName ?? "")
        _number = State(initialValue: entry?.jerseyNumber ?? "")
        _baseEntry = State(initialValue: entry)
    }
    var body: some View {
        Form {
            AdministrationFeedback(model: model)
            Section("Player") {
                TextField("Actual player name", text: $name).focused($focusedField, equals: .name)
                TextField("Jersey number", text: $number).focused($focusedField, equals: .number)
                if let entry, let current = model.roster.first(where: { $0.id == entry.id }), current.version != baseEntry?.version {
                    Text("The server has a newer player version. Load its values before saving again.")
                    Button("Load current player values") {
                        baseEntry = current
                        name = current.displayName
                        number = current.jerseyNumber
                    }
                }
                Text("Use owner-provided actual roster details. Temporary local identities are not imported.").foregroundStyle(.secondary)
            }
            Section {
                Button(entry == nil ? "Add player on server" : "Save player on server") {
                    focusedField = nil
                    Task {
                        if await model.saveRoster(entry: baseEntry, displayName: name, jerseyNumber: number) { dismiss() }
                    }
                }.disabled(model.isBusy || model.access == nil || !validInput)
            }
        }
        .navigationTitle(entry == nil ? "Add player" : "Edit player")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focusedField = nil } }
        }
    }
    private var validInput: Bool {
        (1...100).contains(name.trimmingCharacters(in: .whitespacesAndNewlines).count) &&
        (1...10).contains(number.trimmingCharacters(in: .whitespacesAndNewlines).count)
    }
}

private struct AdministrationMembershipView: View {
    let model: TeamAdministration
    @State private var targetID = ""
    @State private var status: TeamMembershipStatus = .pending
    @State private var removalRequested = false
    @FocusState private var focused: Bool
    var body: some View {
        Form {
            AdministrationFeedback(model: model)
            Section("Server membership") {
                if model.memberships.isEmpty { Text("No membership records returned.").foregroundStyle(.secondary) }
                ForEach(model.memberships) { member in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(member.userID.uuidString).font(.caption).textSelection(.enabled)
                        Text(member.status.rawValue.capitalized)
                        if member.userID != model.access?.userID && member.userID != model.selectedTeam?.ownerAuthUUID {
                            Button("Choose account") { targetID = member.userID.uuidString; status = member.status }
                        }
                    }.padding(.vertical, 4)
                }
            }
            Section {
                TextField("Verified Auth account UUID", text: $targetID)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused)
                Picker("Membership status", selection: $status) {
                    ForEach(TeamMembershipStatus.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                Button("Save membership on server") {
                    focused = false
                    if status == .removed { removalRequested = true }
                    else { Task { await model.setMembership(userID: targetID, status: status) } }
                }.disabled(model.isBusy || model.access == nil || UUID(uuidString: targetID) == nil)
            } header: { Text("Change admission") } footer: {
                Text("Use an Auth UUID confirmed by your administrator, never an email-derived role. The server verifies the account. You cannot change yourself or the owner. Pending or removed membership revokes previous grants and delegations.")
            }
        }
        .navigationTitle("Membership")
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } } }
        .confirmationDialog("Remove this member's access?", isPresented: $removalRequested, titleVisibility: .visible) {
            Button("Remove membership", role: .destructive) { Task { await model.setMembership(userID: targetID, status: .removed) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Previous capability grants and permission delegations are revoked. Historical records remain.") }
    }
}

private struct AdministrationCapabilityView: View {
    let model: TeamAdministration
    @State private var targetID = ""
    @State private var capability: TeamCapability = .statsReview
    @State private var enabled = true
    @State private var hasExpiry = true
    @State private var expiry = Date().addingTimeInterval(86400)
    private var grantable: [TeamCapability] { model.access?.grantableCapabilities ?? [] }
    var body: some View {
        Form {
            AdministrationFeedback(model: model)
            Section("One capability") {
                AdministrationTargetPicker(model: model, selection: $targetID)
                Picker("Capability", selection: $capability) {
                    ForEach(grantable) { Text($0.label).tag($0) }
                }
                Picker("Action", selection: $enabled) {
                    Text("Grant").tag(true)
                    Text("Revoke").tag(false)
                }
                if enabled {
                    if model.access?.isOwner == true { Toggle("Set expiry", isOn: $hasExpiry) }
                    if hasExpiry || model.access?.isOwner != true {
                        DatePicker("Expiry", selection: $expiry, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    }
                }
                Button(enabled ? "Grant capability on server" : "Revoke capability on server") {
                    Task { await model.setCapability(userID: targetID, capability: capability, enabled: enabled, expiry: enabled && (hasExpiry || model.access?.isOwner != true) ? expiry : nil) }
                }.disabled(model.isBusy || model.access == nil || targetID.isEmpty || !grantable.contains(capability))
            }
            Section {
                Text("Operational permission and permission to grant it are separate. Delegated grants must expire within your owner-issued envelope. The server rechecks authority on every change.").foregroundStyle(.secondary)
            }
            if model.access?.isOwner == false {
                Section("Your delegation limits") {
                    ForEach(model.access?.grantEnvelopes ?? []) { envelope in
                        ForEach(envelope.allowedCapabilities) { Text($0.label) }
                        if let date = envelope.expiry {
                            Text("Grant expiry must be no later than \(date.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Recorded grants for selected account") {
                ForEach(model.grants.filter { $0.userID.uuidString == targetID }) { grant in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(grant.capability.label)
                        Text(grant.revokedAt == nil ? "Recorded grant; effective access is rechecked by server" : "Revoked").font(.caption).foregroundStyle(.secondary)
                        if let expiry = grant.expiresAt, let date = administrationDate(expiry) { Text(date, style: .date).font(.caption) }
                    }
                }
            }
        }
        .navigationTitle("Capabilities")
        .onAppear { if let first = grantable.first { capability = first } }
    }
}

private struct AdministrationTargetPicker: View {
    let model: TeamAdministration
    @Binding var selection: String
    var body: some View {
        Picker("Active Auth account", selection: $selection) {
            Text("Choose an account").tag("")
            ForEach(model.memberships.filter { $0.status == .active && $0.userID != model.access?.userID && $0.userID != model.selectedTeam?.ownerAuthUUID }) { member in
                Text(member.userID.uuidString).tag(member.userID.uuidString)
            }
        }
    }
}

private struct AdministrationDelegationView: View {
    let model: TeamAdministration
    @State private var targetID = ""
    @State private var capabilities: Set<TeamCapability> = []
    @State private var expiry = Date().addingTimeInterval(7 * 86400)
    var body: some View {
        Form {
            AdministrationFeedback(model: model)
            Section("Owner-issued delegation") {
                AdministrationTargetPicker(model: model, selection: $targetID)
                DatePicker("Expiry", selection: $expiry, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                Text("Select the exact capabilities this account may grant or revoke. Delegation does not grant operational access, allow onward delegation, or change the owner.").foregroundStyle(.secondary)
                ForEach(TeamCapability.allCases) { capability in
                    Toggle(capability.label, isOn: Binding(get: { capabilities.contains(capability) }, set: { if $0 { capabilities.insert(capability) } else { capabilities.remove(capability) } }))
                }
                Button("Create delegation on server") {
                    Task {
                        if await model.delegate(userID: targetID, capabilities: capabilities, expiry: expiry) {
                            capabilities.removeAll()
                            targetID = ""
                        }
                    }
                }.disabled(model.isBusy || model.access?.isOwner != true || targetID.isEmpty || capabilities.isEmpty)
            }
            Section("Server delegation records") {
                if model.delegations.isEmpty { Text("No delegation records.").foregroundStyle(.secondary) }
                ForEach(model.delegations) { delegation in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(delegation.delegateUserID.uuidString).font(.caption).textSelection(.enabled)
                        ForEach(delegation.allowedCapabilities) { Text($0.label) }
                        if let date = administrationDate(delegation.expiresAt) {
                            Text("Expires \(date.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.secondary)
                        }
                        if delegation.revokedAt != nil { Text("Revoked").foregroundStyle(.secondary) }
                        else {
                            Button("Revoke delegation", role: .destructive) { Task { await model.revokeDelegation(delegation) } }
                                .disabled(model.isBusy || model.access?.isOwner != true)
                        }
                    }.padding(.vertical, 4)
                }
            }
        }.navigationTitle("Delegation")
    }
}
