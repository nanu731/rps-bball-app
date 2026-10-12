import SwiftUI

struct PlaybookView: View {
    let account: BackendAccount
    @State private var model: Playbook
    @State private var newPlayID = UUID()
    @State private var openedDraft: PlayRevision?
    init(account: BackendAccount, teamID: UUID) { self.account = account; _model = State(initialValue: Playbook(account: account, teamID: teamID)) }
    var body: some View {
        List {
            Section {
                Text("Only accepted plays are shared with team viewers. Marker numbers are diagram roles, not roster identities.")
                if model.isBusy { ProgressView("Loading playbook…") }
                if let issue = model.issue { Label(issue.localizedDescription, systemImage: "exclamationmark.triangle").foregroundStyle(.red); Button("Retry") { Task { await model.load() } } }
                if let confirmation = model.confirmation { Text(confirmation) }
            }
            if model.didLoad {
                Section("Published plays") {
                    if model.published.isEmpty { Text("No published plays.").foregroundStyle(.secondary) }
                    ForEach(model.published) { revision in
                        NavigationLink(revision.title) { PlayRevisionView(account: account, model: model, revision: revision) }
                    }
                }
                if model.access?.can(.playsAuthor) == true {
                    Section("Your drafts") {
                        Button("Create a play", systemImage: "plus") {
                            Task { if let draft = await model.openDraft(playID: newPlayID) { openedDraft = draft; newPlayID = UUID() } }
                        }
                        ForEach(model.ownDrafts) { revision in
                            Button(revision.title.isEmpty ? "Unnamed draft" : revision.title) { openedDraft = revision }
                        }
                    }
                }
                if model.versions.contains(where: { $0.status == .superseded }) {
                    Section("Your superseded saved drafts") {
                        ForEach(model.versions.filter { $0.status == .superseded }) { revision in
                            NavigationLink { PlayRevisionView(account: account, model: model, revision: revision) } label: {
                                VStack(alignment: .leading) {
                                    Text(revision.title.isEmpty ? "Unnamed saved draft" : revision.title)
                                    Text("Superseded saved drawing — read-only").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Section("Submitted / rejected revisions") {
                    ForEach(model.versions.filter { $0.status == .submitted || $0.status == .rejected }) { revision in
                        NavigationLink { PlayRevisionView(account: account, model: model, revision: revision) } label: {
                            VStack(alignment: .leading) { Text(revision.title); Text(revision.status.rawValue.capitalized).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    if model.submissions.isEmpty { Text("No visible submissions awaiting review.").foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle("Playbook")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Reload", systemImage: "arrow.clockwise") { Task { await model.load() } }.disabled(model.isBusy) } }
        .task { await model.load() }
        .navigationDestination(item: $openedDraft) { revision in PlayRevisionView(account: account, model: model, revision: revision) }
    }
}

private struct PlayRevisionView: View {
    let account: BackendAccount
    let model: Playbook
    @State var revision: PlayRevision
    @State private var title: String
    @State private var diagram: PlayDiagram
    @State private var selectedStep = 0
    @State private var selectedMarkerID: UUID?
    @State private var reason = ""
    @State private var successor: PlayRevision?
    @State private var recoveryPointer: UUID?
    @State private var confirmRecovery = false
    @State private var pendingRecoverySource: PlayRevision?
    @State private var attachmentCandidate: PlayRevision?
    @State private var attachmentLookupMessage: String?
    @State private var confirmAttachment = false
    @FocusState private var textFocused: Bool
    init(account: BackendAccount, model: Playbook, revision: PlayRevision) {
        self.account = account; self.model = model; _revision = State(initialValue: revision)
        _title = State(initialValue: revision.title); _diagram = State(initialValue: revision.diagram)
    }
    private var editable: Bool { revision.status == .draft && revision.authorUserID == model.access?.userID && model.access?.can(.playsAuthor) == true }
    private var changed: Bool { title != revision.title || diagram != revision.diagram }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label(revision.status == .published ? "Published revision — read-only" : "\(revision.status.rawValue.capitalized) play revision", systemImage: revision.status == .published ? "checkmark.circle" : "pencil")
                if let issue = model.issue {
                    Label(issue.localizedDescription, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    Button("Reload server state (keep unsaved drawing)") { Task { await reloadRetainingBuffers() } }
                }
                if let confirmation = model.confirmation { Text(confirmation) }
                if pendingRecoverySource != nil && changed {
                    Label("Retained unsaved name or drawing — not uploaded", systemImage: "pencil").font(.subheadline)
                    Text("Retained name: \(title.isEmpty ? "Unnamed draft" : title)").font(.subheadline)
                }
                if let message = attachmentLookupMessage {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    Button("Reload and check recovered draft") { Task { await reloadRetainingBuffers() } }
                }
                if attachmentCandidate != nil {
                    Text("The server has a recovered working draft for this saved drawing. Attach your retained editor content to that draft only if you want to continue editing it.").font(.subheadline)
                    Button("Attach retained edits to recovered draft") { confirmAttachment = true }
                        .alert("Attach retained edits?", isPresented: $confirmAttachment) {
                            Button("Attach without saving") { attachRetainedBuffers() }
                            Button("Go back", role: .cancel) {}
                        } message: {
                            Text("Your retained name and drawing stay in the editor. The recovered draft's saved content and published play remain unchanged until you explicitly Save and complete the review/publication workflow. This does not repeat recovery.")
                        }
                }
                if revision.status == .superseded {
                    Text("This saved drawing was retained after explicit recovery. It is read-only; the resumed draft has a separate identity.").font(.subheadline)
                }
                if editable && model.isStaleDraft(revision) && model.didLoad && !model.reloadRequired {
                    Label("A newer play was published. This saved draft still references the previous accepted revision.", systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    Text("Resume keeps this saved drawing in read-only history and creates a new draft against the latest published play. Your unsaved name and drawing stay in this editor until you explicitly Save.").font(.subheadline)
                    Button("Resume drawing against latest published play") {
                        recoveryPointer = model.currentPublishedVersionID(playID: revision.playID)
                        confirmRecovery = recoveryPointer != nil
                    }
                }
                if editable {
                    if changed { Label("Unsaved name or drawing changes", systemImage: "pencil").font(.subheadline) }
                    TextField("Play name", text: $title).textFieldStyle(.roundedBorder).focused($textFocused)
                    Text("Drag a marker to position it. The controls below also move the selected marker without dragging.").font(.subheadline)
                    Picker("Edit position", selection: $selectedStep) {
                        Text("Initial placement").tag(0)
                        ForEach(diagram.steps.indices, id: \.self) { Text("Step \($0 + 1)").tag($0 + 1) }
                    }.pickerStyle(.menu)
                    PlayCourt(diagram: diagram, positions: editorPositions, selectedMarkerID: selectedMarkerID, arrows: movementArrows,
                              select: { selectedMarkerID = $0 }, move: { id, point in diagram.move(markerID: id, step: selectedStep, to: point) })
                        .aspectRatio(1.15, contentMode: .fit)
                    HStack {
                        Button("Add marker", systemImage: "plus.circle") { diagram.addMarker(); selectedMarkerID = diagram.markers.last?.id }
                        Spacer()
                        Button("Add movement step", systemImage: "arrow.right") { diagram.addStep(); selectedStep = diagram.steps.count }.disabled(diagram.markers.isEmpty)
                    }.buttonStyle(.bordered)
                    if !diagram.markers.isEmpty {
                        Picker("Marker", selection: $selectedMarkerID) {
                            Text("Choose a marker").tag(Optional<UUID>.none)
                            ForEach(diagram.markers) { Text("Marker \($0.number)").tag(Optional($0.id)) }
                        }.pickerStyle(.menu)
                    }
                    if let id = selectedMarkerID, let index = diagram.markers.firstIndex(where: { $0.id == id }), let point = diagram.position(markerID: id, step: selectedStep) {
                        TextField("Optional marker label", text: $diagram.markers[index].label).textFieldStyle(.roundedBorder).focused($textFocused)
                        coordinateSlider("Horizontal position", id: id, point: point, horizontal: true)
                        coordinateSlider("Vertical position", id: id, point: point, horizontal: false)
                    }
                    if selectedStep > 0, diagram.steps.indices.contains(selectedStep - 1) {
                        HStack {
                            Text("Step duration: \(diagram.steps[selectedStep - 1].duration, specifier: "%.1f") seconds")
                            Stepper("Duration", value: $diagram.steps[selectedStep - 1].duration, in: 0.1...30, step: 0.1).labelsHidden().accessibilityLabel("Step \(selectedStep) duration")
                        }
                    }
                    if let message = diagram.validationMessage { Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                } else {
                    Text(revision.title).font(.title2)
                }
                if revision.status == .published {
                    NavigationLink("Practice video links and owner review") {
                        MediaResourcesView(teamID: revision.teamID, kind: .practice, targetID: revision.playID,
                            targetTitle: revision.title, account: account)
                    }
                }
                Divider()
                Text(pendingRecoverySource == nil ? "Playback" : "Retained editor preview").font(.headline)
                PlayPlaybackView(diagram: diagram)
                if editable {
                    Text("Save the name and drawing before submitting. Publication requires at least one marker and movement step.").font(.subheadline)
                    Button("Submit for independent review") { Task { _ = await model.transition(revision, action: "submit"); synchronize() } }
                        .disabled(changed || !diagram.canPublish || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.reloadRequired)
                    if model.access?.can(.playsPublish) == true {
                        Button("Publish with authorized bypass") { Task { _ = await model.transition(revision, action: "publish"); synchronize() } }
                            .disabled(changed || !diagram.canPublish || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.reloadRequired)
                    }
                }
                if revision.status == .submitted, model.access?.can(.playsReview) == true,
                   revision.authorUserID != model.access?.userID || model.access?.isOwner == true {
                    TextField("Review reason (optional)", text: $reason, axis: .vertical).textFieldStyle(.roundedBorder).focused($textFocused)
                    HStack {
                        Button("Approve and publish") { Task { _ = await model.transition(revision, action: "approve", reason: reason); synchronize() } }
                        Button("Reject proposal") { Task { _ = await model.transition(revision, action: "reject", reason: reason); synchronize() } }
                    }.buttonStyle(.bordered)
                }
                if !revision.reviewReason.isEmpty { Text("Review: \(revision.reviewReason)") }
                if model.access?.can(.playsAuthor) == true && (revision.status == .published || (revision.status == .rejected && revision.authorUserID == model.access?.userID)) {
                    Button("Create successor draft") { Task { successor = await model.openDraft(playID: revision.playID, source: revision) } }
                    Text("The published revision stays unchanged while a successor is authored and reviewed.").font(.caption)
                }
                if revision.status == .published {
                    Text("Published history").font(.headline)
                    ForEach(model.history(playID: revision.playID).filter { $0.id != revision.id }) { past in
                        NavigationLink("\(past.title) — revision \(past.revision)") { PlayRevisionView(account: account, model: model, revision: past) }
                    }
                }
            }.padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(editable ? "Edit play" : "View play")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if editable { Button("Save") { textFocused = false; Task { if await model.save(revision, title: title, diagram: diagram) { synchronize() } } }
                    .disabled(model.isBusy || model.reloadRequired || diagram.validationMessage != nil || title.count > 100) }
            }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { textFocused = false } }
        }
        .disabled(model.isBusy)
        .alert("Resume this stale draft?", isPresented: $confirmRecovery) {
            Button("Resume and retain saved history") {
                guard let pointer = recoveryPointer else { return }
                pendingRecoverySource = revision; attachmentCandidate = nil; attachmentLookupMessage = nil
                Task {
                    if let resumed = await model.recoverDraft(revision, expectedPublishedVersionID: pointer) {
                        // Change only server revision metadata. Retain current unsaved editor buffers.
                        revision = resumed; pendingRecoverySource = nil
                    }
                }
            }
            Button("Go back", role: .cancel) {}
        } message: {
            Text("The old saved drawing remains read-only. The new draft copies its saved content against the latest published revision. Your current unsaved edits remain in this editor and are not automatically saved or published.")
        }
        .navigationDestination(item: $successor) { next in PlayRevisionView(account: account, model: model, revision: next) }
    }
    private func attachRetainedBuffers() {
        guard let source = pendingRecoverySource, let candidate = attachmentCandidate else { return }
        do {
            // Revalidate identity/revision against the last explicit successful server reload.
            let current = try model.recoveredDraft(for: source)
            guard current.id == candidate.id, current.revision == candidate.revision else { throw PlaybookIssue.reloadRequired }
            revision = current; pendingRecoverySource = nil; attachmentCandidate = nil; attachmentLookupMessage = nil
        } catch {
            attachmentCandidate = nil; attachmentLookupMessage = error.localizedDescription
        }
    }
    private func reloadRetainingBuffers() async {
        attachmentCandidate = nil; attachmentLookupMessage = nil
        await model.load()
        guard model.didLoad else { return }
        if let current = model.versions.first(where: { $0.id == revision.id }) { revision = current }
        if let source = pendingRecoverySource {
            do { attachmentCandidate = try model.recoveredDraft(for: source) }
            catch { attachmentLookupMessage = error.localizedDescription }
        }
    }
    private var editorPositions: [PlayPosition] { diagram.markers.compactMap { marker in diagram.position(markerID: marker.id, step: selectedStep).map { PlayPosition(markerID: marker.id, point: $0) } } }
    private var movementArrows: [(CourtPoint, CourtPoint)] {
        guard selectedStep > 0 else { return [] }
        return diagram.markers.compactMap { marker in
            guard let start = diagram.position(markerID: marker.id, step: selectedStep - 1), let end = diagram.position(markerID: marker.id, step: selectedStep) else { return nil }
            return (start, end)
        }
    }
    private func coordinateSlider(_ label: String, id: UUID, point: CourtPoint, horizontal: Bool) -> some View {
        VStack(alignment: .leading) {
            Text("\(label): \((horizontal ? point.x : point.y) * 100, specifier: "%.0f")%")
            Slider(value: Binding(get: { horizontal ? point.x : point.y }, set: { value in
                diagram.move(markerID: id, step: selectedStep, to: CourtPoint(x: horizontal ? value : point.x, y: horizontal ? point.y : value))
            }), in: 0...1).accessibilityLabel(label)
        }
    }
    private func synchronize() { if let current = model.versions.first(where: { $0.id == revision.id }) { revision = current; title = current.title; diagram = current.diagram } }
}

struct PlayPlaybackView: View {
    let diagram: PlayDiagram
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @State private var time = 0.0
    @State private var playing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PlayCourt(diagram: diagram, positions: diagram.positions(at: time, reducedMotion: reducedMotion), selectedMarkerID: nil, arrows: [], select: { _ in }, move: nil)
                .aspectRatio(1.15, contentMode: .fit)
            if diagram.steps.isEmpty { Text("No authored movement steps.").foregroundStyle(.secondary) }
            if reducedMotion { Text("Reduced Motion: discrete authored positions.").font(.caption) }
            if diagram.duration > 0 {
                Slider(value: $time, in: 0...diagram.duration, onEditingChanged: { _ in playing = false }).accessibilityLabel("Playback position in seconds")
                Text("\(time, specifier: "%.1f") of \(diagram.duration, specifier: "%.1f") seconds").monospacedDigit().font(.caption)
                HStack {
                    Button(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill") { if time >= diagram.duration { time = 0 }; playing.toggle() }
                    Button("Replay", systemImage: "arrow.counterclockwise") { time = 0; playing = true }
                    Button("Previous step", systemImage: "backward.end.fill") { advanceStep(forward: false) }.labelStyle(.iconOnly)
                    Button("Next step", systemImage: "forward.end.fill") { advanceStep(forward: true) }.labelStyle(.iconOnly)
                }.buttonStyle(.bordered).controlSize(.large)
            }
            ForEach(diagram.markers) { marker in
                if let point = diagram.positions(at: time, reducedMotion: reducedMotion).first(where: { $0.markerID == marker.id })?.point {
                    Text("Marker \(marker.number)\(marker.label.isEmpty ? "" : ": \(marker.label)"): \(point.x * 100, specifier: "%.0f")% across, \(point.y * 100, specifier: "%.0f")% down").font(.caption)
                }
            }
        }
        .task(id: playing) {
            guard playing else { return }
            var previous = Date()
            while !Task.isCancelled && playing {
                do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
                let now = Date(); time = min(diagram.duration, time + max(0, now.timeIntervalSince(previous))); previous = now
                if time >= diagram.duration { playing = false }
            }
        }
        .onDisappear { playing = false }
        .onChange(of: diagram) { playing = false; time = 0 }
    }
    private func advanceStep(forward: Bool) {
        playing = false
        var boundaries = [0.0]; for step in diagram.steps { boundaries.append(boundaries.last! + step.duration) }
        time = forward ? boundaries.first(where: { $0 > time + 0.001 }) ?? diagram.duration : boundaries.last(where: { $0 < time - 0.001 }) ?? 0
    }
}

private struct PlayCourt: View {
    let diagram: PlayDiagram
    let positions: [PlayPosition]
    let selectedMarkerID: UUID?
    let arrows: [(CourtPoint, CourtPoint)]
    let select: (UUID) -> Void
    let move: ((UUID, CourtPoint) -> Void)?
    @State private var dragOrigin: CourtPoint?
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color(uiColor: .secondarySystemBackground))
                Path { path in
                    path.addRect(CGRect(x: 1, y: 1, width: max(0, size.width - 2), height: max(0, size.height - 2)))
                    path.addRect(CGRect(x: size.width * 0.34, y: 1, width: size.width * 0.32, height: size.height * 0.42))
                    path.addEllipse(in: CGRect(x: size.width * 0.44, y: size.height * 0.05, width: size.width * 0.12, height: size.width * 0.12))
                }.stroke(.secondary, lineWidth: 1.5).accessibilityHidden(true)
                Path { path in
                    for (start, end) in arrows where start != end {
                        let a = CGPoint(x: start.x * size.width, y: start.y * size.height)
                        let b = CGPoint(x: end.x * size.width, y: end.y * size.height)
                        path.move(to: a); path.addLine(to: b)
                        let angle = atan2(b.y - a.y, b.x - a.x)
                        for offset in [-0.5, 0.5] { path.move(to: b); path.addLine(to: CGPoint(x: b.x - 10 * cos(angle + offset), y: b.y - 10 * sin(angle + offset))) }
                    }
                }.stroke(.primary, style: StrokeStyle(lineWidth: 2, dash: [5, 3])).accessibilityHidden(true)
                ForEach(diagram.markers) { marker in
                    if let point = positions.first(where: { $0.markerID == marker.id })?.point {
                        Group {
                            if move == nil {
                                markerSymbol(marker)
                            } else {
                                Button { select(marker.id) } label: { markerSymbol(marker) }
                                    .buttonStyle(.plain)
                                    .gesture(DragGesture(minimumDistance: 5).onChanged { value in
                                        guard let move, size.width > 0, size.height > 0 else { return }
                                        select(marker.id)
                                        if dragOrigin == nil { dragOrigin = point }
                                        guard let origin = dragOrigin else { return }
                                        move(marker.id, CourtPoint(x: min(1, max(0, origin.x + value.translation.width / size.width)), y: min(1, max(0, origin.y + value.translation.height / size.height))))
                                    }.onEnded { _ in dragOrigin = nil })
                            }
                        }
                        .position(x: point.x * size.width, y: point.y * size.height)
                        .accessibilityLabel("Marker \(marker.number)\(marker.label.isEmpty ? "" : ", \(marker.label)")")
                    }
                }
            }
        }
        .padding(22)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Half court diagram")
    }
    private func markerSymbol(_ marker: PlayMarker) -> some View {
        Text("\(marker.number)").font(.body.weight(.semibold)).monospacedDigit().frame(minWidth: 44, minHeight: 44)
            .background(selectedMarkerID == marker.id ? Color.primary : Color(uiColor: .systemBackground), in: Circle())
            .foregroundStyle(selectedMarkerID == marker.id ? Color(uiColor: .systemBackground) : Color.primary)
            .overlay(Circle().stroke(.primary, lineWidth: 2))
    }

}
