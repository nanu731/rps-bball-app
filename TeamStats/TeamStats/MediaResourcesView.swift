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
                if !model.contentConcealed { Text(targetTitle).font(.headline) }
                Label(model.kind == .film ? "Full game film stays on Hudl" : "Links only — no file uploaded", systemImage: "link")
                Text(model.kind == .film ? "Add an optional Hudl shortcut for this game. TeamStats admission does not grant Hudl access: sign into Hudl and belong to the team that shared the film. No film is uploaded, embedded or downloaded here." : "A saved link does not verify video ownership, provider access or playback. The provider may require its own login. Share only links you are authorized to share; do not paste private access tokens.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text(model.kind == .film ? "Pending shortcuts need owner approval unless your separate publication capability allows bypass. Saving a shortcut does not verify that the film opens." : "Pending links need owner approval. File uploads and in-app playback are not available.").font(.footnote)
            }
            if let issue = model.issue { Section { mediaError(issue, retry: { Task { await model.load() } }) } }
            if let text = model.confirmation { Section { Label(text, systemImage: "checkmark.circle") } }
            if model.isBusy { ProgressView("Loading or saving links") }
            if model.didLoad {
                Section("Published links") {
                    if model.published.isEmpty {
                        Text("No published links for this \(model.kind == .practice ? "play" : "game").").foregroundStyle(.secondary)
                        Text(model.canContribute ? "Add a link draft below, then save and submit it for owner review." : "Ask the team owner about publishing a video link.").font(.footnote).foregroundStyle(.secondary)
                    }
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
                        Button(model.kind == .film ? "Add Hudl shortcut" : "Add video link", systemImage: "plus") {
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
        .disabled(model.isBusy)
        .navigationTitle(model.kind.label)
        .navigationBarBackButtonHidden(model.isBusy)
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
    @State private var confirmLeave = false
    @Environment(\.dismiss) private var dismiss
    private var version: MediaResourceVersion? { model.versions.first { $0.id == versionID } }
    var body: some View {
        List {
            if model.isBusy { ProgressView("Contacting video-link server…") }
            if let version {
                Section {
                    Text(version.title.isEmpty ? "Untitled draft" : version.title).font(.headline)
                    Label(version.status.label, systemImage: version.status == .published ? "link" : "clock")
                    Text("Saved revision \(version.revision)").font(.footnote).foregroundStyle(.secondary)
                    if !version.notes.isEmpty { Text(version.notes) }
                    if let url = version.externalURL {
                        Text(version.linkURL).textSelection(.enabled)
                        if model.kind == .film && MediaLinkInput.hudlURL(version.linkURL) == nil {
                            Label("Saved earlier provider link — not a supported Hudl shortcut", systemImage: "clock.arrow.circlepath")
                                .font(.footnote)
                        }
                        Button(model.kind == .film && MediaLinkInput.hudlURL(version.linkURL) != nil ? "Open Hudl" : "Open saved provider link", systemImage: "arrow.up.right.square") { openURL(url) }
                            .frame(minHeight: 44)
                        Text(model.kind == .film ? "Opens outside TeamStats. Hudl independently controls sign-in and film access. An unavailable or denied film must be resolved with the sharing team in Hudl." : "Opens outside TeamStats. Provider login and private video access have not been verified.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else { Text("Video link not entered.") }
                    if !version.reviewReason.isEmpty { LabeledContent("Owner review", value: version.reviewReason) }
                }
                if version.status == .submitted && model.access?.isOwner == true {
                    Section("Owner decision") {
                        TextField("Review reason (optional)", text: $reviewReason, axis: .vertical)
                        if !MediaLinkInput(version).readyToSubmit(for: model.kind) {
                            Label("This earlier link cannot be newly approved as a Hudl shortcut. Reject it with guidance to submit a supported Hudl link.", systemImage: "exclamationmark.triangle")
                        }
                        Button("Approve link for team viewing", systemImage: "checkmark.circle") { transition(version, "approve") }
                            .disabled(!MediaLinkInput(version).readyToSubmit(for: model.kind))
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
        .disabled(model.isBusy)
        .navigationTitle(model.kind == .film ? "Hudl shortcut" : "Video link")
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(model.isBusy || !reviewReason.isEmpty)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", systemImage: "chevron.left") {
                    if reviewReason.isEmpty { dismiss() } else { confirmLeave = true }
                }.disabled(model.isBusy)
            }
        }
        .confirmationDialog("Leave this review?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Keep editing", role: .cancel) {}
            Button("Discard unsent review reason", role: .destructive) { dismiss() }
        } message: {
            Text("The review reason has not been sent. Saved links and review decisions remain unchanged.")
        }
        .sheet(item: $editor) { draft in NavigationStack { MediaResourceEditor(model: model, draft: draft) } }
    }
    private func transition(_ version: MediaResourceVersion, _ action: String) {
        Task { if await model.transition(version, action: action, reason: reviewReason) != nil { reviewReason = "" } }
    }
}
private struct MediaResourceEditor: View {
    let model: MediaResources
    @State private var draft: MediaResourceVersion
    @State private var input: MediaLinkInput
    @State private var attachmentCandidate: MediaResourceVersion?
    @State private var confirmAttachment = false
    @State private var attachmentIssue: String?
    @State private var confirmLeave = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTyping: Bool
    init(model: MediaResources, draft: MediaResourceVersion) {
        self.model = model; _draft = State(initialValue: draft); _input = State(initialValue: MediaLinkInput(draft))
    }
    private var changed: Bool { input != MediaLinkInput(draft) }
    private var protectedContentUnavailable: Bool { model.contentConcealed || (model.didLoad && !model.versions.contains { $0.id == draft.id }) }
    var body: some View {
        Form {
            if model.isBusy { Section { ProgressView("Contacting video-link server…") } }
            if protectedContentUnavailable {
                Section {
                    Label("This draft is unavailable with current access. Retained text is hidden.", systemImage: "lock")
                    Button("Reload and check access") { Task { await reloadDraft() } }.disabled(model.isBusy)
                    if let issue = model.issue { Label(issue.message, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
            } else {
                Section {
                    Label("Private link draft — not uploaded or reviewed", systemImage: "pencil")
                    Text("This link is for the selected \(model.kind == .practice ? "published play" : "shared game"). Only the owner approves pending videos.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if draft.status == .superseded {
                    Section("Saved proposal was preserved") {
                        Label("This saved revision is read-only.", systemImage: "doc.text")
                        if let recovered = model.recoveredDraft(after: draft) {
                            Text("The server already created its replacement draft. Your typed text is still retained here and has not been saved to that draft.").font(.footnote)
                            Button("Attach typed changes to recovered draft", systemImage: "arrow.triangle.branch") {
                                attachmentCandidate = recovered; confirmAttachment = true
                            }
                        } else {
                            Text("No unique, current, eligible replacement draft can be attached. Reload and compare saved revisions; do not repeat the recovery request.").font(.footnote)
                            Button("Reload saved links") { Task { await reloadDraft() } }.disabled(model.isBusy)
                        }
                    }
                }
                if let attachmentIssue { Section { Label(attachmentIssue, systemImage: "exclamationmark.triangle").foregroundStyle(.red) } }
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
                    TextField(model.kind == .film ? "HTTPS Hudl link" : "HTTPS provider link", text: $input.linkURL, axis: .vertical)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().focused($isTyping)
                    TextField("Notes (optional)", text: $input.notes, axis: .vertical).focused($isTyping)
                    if !input.validDraft(for: model.kind) { Label(model.kind == .film ? "Use a safe HTTPS link on hudl.com or www.hudl.com, or leave the link blank for a draft. Check title and notes limits." : MediaResourceIssue.invalidInput.message, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                    Text(model.kind == .film ? "Supported hosts: hudl.com and www.hudl.com. No provider request occurs while typing or saving. Leave the link blank if not yet available; never include credentials, access tokens or fragments." : "No provider request occurs while typing or saving. Do not include credentials, access tokens or link fragments.").font(.footnote).foregroundStyle(.secondary)
                }.disabled(model.isBusy)
                Section {
                    Button("Save draft", systemImage: "square.and.arrow.down") { Task { await save() } }
                        .disabled(model.isBusy || model.reloadRequired || protectedContentUnavailable || draft.status != .draft || !input.validDraft(for: model.kind))
                    Button("Submit for owner review", systemImage: "paperplane") { Task { await send("submit") } }
                        .disabled(model.isBusy || model.reloadRequired || draft.status != .draft || changed || !input.readyToSubmit(for: model.kind))
                    if model.canPublishOwn {
                        Button("Publish my link", systemImage: "checkmark.circle") { Task { await send("publish") } }
                            .disabled(model.isBusy || model.reloadRequired || draft.status != .draft || changed || !input.readyToSubmit(for: model.kind))
                    }
                    Text("Save changes before submitting. A published link still requires access through its provider.").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: model.contentConcealed) { _, concealed in if concealed { isTyping = false } }
        .navigationTitle(model.kind == .film ? "Edit Hudl shortcut" : "Edit video link")
        .interactiveDismissDisabled(model.isBusy || changed)
        .confirmationDialog("Close this draft?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Keep editing", role: .cancel) {}
            Button("Discard unsaved text", role: .destructive) { dismiss() }
        } message: {
            Text("Only this screen's unsaved text will be discarded. Saved links and their history remain unchanged.")
        }
        .alert("Attach retained text?", isPresented: $confirmAttachment, presenting: attachmentCandidate) { candidate in
            Button("Attach — keep changes unsaved") {
                if let current = model.recoveredDraft(after: draft, expectedID: candidate.id, expectedRevision: candidate.revision) {
                    draft = current; attachmentIssue = nil
                    // Only revision identity changes. The input buffer remains untouched; Save is separate.
                } else { attachmentIssue = "The replacement draft or current access changed. Reload and compare before attaching." }
            }
            Button("Cancel", role: .cancel) { }
        } message: { candidate in
            Text("Attach your retained typed text to the exact recovered draft, saved revision \(candidate.revision). This does not save or publish changes. The saved earlier proposal remains read-only.")
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { if changed { confirmLeave = true } else { dismiss() } }.disabled(model.isBusy) }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }.disabled(model.isBusy || model.reloadRequired || protectedContentUnavailable || draft.status != .draft || !input.validDraft(for: model.kind))
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
        if let saved = model.versions.first(where: { $0.id == draft.id }) { draft = saved }
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
