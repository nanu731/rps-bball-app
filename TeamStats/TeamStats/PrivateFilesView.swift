import SwiftUI
import UniformTypeIdentifiers
import AVKit
import PDFKit

// One cache lock for all UI destinations sharing the same on-device namespace.
enum DeviceClipLibrary { static let storage = ClipRetention() }

struct PrivateFilesView: View {
    let targetTitle: String
    let account: BackendAccount
    @State private var model: PrivateFiles
    @State private var editing: FileEditorSelection?

    init(teamID: UUID, kind: PrivateFileKind, targetID: UUID, targetTitle: String, account: BackendAccount) {
        self.targetTitle = targetTitle
        self.account = account
        _model = State(initialValue: PrivateFiles(teamID: teamID, kind: kind, targetID: targetID,
            account: account, retention: DeviceClipLibrary.storage))
    }

    var body: some View {
        List {
            Section {
                Text(targetTitle).font(.headline)
                Text("Choosing a file does not publish it. Shared files require trusted validation and the applicable owner review or publication permission.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if model.isBusy { ProgressView("Checking saved files…") }
            if let issue = model.issue {
                Section {
                    Label(issue.message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    Button("Reload saved files") { Task { await model.load() } }.disabled(model.isBusy)
                }
            }
            if let confirmation = model.confirmation {
                Label(confirmation, systemImage: "checkmark.circle").foregroundStyle(.secondary)
            }
            if model.didLoad && !model.contentConcealed {
                Section("Published files") {
                    if model.published.isEmpty {
                        Text("No published files are available for this \(model.kind == .practice ? "play" : "game").")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.published) { version in
                        NavigationLink { FileRecordView(model: model, initial: version, account: account) } label: { fileLabel(version) }
                    }
                }
                if model.canContribute {
                    Section("Your drafts") {
                        Button("Choose a new \(model.kind == .practice ? "practice clip" : "scouting PDF")", systemImage: "plus") {
                            editing = FileEditorSelection()
                        }.frame(minHeight: 44).disabled(model.isBusy || model.reloadRequired)
                        ForEach(model.ownDrafts) { version in
                            Button { editing = FileEditorSelection(version: version) } label: { fileLabel(version) }
                                .disabled(model.isBusy)
                        }
                    }
                }
                let other = model.versions.filter { !model.ownDrafts.map(\.id).contains($0.id) && !model.published.map(\.id).contains($0.id) }
                if !other.isEmpty {
                    Section(model.access?.isOwner == true ? "Review and saved history" : "Your submitted files") {
                        ForEach(other) { version in
                            NavigationLink { FileRecordView(model: model, initial: version, account: account) } label: { fileLabel(version) }
                        }
                    }
                }
            }
        }
        .navigationTitle(model.kind.label)
        .task { if !model.didLoad { await model.load() } }
        .sheet(item: $editing) { selection in
            NavigationStack { FileDraftEditor(model: model, selection: selection) }
        }
    }

    private func fileLabel(_ version: PrivateFileVersion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(version.title.isEmpty ? "Untitled file draft" : version.title).font(.headline)
            Text(version.status.fileLabel).font(.subheadline).foregroundStyle(.secondary)
        }.padding(.vertical, 8)
    }
}

private struct FileEditorSelection: Identifiable {
    let id = UUID()
    var version: PrivateFileVersion?
    var replacing: PrivateFileResource?
}

private struct FileDraftEditor: View {
    let model: PrivateFiles
    @Environment(\.dismiss) private var dismiss
    @State private var version: PrivateFileVersion?
    @State private var replacing: PrivateFileResource?
    @State private var input: PrivateFileInput
    @State private var savedInput: PrivateFileInput
    @State private var bytes: Data?
    @State private var choosingFile = false
    @State private var preparing = false
    @State private var preparationError: String?
    @State private var confirmClose = false
    @FocusState private var focused: Bool

    init(model: PrivateFiles, selection: FileEditorSelection) {
        self.model = model
        _version = State(initialValue: selection.version)
        _replacing = State(initialValue: selection.replacing)
        let value = selection.version.map(PrivateFileInput.init) ?? PrivateFileInput()
        _input = State(initialValue: value)
        _savedInput = State(initialValue: value)
    }
    private var busy: Bool { model.isBusy || preparing }
    private var changed: Bool { input != savedInput || bytes != nil }
    private var editable: Bool {
        guard model.canContribute else { return false }
        guard let version else { return true }
        return version.authorUserID == model.access?.userID && [.uploading, .ready].contains(version.status)
    }
    private var draftVisible: Bool {
        guard model.didLoad && !model.contentConcealed else { return false }
        if let version { return model.versions.contains { $0.id == version.id } }
        return model.canContribute
    }

    var body: some View {
        Form {
            if let issue = model.issue {
                Section {
                    Label(issue.message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    Button("Reload saved state; keep typed text") { Task { await model.load() } }.disabled(busy)
                }
            }
            if model.isBusy && !model.didLoad {
                ProgressView("Checking saved draft access…")
            } else if !draftVisible {
                if model.contentConcealed || model.didLoad {
                    Label("Current access does not allow this draft to be displayed.", systemImage: "lock")
                } else { Text("The saved draft is unavailable until loading succeeds. Typed input is preserved.").foregroundStyle(.secondary) }
                if model.issue == nil { Button("Reload saved state") { Task { await model.load() } }.disabled(busy) }
            } else {
                if let version, let refreshed = model.versions.first(where: { $0.id == version.id }), refreshed.revision != version.revision {
                    Section("Compare refreshed version") {
                        LabeledContent("Saved title", value: refreshed.title.isEmpty ? "Not entered" : refreshed.title)
                        Text(refreshed.status.fileLabel).foregroundStyle(.secondary)
                        if !refreshed.notes.isEmpty { LabeledContent("Saved notes", value: refreshed.notes) }
                        Button("Use refreshed revision after comparing") { self.version = refreshed; savedInput = PrivateFileInput(refreshed) }
                            .disabled(busy)
                    }
                }
                if version == nil && model.hasPendingReservation {
                    Section("Unconfirmed reservation") {
                        Button("Reconcile saved reservation") {
                            Task { if let reserved = await model.retryReservation() { accept(reserved) } }
                        }.disabled(busy)
                        Text("This retries the same reservation identity without sending the file again. Recover it before choosing a different file.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let preparationError { Label(preparationError, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                if busy { ProgressView(preparing ? "Preparing selected file…" : "Waiting for server confirmation…") }
                Section("File draft") {
                    if let version { Text(version.status.fileLabel).foregroundStyle(.secondary) }
                    TextField("Title (may be blank in a draft)", text: $input.title).focused($focused).disabled(!editable || busy)
                    TextField("Notes", text: $input.notes, axis: .vertical).focused($focused).disabled(!editable || busy)
                    if !input.validDraft {
                        Label("Use at most 120 title characters and 1,000 note characters without unsupported control characters.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                    if version == nil {
                        Button(bytes == nil ? "Choose file" : "Choose a different file") { focused = false; choosingFile = true }
                            .frame(minHeight: 44).disabled(busy || model.hasPendingReservation)
                        if let bytes { LabeledContent("Selected file", value: ByteCountFormatter.string(fromByteCount: Int64(bytes.count), countStyle: .file)) }
                    }
                    Text(model.kind == .practice
                        ? "MP4 with H.264 video and optional AAC audio; up to 10 MiB, 30 seconds and 1920 × 1080 in either orientation. Originals are not compressed."
                        : "Readable PDF up to 5 MiB, without encryption, active actions, forms or attachments. Trusted validation runs after upload.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let version, version.status == .uploading {
                    Section("Unconfirmed upload") {
                        Text("Check the stored outcome before another upload. This does not repeat the file transfer.")
                        if model.pendingVersion?.id == version.id && !model.uploadNeedsReconciliation && bytes != nil {
                            Button("Upload reserved file") {
                                Task {
                                    if let result = await model.upload() {
                                        accept(result); savedInput = PrivateFileInput(result); bytes = nil
                                    }
                                }
                            }.disabled(busy)
                        }
                        Button("Reconcile saved upload") {
                            Task {
                                if let result = await model.reconcile(version) {
                                    accept(result); savedInput = PrivateFileInput(result); bytes = nil
                                }
                            }
                        }
                            .disabled(busy)
                    }
                }
                if let version, version.status == .ready && editable {
                    Section("Submit saved file") {
                        Text("Save title and notes before submitting. Publication is confirmed only by the server.").font(.footnote).foregroundStyle(.secondary)
                        Button("Submit for owner review") { transition(version, .submit) }.disabled(busy || changed || input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if model.canPublishOwn {
                            Button("Publish own clip without review") { transition(version, .publish) }.disabled(busy || changed || input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                if version?.status == .failed || model.issue == .missingUpload {
                    Section {
                        Text("The earlier draft is preserved. Create a new draft for a missing or rejected file; a new upload uses additional storage allowance.")
                        Button("Prepare a new draft") {
                            replacing = model.resources.first { $0.id == version?.resourceID }
                            version = nil
                        }.disabled(busy || !model.canContribute)
                    }
                }
            }
        }
        .navigationTitle(version == nil ? "New file draft" : "Saved file draft")
        .scrollDismissesKeyboard(.interactively)
        .interactiveDismissDisabled(changed || busy)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { focused = false; if changed { confirmClose = true } else { dismiss() } }.disabled(busy)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save draft") { focused = false; Task { await save() } }
                    .disabled(busy || !editable || !input.validDraft || model.reloadRequired || (version == nil && bytes == nil) || model.contentConcealed)
            }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } }
        }
        .confirmationDialog("Close without saving unsent changes?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Discard unsent changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        } message: { Text("Saved records and original files remain unchanged.") }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: model.kind == .practice ? [.mpeg4Movie] : [.pdf]) { result in
            switch result {
            case .failure(let error): preparationError = error.localizedDescription
            case .success(let url):
                preparing = true; preparationError = nil
                let kind = model.kind
                Task {
                    defer { preparing = false }
                    do {
                        bytes = try await Task.detached {
                            let scoped = url.startAccessingSecurityScopedResource()
                            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                            if kind == .practice { return try await PracticeClipDocument.read(url).bytes }
                            return try ScoutingReportDocument.read(url).bytes
                        }.value
                    } catch { preparationError = "The selected file could not be prepared. \(error.localizedDescription)" }
                }
            }
        }
    }

    private func accept(_ result: PrivateFileVersion) {
        version = result
        // Reconciliation refreshes revision/status, never silently replaces typed text.
    }
    private func transition(_ version: PrivateFileVersion, _ action: PrivateFileAction) {
        Task { if let result = await model.transition(version, action: action) { accept(result) } }
    }
    private func save() async {
        if let version {
            if let saved = await model.save(version, input: input) { accept(saved); savedInput = input }
        } else if let bytes {
            guard let reserved = await model.reserve(data: bytes, input: input, replacing: replacing) else { return }
            version = reserved
            savedInput = input
            if let saved = await model.upload() { accept(saved); savedInput = PrivateFileInput(saved); self.bytes = nil }
        }
    }
}

private struct FileRecordView: View {
    let model: PrivateFiles
    let initial: PrivateFileVersion
    let account: BackendAccount
    @Environment(\.dismiss) private var dismiss
    @State private var preview: LocalFilePreview?
    @State private var reason = ""
    @State private var replacement: FileEditorSelection?
    @State private var confirmArchive = false
    @State private var confirmClose = false
    @State private var savedReason = ""
    @FocusState private var focused: Bool
    private var current: PrivateFileVersion? { model.versions.first { $0.id == initial.id } }
    private var changed: Bool { reason != savedReason }

    var body: some View {
        Form {
            if let issue = model.issue {
                Section {
                    Label(issue.message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    Button("Reload saved files; keep review text") { Task { await model.load() } }.disabled(model.isBusy)
                }
            }
            if model.isBusy && !model.didLoad {
                ProgressView("Loading saved file…")
            } else if model.didLoad, !model.contentConcealed, let current {
                if model.isBusy { ProgressView("Waiting for server confirmation…") }
                Section("Saved version") {
                    Text(current.title.isEmpty ? "Untitled saved file" : current.title).font(.headline)
                    Text(current.status.fileLabel).foregroundStyle(.secondary)
                    if !current.notes.isEmpty { Text(current.notes) }
                    if !current.reviewReason.isEmpty { LabeledContent("Review reason", value: current.reviewReason) }
                    if let count = current.byteCount {
                        LabeledContent("Validated size", value: ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file))
                        Button(model.kind == .practice ? "Play saved clip" : "Read saved PDF") { open(keep: false) }.disabled(model.isBusy)
                    }
                    if model.kind == .practice && model.published.contains(where: { $0.id == current.id }) {
                        Button("Keep on this device") { open(keep: true) }.disabled(model.isBusy)
                        Text("Keeps a verified copy for offline playback. Delivered copies cannot reliably be recalled; future remote access still checks current permissions.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if model.access?.isOwner == true && current.status == .submitted {
                    Section("Owner review") {
                        TextField("Review reason", text: $reason, axis: .vertical).focused($focused).disabled(model.isBusy)
                        Button("Approve this exact version") { review(.approve) }.disabled(model.isBusy || model.reloadRequired)
                        Button("Reject this version", role: .destructive) { review(.reject) }.disabled(model.isBusy || model.reloadRequired)
                    }
                }
                if model.canContribute && model.published.contains(where: { $0.id == current.id }) {
                    Section {
                        Text("A correction uploads a new immutable version. The published file stays available until its successor is approved.").font(.footnote).foregroundStyle(.secondary)
                        Button("Upload a replacement") {
                            replacement = FileEditorSelection(replacing: model.resources.first { $0.id == current.resourceID })
                        }.disabled(model.isBusy || model.reloadRequired)
                    }
                }
                if model.access?.isOwner == true,
                   let resource = model.resources.first(where: { $0.id == current.resourceID && $0.publishedVersionID == current.id && $0.archivedAt == nil }) {
                    Section {
                        Button("Archive published resource") { confirmArchive = true }.disabled(model.isBusy)
                        Text("Archive hides the current resource from routine viewing while preserving files and history.").font(.footnote).foregroundStyle(.secondary)
                    }
                    .confirmationDialog("Archive this resource?", isPresented: $confirmArchive, titleVisibility: .visible) {
                        Button("Archive", role: .destructive) { Task { _ = await model.archive(resource) } }
                        Button("Cancel", role: .cancel) {}
                    }
                }
            } else {
                if model.contentConcealed || model.didLoad {
                    Label("This file is unavailable for the current account. Reload to check access.", systemImage: "lock")
                } else { Text("The saved file is unavailable until loading succeeds.").foregroundStyle(.secondary) }
                if model.issue == nil { Button("Reload saved files") { Task { await model.load() } }.disabled(model.isBusy) }
            }
        }
        .navigationTitle(model.kind == .practice ? "Practice clip" : "Scouting report")
        .scrollDismissesKeyboard(.interactively)
        .navigationBarBackButtonHidden(changed || model.isBusy)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { focused = false; if changed { confirmClose = true } else { dismiss() } }.disabled(model.isBusy)
            }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } }
        }
        .confirmationDialog("Close without submitting review text?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Discard unsent review text", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        } message: { Text("Saved versions and review history remain unchanged.") }
        .task { await model.load() }
        .sheet(item: $preview) { item in NavigationStack { LocalFileViewer(preview: item) } }
        .sheet(item: $replacement) { item in NavigationStack { FileDraftEditor(model: model, selection: item) } }
        .onChange(of: model.contentConcealed) { _, value in if value { preview = nil } }
    }
    private func open(keep: Bool) {
        guard let current else { return }
        Task {
            if let url = await model.retrieve(current, keepOnDevice: keep) {
                preview = LocalFilePreview(url: url, kind: model.kind, title: current.title)
            }
        }
    }
    private func review(_ action: PrivateFileAction) {
        guard let current else { return }
        focused = false
        Task { if await model.transition(current, action: action, reason: reason) != nil { savedReason = reason } }
    }
}

private extension PrivateFileStatus {
    var fileLabel: String {
        switch self {
        case .uploading: "Upload unconfirmed — reconcile before retrying"
        case .ready: "Validated draft — unreviewed"
        case .submitted: "Pending owner review"
        case .rejected: "Rejected version — preserved"
        case .published: "Published file"
        case .failed: "Failed upload — preserved"
        }
    }
}

private struct LocalFilePreview: Identifiable {
    let id = UUID()
    let url: URL
    let kind: PrivateFileKind
    let title: String
    var rightsUnknown = false
}

private struct LocalFileViewer: View {
    let preview: LocalFilePreview
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var playbackFailed = false
    @State private var document: PDFDocument?
    @State private var documentFailed = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    var body: some View {
        Group {
            if preview.kind == .practice {
                ScrollView {
                    VStack(spacing: 16) {
                        if preview.rightsUnknown {
                            Label("Previously authorized device copy. Current team access could not be checked; delivered copies cannot reliably be recalled.", systemImage: "wifi.slash")
                                .font(.footnote).padding(.horizontal, 16)
                        }
                        if playbackFailed {
                            Label("Playback could not start. The saved file is preserved.", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red).padding(16)
                            Button("Close and recheck file") { dismiss() }.frame(minHeight: 44)
                        }
                        if let player, let item = player.currentItem {
                            VideoPlayer(player: player).frame(height: sizeClass == .regular ? 480 : 300)
                                .onReceive(player.publisher(for: \.status)) { if $0 == .failed { playbackFailed = true } }
                                .onReceive(item.publisher(for: \.status)) { if $0 == .failed { playbackFailed = true } }
                                .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: item)) { _ in playbackFailed = true }
                        } else { ProgressView("Preparing saved clip…") }
                    }
                }
            } else if documentFailed {
                ContentUnavailableView {
                    Label("Could not open saved report", systemImage: "exclamationmark.triangle")
                } description: { Text("The file is preserved. Close and read it again to recheck access and the saved copy.") }
                actions: { Button("Close and recheck file") { dismiss() } }
            } else if let document { LocalPDFView(document: document) }
            else { ProgressView("Opening saved report…") }
        }
        .navigationTitle(preview.title.isEmpty ? "Saved file" : preview.title)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
        .onAppear {
            if preview.kind == .practice && preview.url.isFileURL {
                let asset = AVURLAsset(url: preview.url, options: [AVURLAssetReferenceRestrictionsKey: AVAssetReferenceRestrictions.forbidAll.rawValue])
                player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            } else if preview.kind == .scouting {
                document = preview.url.isFileURL ? PDFDocument(url: preview.url) : nil
                documentFailed = document == nil || document?.pageCount == 0
            }
        }
        .onDisappear { player?.pause(); player = nil }
    }
}

/// Reads only explicitly retained, previously authorized clips. The private actor
/// stamp is a device namespace; it never authorizes a remote command.
struct OfflineClipsView: View {
    let account: BackendAccount
    let openAccount: () -> Void
    @State private var rows: [SavedClipRow] = []
    @State private var loadError: String?
    @State private var checking = false
    @State private var preview: LocalFilePreview?
    private let retention = DeviceClipLibrary.storage

    var body: some View {
        List {
            Section {
                Text("Use “Keep on this device” on a published practice clip to retain it. Existing device copies are reused; this screen never downloads automatically.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if checking { ProgressView("Checking access and saved copy…") }
            if let loadError {
                Section {
                    Label(loadError, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    Button("Retry", action: loadCatalog).disabled(checking)
                }
            }
            if account.offlineClipActorID == nil {
                Section {
                    Label("Saved clips are locked while signed out or after a known account restriction. Files remain on this device.", systemImage: "lock")
                    Button("Open Account", action: openAccount)
                }
            } else if loadError == nil && rows.isEmpty {
                ContentUnavailableView("No clips kept on this device", systemImage: "arrow.down.circle",
                    description: Text("Open Team → Playbook → a published play → Practice clips to choose a file to retain."))
            }
            ForEach(rows) { row in
                Button { Task { await open(row) } } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(row.clip.title).font(.headline)
                        Label("Kept on this device", systemImage: "arrow.down.circle").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }.disabled(checking)
            }
        }
        .navigationTitle("Saved clips")
        .task { await account.restoreIfNeeded(); loadCatalog() }
        .sheet(item: $preview) { item in NavigationStack { LocalFileViewer(preview: item) } }
        .onChange(of: account.offlineClipActorID) { _, _ in preview = nil; loadCatalog() }
    }

    private func loadCatalog() {
        rows = []; loadError = nil
        guard let project = account.configuration?.url, let actor = account.offlineClipActorID else { return }
        do {
            let scopes = try retention.scopes(projectURL: project, actorID: actor)
            rows = try scopes.flatMap { scope in
                try retention.items(scope: scope, actorID: actor).map { SavedClipRow(scope: scope, clip: $0) }
            }
        } catch { loadError = (error as? ClipRetentionIssue)?.message ?? "Saved clip storage could not be read. Existing files are preserved." }
    }

    private func open(_ row: SavedClipRow) async {
        guard !checking else { return }
        checking = true; loadError = nil
        defer { checking = false }
        do {
            guard account.offlineClipActorID == row.scope.actorID else { throw ClipRetentionIssue.locked }
            var rightsUnknown = true
            if account.sessionContextID != nil {
                let model = PrivateFiles(teamID: row.scope.teamID, kind: .practice, targetID: row.clip.targetID,
                    account: account, retention: retention)
                await model.load()
                guard account.offlineClipActorID == row.scope.actorID, !model.contentConcealed else { throw ClipRetentionIssue.locked }
                if model.didLoad {
                    guard model.versions.contains(where: { $0.id == row.clip.versionID }) else {
                        try retention.recordDenial(scope: row.scope, versionID: row.clip.versionID)
                        throw ClipRetentionIssue.locked
                    }
                    rightsUnknown = false
                } else if model.issue == .denied { throw ClipRetentionIssue.locked }
            }
            guard let url = try retention.cachedURL(scope: row.scope, versionID: row.clip.versionID,
                actorID: account.offlineClipActorID, requireRetained: true) else { throw ClipRetentionIssue.storage }
            preview = LocalFilePreview(url: url, kind: .practice, title: row.clip.title, rightsUnknown: rightsUnknown)
        } catch {
            loadCatalog()
            loadError = (error as? ClipRetentionIssue)?.message ?? "The saved copy could not be opened. Its file is preserved."
        }
    }
}

private struct SavedClipRow: Identifiable {
    let scope: ClipScope
    let clip: RetainedClip
    var id: String { "\(scope.teamID)-\(clip.versionID)" }
}

private struct LocalPDFView: UIViewRepresentable {
    let document: PDFDocument
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = document
        view.accessibilityLabel = "Saved scouting report"
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {}
}
