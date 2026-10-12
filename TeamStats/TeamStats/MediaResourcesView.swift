import SwiftUI

/// Link metadata/review only. External providers open only after an explicit tap.
struct MediaResourcesView: View {
    @State private var model: MediaResources
    private let targetTitle: String
    @State private var editor: MediaResourceVersion?
    @State private var newResourceID = UUID()
    init(teamID: UUID, kind: MediaResourceKind, targetID: UUID, targetTitle: String, account: BackendAccount) {
        _model = State(initialValue: MediaResources(teamID: teamID, kind: kind, targetID: targetID, account: account))
        self.targetTitle = targetTitle
    }
    var body: some View {
        List {
            Section {
                Text(targetTitle).font(.headline)
                Label("Links only — no file uploaded", systemImage: "link")
                Text("A saved link does not verify video ownership, provider access or playback. The provider may require its own login. Share only links you are authorized to share; do not paste private access tokens.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Pending links need owner approval. File uploads and in-app playback are not available.").font(.footnote)
            }
            if let issue = model.issue { Section { mediaError(issue, retry: { Task { await model.load() } }) } }
            if let text = model.confirmation { Section { Label(text, systemImage: "checkmark.circle") } }
            if model.isBusy { ProgressView("Loading or saving links") }
            if model.didLoad {
                Section("Published links") {
                    if model.published.isEmpty { Text("No published links for this \(model.kind == .practice ? "play" : "game").").foregroundStyle(.secondary) }
                    ForEach(model.published) { version in
                        NavigationLink { MediaResourceDetail(model: model, versionID: version.id) } label: { resourceLabel(version) }
                    }
                }
                Section("Your drafts") {
                    ForEach(model.ownDrafts) { version in
                        Button { editor = version } label: { resourceLabel(version) }.buttonStyle(.plain)
                    }
                    if model.ownDrafts.isEmpty { Text("No saved link drafts.").foregroundStyle(.secondary) }
                    if model.canContribute {
                        Button("Add video link", systemImage: "plus") {
                            Task {
                                if let draft = await model.openDraft(resourceID: newResourceID) {
                                    editor = draft; newResourceID = UUID()
                                }
                            }
                        }
                        .disabled(model.isBusy || model.reloadRequired)
                    } else { Text("Game-film contribution needs owner-assigned eligibility.").font(.footnote) }
                }
                if !model.unpublished.isEmpty {
                    Section(model.access?.isOwner == true ? "Owner review and saved history" : "Pending and saved history") {
                        ForEach(model.unpublished) { version in
                            NavigationLink { MediaResourceDetail(model: model, versionID: version.id) } label: { resourceLabel(version) }
                        }
                    }
                }
            } else if !model.isBusy && model.issue == nil { Text("Links have not been loaded.") }
        }
        .navigationTitle(model.kind.label)
        .task { await model.load() }
        .sheet(item: $editor) { draft in
            NavigationStack { MediaResourceEditor(model: model, draft: draft) }
        }
    }
}
private struct MediaResourceDetail: View {
    let model: MediaResources
    let versionID: UUID
    @Environment(\.openURL) private var openURL
    @State private var editor: MediaResourceVersion?
    @State private var reviewReason = ""
    private var version: MediaResourceVersion? { model.versions.first { $0.id == versionID } }
    var body: some View {
        List {
            if let version {
                Section {
                    Text(version.title.isEmpty ? "Untitled draft" : version.title).font(.headline)
                    Label(version.status.label, systemImage: version.status == .published ? "link" : "clock")
                    Text("Saved revision \(version.revision)").font(.footnote).foregroundStyle(.secondary)
                    if !version.notes.isEmpty { Text(version.notes) }
                    if let url = version.externalURL {
                        Text(version.linkURL).textSelection(.enabled)
                        Button("Open provider link", systemImage: "arrow.up.right.square") { openURL(url) }
                            .frame(minHeight: 44)
                        Text("Opens outside TeamStats. Provider login and private video access have not been verified.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else { Text("Video link not entered.") }
                    if !version.reviewReason.isEmpty { LabeledContent("Owner review", value: version.reviewReason) }
                }
                if version.status == .submitted && model.access?.isOwner == true {
                    Section("Owner decision") {
                        TextField("Review reason (optional)", text: $reviewReason, axis: .vertical)
                        Button("Approve link for team viewing", systemImage: "checkmark.circle") { transition(version, "approve") }
                        Button("Reject this revision", systemImage: "xmark.circle") { transition(version, "reject") }
                    }.disabled(model.isBusy || model.reloadRequired || reviewReason.count > 500)
                }
                if model.canContribute && (version.status == .published || (version.status == .rejected && version.authorUserID == model.access?.userID)) {
                    Section {
                        Button("Propose revised link", systemImage: "pencil") {
                            Task { editor = await model.openDraft(resourceID: version.resourceID, source: version) }
                        }.disabled(model.isBusy || model.reloadRequired)
                        Text("The accepted link stays visible while a new private draft is reviewed.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Saved history") {
                    ForEach(model.versions.filter { $0.resourceID == version.resourceID && $0.id != version.id && ($0.status == .published || $0.status == .superseded) }) { historical in
                        NavigationLink { MediaResourceDetail(model: model, versionID: historical.id) } label: { resourceLabel(historical) }
                    }
                }
            } else { Text("This revision is not available with current access. Reload the link list.") }
            if let issue = model.issue { Section { mediaError(issue, retry: { Task { await model.load() } }) } }
            if let text = model.confirmation { Section { Label(text, systemImage: "checkmark.circle") } }
        }
        .navigationTitle("Video link")
        .sheet(item: $editor) { draft in NavigationStack { MediaResourceEditor(model: model, draft: draft) } }
    }
    private func transition(_ version: MediaResourceVersion, _ action: String) {
        Task { _ = await model.transition(version, action: action, reason: reviewReason) }
    }
}
private struct MediaResourceEditor: View {
    let model: MediaResources
    @State private var draft: MediaResourceVersion
    @State private var input: MediaLinkInput
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTyping: Bool
    init(model: MediaResources, draft: MediaResourceVersion) {
        self.model = model; _draft = State(initialValue: draft); _input = State(initialValue: MediaLinkInput(draft))
    }
    private var changed: Bool { input != MediaLinkInput(draft) }
    var body: some View {
        Form {
            Section {
                Label("Private link draft — not uploaded or reviewed", systemImage: "pencil")
                Text("This link is for the selected \(model.kind == .practice ? "published play" : "shared game"). Only the owner approves pending videos.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if model.hasNewerPublishedLink(draft) {
                Section("A newer link was accepted") {
                    Label("This proposal uses an earlier accepted link.", systemImage: "exclamationmark.triangle")
                    Text("Keep your saved proposal read-only and start a draft against the current accepted link. Text you are typing stays in this editor as unsaved changes.").font(.footnote)
                    Button("Preserve saved proposal and resume", systemImage: "arrow.triangle.branch") {
                        Task { if let fresh = await model.resumeDraft(draft) { draft = fresh } }
                    }.disabled(model.isBusy || model.reloadRequired)
                }
            }
            if let issue = model.issue { Section { mediaError(issue, retry: { Task { await reloadDraft() } }) } }
            if let text = model.confirmation { Section { Label(text, systemImage: "checkmark.circle") } }
            Section("Video link") {
                TextField("Title", text: $input.title, axis: .vertical).focused($isTyping)
                TextField("HTTPS provider link", text: $input.linkURL, axis: .vertical)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().focused($isTyping)
                TextField("Notes (optional)", text: $input.notes, axis: .vertical).focused($isTyping)
                if !input.validDraft { Label(MediaResourceIssue.invalidInput.message, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                Text("No provider request occurs while typing or saving. Do not include credentials, access tokens or link fragments.").font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button("Save draft", systemImage: "square.and.arrow.down") { Task { await save() } }
                    .disabled(model.isBusy || model.reloadRequired || !input.validDraft)
                Button("Submit for owner review", systemImage: "paperplane") { Task { await send("submit") } }
                    .disabled(model.isBusy || model.reloadRequired || changed || !input.readyToSubmit)
                if model.canPublishOwn {
                    Button("Publish my link", systemImage: "checkmark.circle") { Task { await send("publish") } }
                        .disabled(model.isBusy || model.reloadRequired || changed || !input.readyToSubmit)
                }
                Text("Save changes before submitting. A published link still requires access through its provider.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Edit video link")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(model.isBusy) }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }.disabled(model.isBusy || model.reloadRequired || !input.validDraft)
            }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { isTyping = false } }
        }
    }
    private func save() async {
        if let saved = await model.save(draft, input: input) { draft = saved }
    }
    private func send(_ action: String) async {
        if await model.transition(draft, action: action) != nil { dismiss() }
    }
    private func reloadDraft() async {
        await model.load()
        if let saved = model.versions.first(where: { $0.id == draft.id && $0.status == .draft }) { draft = saved }
        // Preserve the user's text; reloaded revision enables an explicit subsequent save.
    }
}
private func resourceLabel(_ version: MediaResourceVersion) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(version.title.isEmpty ? "Untitled draft" : version.title)
        Text(version.status.label).font(.footnote).foregroundStyle(.secondary)
    }.frame(minHeight: 44, alignment: .leading)
}
private func mediaError(_ issue: MediaResourceIssue, retry: @escaping () -> Void) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Label(issue.message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
        Button("Reload saved links", action: retry).frame(minHeight: 44)
    }
}
