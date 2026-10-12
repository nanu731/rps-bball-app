import SwiftUI

struct TeamAdministrationView: View {
    let account: BackendAccount
    @State private var model: TeamAdministration
    private enum AdministrationScreen: String, Hashable { case roster, membership, capabilities, delegation }
    @State private var administrationScreen: AdministrationScreen?
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
                    Button("Roster") { administrationScreen = .roster }.disabled(model.isBusy)
                    if access.can(.membersManage) {
                        Button("Membership") { administrationScreen = .membership }.disabled(model.isBusy)
                    }
                    if !access.grantableCapabilities.isEmpty {
                        Button("Grant or revoke a capability") { administrationScreen = .capabilities }.disabled(model.isBusy)
                    }
                    if access.isOwner {
                        Button("Delegate permission administration") { administrationScreen = .delegation }.disabled(model.isBusy)
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
                    LabeledContent("Last admission response", value: status.rawValue.capitalized)
                    switch status {
                    case .pending: Text("Wait for administrator admission, then reload teams.")
                    case .active: Text("Reload teams and select your team to open its available features.")
                    case .removed: Text("Access is removed. Contact your administrator before requesting admission again.")
                    }
                }
            } header: { Text("Team invitation") } footer: {
                Text("Use the team UUID supplied by your administrator. A request does not activate membership. Actual team setup requires the verified owner account on the server.")
            }.disabled(model.isBusy)
            Section {
                Text("Server roster identities are separate from the temporary local roster. Local records are preserved and are never uploaded by this screen.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Team administration")
        .navigationBarBackButtonHidden(model.isBusy)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { invitationFocused = false }
            }
        }
        .navigationDestination(item: $administrationScreen) { screen in
            switch screen {
            case .roster: AdministrationRosterView(model: model)
            case .membership: AdministrationMembershipView(model: model)
            case .capabilities: AdministrationCapabilityView(model: model)
            case .delegation: AdministrationDelegationView(model: model)
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
        if let issue = model.identityIssue {
            Section {
                Label("Verified account contacts are unavailable.", systemImage: "exclamationmark.triangle")
                Text(issue.localizedDescription).font(.footnote).foregroundStyle(.secondary)
                Text("Account UUIDs remain available; contacts do not determine permissions.").font(.footnote).foregroundStyle(.secondary)
                Button("Retry account contacts") { Task { await model.reload() } }.disabled(model.isBusy)
            }
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
    @State private var editingEntry: ServerRosterEntry?
    @State private var editorPresented = false
    var body: some View {
        List {
            AdministrationFeedback(model: model)
            if model.access?.can(.rosterManage) == true {
                Section { Button("Add actual player") { editingEntry = nil; editorPresented = true }.disabled(model.isBusy) }
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
                                Button("Edit player") { editingEntry = entry; editorPresented = true }.disabled(model.isBusy)
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
        .navigationBarBackButtonHidden(model.isBusy)
        .navigationDestination(isPresented: $editorPresented) { AdministrationRosterEditor(model: model, entry: editingEntry) }
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
    @State private var expectedTeamID: UUID?
    @State private var isSaving = false
    private var isBusy: Bool { model.isBusy || isSaving }
    private var authorizedRoster: Bool { model.access?.can(.rosterManage) == true && model.access?.teamID == expectedTeamID && model.selectedTeam?.id == expectedTeamID }
    @State private var discardTextRequested = false
    @State private var replaceTextRequested = false
    private var hasChanges: Bool { name != (baseEntry?.displayName ?? "") || number != (baseEntry?.jerseyNumber ?? "") }
    private enum Field { case name, number }
    init(model: TeamAdministration, entry: ServerRosterEntry?) {
        self.model = model
        self.entry = entry
        _name = State(initialValue: entry?.displayName ?? "")
        _number = State(initialValue: entry?.jerseyNumber ?? "")
        _baseEntry = State(initialValue: entry)
        _expectedTeamID = State(initialValue: entry?.teamID ?? model.selectedTeam?.id)
    }
    var body: some View {
        Form {
            AdministrationFeedback(model: model)
            if authorizedRoster {
                Section("Player") {
                    TextField("Actual player name", text: $name).focused($focusedField, equals: .name)
                    TextField("Jersey number", text: $number).focused($focusedField, equals: .number)
                    if let entry, let current = model.roster.first(where: { $0.id == entry.id }), current.version != baseEntry?.version {
                        Text("The server has a newer player version. Load its values before saving again.")
                        Button("Load current player values") {
                            focusedField = nil
                            if hasChanges { replaceTextRequested = true } else { loadCurrentValues() }
                        }
                        .confirmationDialog("Replace unsaved player text?", isPresented: $replaceTextRequested, titleVisibility: .visible) {
                            Button("Replace typed text with loaded server values") { loadCurrentValues() }
                            Button("Keep editing", role: .cancel) {}
                        } message: { Text("Your typed name and number will be replaced by the latest loaded player values.") }
                    }
                    Text("Use owner-provided actual roster details. Temporary local identities are not imported.").foregroundStyle(.secondary)
                }.disabled(isBusy)
                Section {
                    Button(entry == nil ? "Add player on server" : "Save player on server") {
                        focusedField = nil
                        let savedEntry = baseEntry, savedName = name, savedNumber = number
                        isSaving = true
                        Task {
                            defer { isSaving = false }
                            if await model.saveRoster(entry: savedEntry, displayName: savedName, jerseyNumber: savedNumber) { dismiss() }
                        }
                    }.disabled(isBusy || !authorizedRoster || !validInput)
                }
            } else {
                Section {
                    Text("Roster editing is unavailable until authorized access to this team reloads. Your typed values remain in memory.").foregroundStyle(.secondary)
                    Button("Reload team access") { Task { await model.reload() } }.disabled(isBusy)
                }
            }
        }
        .navigationTitle(entry == nil ? "Add player" : "Edit player")
        .navigationBarBackButtonHidden(isBusy || hasChanges)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if isBusy || hasChanges {
                    Button("Back", systemImage: "chevron.backward") { focusedField = nil; discardTextRequested = true }
                        .disabled(isBusy)
                        .confirmationDialog("Leave unsaved player text?", isPresented: $discardTextRequested, titleVisibility: .visible) {
                            Button("Discard unsaved text", role: .destructive) { dismiss() }
                            Button("Keep editing", role: .cancel) {}
                        } message: { Text("Leaving discards only this form's unsaved name and number. Saved roster entries and historical records are retained.") }
                }
            }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focusedField = nil } }
        }
    }
    private func loadCurrentValues() {
        guard !isBusy, authorizedRoster, let entry, let current = model.roster.first(where: { $0.id == entry.id && $0.teamID == expectedTeamID }) else { return }
        baseEntry = current; name = current.displayName; number = current.jerseyNumber
    }
    private var validInput: Bool {
        (1...100).contains(name.trimmingCharacters(in: .whitespacesAndNewlines).count) &&
        (1...10).contains(number.trimmingCharacters(in: .whitespacesAndNewlines).count)
    }
}

private struct AdministrationIdentityView: View {
    let model: TeamAdministration
    let userID: UUID
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let identity = model.identity(for: userID) {
                if let email = identity.email { Text("Verified email: \(email)").textSelection(.enabled) }
                if let phone = identity.phone { Text("Verified phone: \(phone)").textSelection(.enabled) }
                if identity.email == nil && identity.phone == nil {
                    Text("No verified contact available").foregroundStyle(.secondary)
                }
            }
            Text("Auth account: \(userID.uuidString)").font(.caption).textSelection(.enabled)
        }
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
            if model.access?.canReadAdministration == true {
                Section("Server membership") {
                    if model.memberships.isEmpty { Text("No membership records returned.").foregroundStyle(.secondary) }
                    ForEach(model.memberships) { member in
                        VStack(alignment: .leading, spacing: 8) {
                            AdministrationIdentityView(model: model, userID: member.userID)
                            Text(member.status.rawValue.capitalized)
                            if member.userID != model.access?.userID && member.userID != model.selectedTeam?.ownerAuthUUID {
                                Button("Choose account") { targetID = member.userID.uuidString; status = member.status }
                            }
                        }.padding(.vertical, 4)
                    }
                }.disabled(model.isBusy)
                if model.access?.can(.membersManage) == true {
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
                    }.disabled(model.isBusy)
                }
            } else {
                Section {
                    Text("Membership data is unavailable. Reload team access before viewing or changing admission.").foregroundStyle(.secondary)
                    if model.issue == nil { Button("Reload team access") { Task { await model.reload() } }.disabled(model.isBusy) }
                }
            }
        }
        .navigationTitle("Membership")
        .navigationBarBackButtonHidden(model.isBusy)
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
            if model.access?.grantableCapabilities.isEmpty == false {
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
                }.disabled(model.isBusy)
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
            } else {
                Section {
                    Text("Authorized team access is unavailable. Reload before viewing or changing these permissions.").foregroundStyle(.secondary)
                    if model.issue == nil { Button("Reload team access") { Task { await model.reload() } }.disabled(model.isBusy) }
                }
            }
        }
        .navigationTitle("Capabilities")
        .navigationBarBackButtonHidden(model.isBusy)
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
                Text(model.identity(for: member.userID)?.label ?? member.userID.uuidString).tag(member.userID.uuidString)
            }
        }
        if let userID = UUID(uuidString: selection) {
            AdministrationIdentityView(model: model, userID: userID)
        }
    }
}

private struct AdministrationDelegationView: View {
    let model: TeamAdministration
    @State private var targetID = ""
    @State private var capabilities: Set<TeamCapability> = []
    @State private var expiry = Date().addingTimeInterval(7 * 86400)
    @State private var isSubmitting = false
    private var isBusy: Bool { model.isBusy || isSubmitting }
    var body: some View {
        Form {
            AdministrationFeedback(model: model)
            if model.access?.isOwner == true {
                Section("Owner-issued delegation") {
                    AdministrationTargetPicker(model: model, selection: $targetID)
                    DatePicker("Expiry", selection: $expiry, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    Text("Select the exact capabilities this account may grant or revoke. Delegation does not grant operational access, allow onward delegation, or change the owner.").foregroundStyle(.secondary)
                    ForEach(TeamCapability.allCases) { capability in
                        Toggle(capability.label, isOn: Binding(get: { capabilities.contains(capability) }, set: { if $0 { capabilities.insert(capability) } else { capabilities.remove(capability) } }))
                    }
                    Button("Create delegation on server") {
                        let submittedTarget = targetID, submittedCapabilities = capabilities, submittedExpiry = expiry
                        isSubmitting = true
                        Task {
                            defer { isSubmitting = false }
                            if await model.delegate(userID: submittedTarget, capabilities: submittedCapabilities, expiry: submittedExpiry) {
                                capabilities.removeAll()
                                targetID = ""
                            }
                        }
                    }.disabled(isBusy || model.access?.isOwner != true || targetID.isEmpty || capabilities.isEmpty)
                }.disabled(isBusy)
                Section("Server delegation records") {
                    if model.delegations.isEmpty { Text("No delegation records.").foregroundStyle(.secondary) }
                    ForEach(model.delegations) { delegation in
                        VStack(alignment: .leading, spacing: 8) {
                            AdministrationIdentityView(model: model, userID: delegation.delegateUserID)
                            ForEach(delegation.allowedCapabilities) { Text($0.label) }
                            if let date = administrationDate(delegation.expiresAt) {
                                Text("Expires \(date.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.secondary)
                            }
                            if delegation.revokedAt != nil { Text("Revoked").foregroundStyle(.secondary) }
                            else {
                                Button("Revoke delegation", role: .destructive) { Task { await model.revokeDelegation(delegation) } }
                                    .disabled(isBusy || model.access?.isOwner != true)
                            }
                        }.padding(.vertical, 4)
                    }
                }
            } else {
                Section {
                    Text("Authorized team access is unavailable. Reload before viewing or changing these permissions.").foregroundStyle(.secondary)
                    if model.issue == nil { Button("Reload team access") { Task { await model.reload() } }.disabled(isBusy) }
                }
            }
        }.navigationTitle("Delegation")
        .navigationBarBackButtonHidden(isBusy)
    }
}
