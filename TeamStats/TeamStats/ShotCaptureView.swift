import SwiftUI

/// Local games use a separate file, never an implicit upload or a legacy-store migration.
struct LocalShotCaptureView: View {
    let game: Game
    @State private var recorder: ShotCaptureRecorder?
    @State private var issue: String?
    var body: some View {
        Group {
            if let recorder { ShotCaptureWorkspace(recorder: recorder, title: game.opponent) }
            else if let issue {
                ContentUnavailableView { Label("Could not open capture", systemImage: "exclamationmark.triangle") }
                description: { Text(issue) } actions: { Button("Retry") { Task { await load() } } }
            } else { ProgressView("Opening local capture") }
        }
        .navigationTitle("Shot recorder").navigationBarTitleDisplayMode(.inline)
        .task { if recorder == nil { await load() } }
    }
    private func load() async {
        issue = nil
        do {
            let url = try GameStorage.fileURL().deletingLastPathComponent()
                .appendingPathComponent("shot-local-\(game.id.uuidString).json")
            let context = ShotCaptureContext(gameID: game.id, teamID: nil, actorID: nil, assignmentRevision: nil)
            let document = try await ShotCaptureDisk.shared.openLocal(gameID: game.id, at: url,
                players: temporaryRoster.map { ShotCapturePlayer(id: $0.id, name: $0.name, number: String($0.number), temporary: true) })
            guard document.context == context else { throw ShotCaptureIssue.corrupt }
            recorder = try ShotCaptureRecorder(document: document, url: url)
        } catch { issue = "Saved capture could not be opened. Existing files were preserved. \((error as? ShotCaptureIssue)?.localizedDescription ?? "Check available device storage and retry.")" }
    }
}

struct ShotCaptureWorkspace: View {
    let recorder: ShotCaptureRecorder
    let title: String
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var team: ShotTeam = .our
    @State private var playerID = ""
    @State private var basket: ShotBasket = .top
    @State private var flipped = false
    @State private var selectedID: UUID?
    @State private var movingID: UUID?
    @State private var showingFT = false
    @State private var showingLocations = false
    @State private var historyLimit = 20
    private var document: ShotCaptureDocument? { recorder.visibleDocument }
    private var events: [ShotCaptureEvent] { (try? document?.events()) ?? [] }
    private var selected: ShotCaptureEvent? { events.first { $0.id == selectedID } }
    private var canStart: Bool { recorder.canChange && (team == .opponent || document?.players.contains { $0.id == playerID } == true) }

    var body: some View {
        if let document {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(title).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                        Label(document.context.isShared ? "Device capture for shared game" : "Local shot draft", systemImage: "basketball")
                            .font(.headline)
                        Text("Incomplete · Unreviewed. Shots stay separate from after-game statistics.")
                            .font(.footnote).foregroundStyle(TeamStatsStyle.secondaryText)
                        if document.players.contains(where: \.temporary) { Text("Temporary roster").font(.subheadline.bold()) }
                        selection(document)
                        let layout = sizeClass == .regular && !textSize.isAccessibilitySize
                            ? AnyLayout(HStackLayout(alignment: .top, spacing: 24)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                        layout {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(movingID != nil ? "Tap the corrected location" : "Tap where the field goal was taken").font(.headline)
                                ShotCourtView(events: events, flipped: flipped, selectedID: selectedID) { point in record(point) }
                                    .frame(maxWidth: 420).aspectRatio(0.65, contentMode: .fit)
                                    .disabled(!canStart && movingID == nil)
                                Text("Schematic full court · 2/3 points are always selected explicitly.")
                                    .font(.caption).foregroundStyle(TeamStatsStyle.secondaryText)
                                ViewThatFits(in: .horizontal) {
                                    HStack { locationButton; freeThrowButton }
                                    VStack(alignment: .leading) { locationButton; freeThrowButton }
                                }
                                Text(flipped ? "Court display flipped180°. Original top basket is displayed at the bottom." : "Court display upright. Original top basket is displayed at the top.").font(.footnote)
                                Button(flipped ? "Restore court display" : "Flip court display", systemImage: "arrow.triangle.2.circlepath") { flipped.toggle() }
                                    .frame(minHeight: 44)
                            }
                            VStack(alignment: .leading, spacing: 16) {
                                if let selected { eventEditor(selected).id("shot.result") }
                                status
                                Button("Undo last change", systemImage: "arrow.uturn.backward") {
                                    Task { await recorder.change { try $0.undo() }; movingID = nil; selectedID = events.last?.id }
                                }.disabled(!recorder.canChange || !document.canUndo).frame(minHeight: 44)
                                Text("Recent observations").font(.headline)
                                if events.isEmpty { Text("No shots recorded. A court tap saves a pending field goal.") }
                                ForEach(Array(events.suffix(historyLimit).reversed())) { event in
                                    Button { selectedID = event.id; movingID = nil } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(eventTitle(event)).font(.headline)
                                            Text(resultText(event)).font(.subheadline)
                                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    }.buttonStyle(.bordered)
                                }
                                if events.count > historyLimit { Button("Show 20 earlier observations") { historyLimit += 20 }.frame(minHeight: 44) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(16)
                }
                .onChange(of: selectedID) { _, _ in
                    movingID = nil
                    if selected != nil { proxy.scrollTo("shot.result", anchor: .top) }
                }
            }
            .navigationBarBackButtonHidden(recorder.isBusy || recorder.needsSave)
            .sheet(isPresented: $showingFT) {
                ShotFreeThrowSetup(team: team, playerID: team == .our ? playerID : nil, recorder: recorder) { id in
                    selectedID = id; showingFT = false
                }
            }
            .confirmationDialog("Choose a schematic location", isPresented: $showingLocations, titleVisibility: .visible) {
                ForEach(0..<3) { row in
                    ForEach(0..<3) { column in
                        Button("\(["Top", "Middle", "Bottom"][row]) \(["left", "center", "right"][column])") {
                            record(ShotCourtTransform(flipped: flipped).display(ShotLocation(x: (Double(column) + 0.5) / 3, y: (Double(row) + 0.5) / 3)))
                        }
                    }
                }
            } message: { Text("Approximate full-court bands, not regulation zones. This is an alternative to tapping the court.") }
            .onAppear { if playerID.isEmpty { playerID = document.players.first?.id ?? "" } }
        } else { ContentUnavailableView("Capture concealed", systemImage: "lock", description: Text("Return to the current account and reload authorized records.")) }
    }

    private func selection(_ document: ShotCaptureDocument) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(team == .our ? "Next entry: Our team" : "Next entry: Opponent").font(.headline)
            Picker("Recording team", selection: $team) { Text("Our team").tag(ShotTeam.our); Text("Opponent").tag(ShotTeam.opponent) }
                .pickerStyle(.segmented).accessibilityIdentifier("shot.team")
            if team == .our {
                Picker("Our player", selection: $playerID) {
                    ForEach(document.players) { Text("\($0.name) · #\($0.number)").tag($0.id) }
                }.frame(minHeight: 44)
                if document.players.isEmpty { Text("No roster players available. Our shots require an existing player.") }
            } else { Text("Opponent · team-only observations").font(.subheadline) }
            Picker("Attacking basket for next field goal", selection: $basket) {
                Text(flipped ? "Original top · displayed bottom" : "Top basket").tag(ShotBasket.top); Text(flipped ? "Original bottom · displayed top" : "Bottom basket").tag(ShotBasket.bottom)
            }.frame(minHeight: 44)
            Text("Selections apply to the next entry. A pending shot keeps its original team/player/basket.").font(.footnote).foregroundStyle(TeamStatsStyle.secondaryText)
        }.disabled(!recorder.canChange)
    }
    private var freeThrowButton: some View {
        Button("Free throws", systemImage: "plus.circle") { showingFT = true }
            .buttonStyle(.borderedProminent).tint(TeamStatsStyle.filledAccent).frame(minHeight: 44).disabled(!canStart)
    }
    private var locationButton: some View {
        Button(movingID != nil ? "Choose corrected location" : "Choose location without tapping") { showingLocations = true }
            .frame(minHeight: 44).disabled(!canStart && movingID == nil)
    }
    private var status: some View {
        VStack(alignment: .leading, spacing: 8) {
            if recorder.isBusy { ProgressView("Saving observation…") }
            else if let issue = recorder.issue {
                Label(issue, systemImage: "exclamationmark.triangle").foregroundStyle(TeamStatsStyle.errorText)
                if recorder.needsSave {
                    Button("Retry same change") { Task { await recorder.retrySave() } }.frame(minHeight: 44)
                    Button("Preserve recovery copy and reopen") {
                        guard let change = document?.journal.last,
                              let folder = try? GameStorage.fileURL().deletingLastPathComponent() else { return }
                        let copy = folder.appendingPathComponent("shot-recovery-\(change.id.uuidString).json")
                        Task { await recorder.reopenPreservingPending(at: copy) }
                    }.frame(minHeight: 44)
                }
            } else { Label("Saved on this device", systemImage: "checkmark.circle") }
            if let url = recorder.recoveryURL {
                Text("Pending work preserved in a separate recovery copy, not merged into the reopened capture.")
                ShareLink("Export preserved recovery copy…", item: url).frame(minHeight: 44)
                Text("Contains capture data. Choose a private destination.").font(.footnote)
            }
            if recorder.needsSave { Text("Save not confirmed. Keep this screen open and retry; do not enter this observation again.") }
        }.fixedSize(horizontal: false, vertical: true)
    }
    private func record(_ point: ShotLocation) {
        guard recorder.canChange else { return }
        let frozenTeam = team, frozenPlayer = team == .our ? playerID : nil, frozenBasket = basket
        Task {
            if let movingID {
                guard var event = events.first(where: { $0.id == movingID }), event.kind == .fieldGoal else { self.movingID = nil; return }
                event.location = point
                await recorder.change { try $0.correct(event) }; self.movingID = nil
            } else {
                var id: UUID?
                await recorder.change { id = try $0.startFieldGoal(team: frozenTeam, playerID: frozenPlayer, location: point, basket: frozenBasket) }
                if let id { selectedID = id }
            }
        }
    }
    private func eventTitle(_ event: ShotCaptureEvent) -> String {
        let attribution = event.team == .opponent ? "Opponent" : document?.players.first { $0.id == event.playerID }.map { "\($0.name) #\($0.number)" } ?? "Player unavailable"
        return "\(attribution) · \(event.kind == .fieldGoal ? "Field goal" : "Free throws")"
    }
    private func resultText(_ event: ShotCaptureEvent) -> String {
        if event.kind == .freeThrows { return "\(event.answers.filter { $0.outcome == .made }.count)/\(event.freeThrowAttempts ?? 0) made · \((event.freeThrowAttempts ?? 0) - event.answers.count) pending" }
        guard let value = event.value, let outcome = event.outcome else { return "Pending field goal" }
        return "\(value) points · \(outcome == .made ? "Make" : "Miss")"
    }
    @ViewBuilder private func eventEditor(_ event: ShotCaptureEvent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eventTitle(event)).font(.headline)
            Text(resultText(event)).font(.subheadline.bold())
            Picker("Correct observation team", selection: Binding(get: { event.team }, set: { team in
                guard team != event.team else { return }
                var corrected = event; corrected.team = team
                corrected.playerID = team == .our ? document?.players.first?.id : nil
                Task { await recorder.change { try $0.correct(corrected) } }
            })) { Text("Our team").tag(ShotTeam.our); Text("Opponent").tag(ShotTeam.opponent) }.frame(minHeight: 44)
            if event.team == .our, let document {
                Picker("Correct observation player", selection: Binding(get: { event.playerID ?? "" }, set: { id in
                    var corrected = event; corrected.playerID = id
                    Task { await recorder.change { try $0.correct(corrected) } }
                })) { ForEach(document.players) { Text("\($0.name) #\($0.number)").tag($0.id) } }.frame(minHeight: 44)
            }
            if event.kind == .fieldGoal {
                ForEach([2, 3], id: \.self) { value in
                    ViewThatFits(in: .horizontal) {
                        HStack { resultButton(event, value, .made); resultButton(event, value, .missed) }
                        VStack(alignment: .leading) { resultButton(event, value, .made); resultButton(event, value, .missed) }
                    }
                }
                Button("Return result to pending") {
                    var corrected = event; corrected.outcome = nil
                    Task { await recorder.change { try $0.correct(corrected) } }
                }.frame(minHeight: 44)
                Button(movingID == event.id ? "Cancel location correction" : "Move selected shot") { movingID = movingID == event.id ? nil : event.id }.frame(minHeight: 44)
                Picker("Correct attacking basket", selection: Binding(get: { event.basket ?? .top }, set: { basket in
                    var corrected = event; corrected.basket = basket
                    Task { await recorder.change { try $0.correct(corrected) } }
                })) { Text(flipped ? "Original top · displayed bottom" : "Top basket").tag(ShotBasket.top); Text(flipped ? "Original bottom · displayed top" : "Bottom basket").tag(ShotBasket.bottom) }.frame(minHeight: 44)
            } else {
                ShotFreeThrowAnswers(recorder: recorder, event: event).id(event.id)
            }
        }.disabled(!recorder.canChange)
    }
    private func resultButton(_ event: ShotCaptureEvent, _ value: Int, _ outcome: ShotOutcome) -> some View {
        Button("\(value)PT \(outcome == .made ? "Make" : "Miss")", systemImage: outcome == .made ? "checkmark.circle" : "xmark.circle") {
            var corrected = event; corrected.value = value; corrected.outcome = outcome
            Task { await recorder.change { try $0.correct(corrected) } }
        }.buttonStyle(.bordered).frame(minHeight: 44)
            .accessibilityIdentifier("shot.result.\(value).\(outcome.rawValue)")
    }
}

struct ShotCourtView: View {
    let events: [ShotCaptureEvent]
    let flipped: Bool
    var selectedID: UUID? = nil
    var tap: ((ShotLocation) -> Void)? = nil
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle().fill(Color(uiColor: .secondarySystemBackground))
                Path { path in
                    let w = geometry.size.width, h = geometry.size.height
                    path.addRect(CGRect(x: 1, y: 1, width: w - 2, height: h - 2))
                    path.move(to: CGPoint(x: 0, y: h / 2)); path.addLine(to: CGPoint(x: w, y: h / 2))
                    path.addEllipse(in: CGRect(x: w * 0.35, y: h * 0.5 - w * 0.15, width: w * 0.3, height: w * 0.3))
                    for y in [h * 0.025, h * 0.95] { path.addRect(CGRect(x: w * 0.42, y: y, width: w * 0.16, height: h * 0.025)) }
                }.stroke(Color.primary.opacity(0.65), lineWidth: 2)
                ForEach(events.filter { $0.kind == .fieldGoal }) { event in
                    if let location = event.location {
                        let point = ShotCourtTransform(flipped: flipped).display(location)
                        Text(event.outcome == .made ? "●" : event.outcome == .missed ? "×" : "?")
                            .font(.headline.bold()).foregroundStyle(event.id == selectedID ? Color.accentColor : .primary)
                            .position(x: point.x * geometry.size.width, y: point.y * geometry.size.height)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { point in
                if let capture = try? ShotCourtTransform(flipped: flipped).capture(x: point.x, y: point.y, width: geometry.size.width, height: geometry.size.height) { tap?(capture) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Schematic full court. Top and bottom baskets. Recorded field goals only.")
        .accessibilityHint(tap == nil ? "Read individual observations below." : "Tap a location, or use Choose location without tapping.")
        .accessibilityIdentifier("shot.court")
    }
}

private struct ShotFreeThrowSetup: View {
    let team: ShotTeam
    let playerID: String?
    let recorder: ShotCaptureRecorder
    let started: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var attempts = "1"
    @FocusState private var focused: Bool
    private var count: Int? {
        guard case let .value(count) = BoxScoreCount(attempts), (1...ShotCaptureDocument.maximumAttempts).contains(count) else { return nil }
        return count
    }
    var body: some View {
        NavigationStack {
            Form {
                if recorder.isBusy { Section { ProgressView("Saving series…") } }
                if let issue = recorder.issue {
                    Section("Series not confirmed") {
                        Label(issue, systemImage: "exclamationmark.triangle").foregroundStyle(TeamStatsStyle.errorText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Section("Free throws · \(team == .our ? "Our player" : "Opponent")") {
                    if team == .our, let player = recorder.visibleDocument?.players.first(where: { $0.id == playerID }) {
                        Text("\(player.name) · #\(player.number)").font(.headline)
                    }
                    Text("The current team/player is fixed for this series. Each answer is independent; unanswered means pending.")
                    ForEach([1, 2, 3], id: \.self) { value in Button("\(value) attempts") { attempts = String(value) } .frame(minHeight: 44) }
                    TextField("Other positive whole-number attempts", text: $attempts).keyboardType(.numberPad).focused($focused)
                    if count == nil { Text("Enter a positive whole number within the supported integer range.").foregroundStyle(TeamStatsStyle.errorText) }
                }
            }.navigationTitle("Free throws")
            .safeAreaInset(edge: .bottom) {
                Button("Start free throws") {
                    guard let count else { return }; focused = false
                    Task {
                        var id: UUID?
                        await recorder.change { id = try $0.startFreeThrows(team: team, playerID: playerID, attempts: count) }
                        if let id, recorder.visibleDocument?.journal.last?.eventID == id { started(id) }
                    }
                }.buttonStyle(.borderedProminent).tint(TeamStatsStyle.filledAccent)
                    .disabled(count == nil || !recorder.canChange).frame(minHeight: 44).padding(16).background(.bar)
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(recorder.isBusy) } }
        }.interactiveDismissDisabled(recorder.isBusy)
    }
}

private struct ShotFreeThrowAnswers: View {
    let recorder: ShotCaptureRecorder
    let event: ShotCaptureEvent
    @State private var page = 0
    @State private var attempts: String
    init(recorder: ShotCaptureRecorder, event: ShotCaptureEvent) {
        self.recorder = recorder; self.event = event
        _attempts = State(initialValue: String(event.freeThrowAttempts ?? 0))
    }
    private var count: Int { event.freeThrowAttempts ?? 0 }
    private var correctedCount: Int? {
        guard case let .value(value) = BoxScoreCount(attempts),
              (1...ShotCaptureDocument.maximumAttempts).contains(value),
              event.answers.allSatisfy({ $0.index <= value }) else { return nil }
        return value
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attempt count correction").font(.subheadline.bold())
            TextField("Correct number of attempts", text: $attempts).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
            Button("Update attempt count") {
                guard let value = correctedCount else { return }
                var corrected = event; corrected.freeThrowAttempts = value
                Task { await recorder.change { try $0.correct(corrected) } }
            }.frame(minHeight: 44).disabled(correctedCount == nil || correctedCount == count)
            if correctedCount == nil {
                Text("Count correction not saved. Enter a positive whole number without removing answered attempts.")
                    .foregroundStyle(TeamStatsStyle.errorText)
            } else if correctedCount != count { Text("Count correction not saved until Update.").font(.footnote) }
            Text("Positive whole numbers only. A reduction cannot discard an answered attempt; clear its answer explicitly first.").font(.footnote)
            if count > 0 {
                let start = min(page * 10 + 1, count), end = min(start + 9, count)
                ForEach(start...end, id: \.self) { index in
                    let answer = event.answers.first { $0.index == index }?.outcome
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FT\(index)/\(count) · \(answer == nil ? "Pending" : answer == .made ? "Make" : "Miss")").font(.headline)
                        ViewThatFits(in: .horizontal) {
                            HStack { answerButton(index, .made); answerButton(index, .missed); answerButton(index, nil) }
                            VStack(alignment: .leading) { answerButton(index, .made); answerButton(index, .missed); answerButton(index, nil) }
                        }
                    }
                }
                if count > 10 {
                    HStack {
                        Button("Previous attempts") { page = max(0, page - 1) }.disabled(page == 0)
                        Button("Next attempts") { page += 1 }.disabled(end == count)
                    }.frame(minHeight: 44)
                    Text("Attempts\(start)–\(end) of\(count). Answers persist across pages.").font(.footnote)
                }
            }
        }
        .onChange(of: count) { _, value in page = 0; attempts = String(value) }
    }
    private func answerButton(_ index: Int, _ outcome: ShotOutcome?) -> some View {
        Button(outcome == nil ? "Pending" : outcome == .made ? "Make" : "Miss") {
            Task { await recorder.change { try $0.answerFreeThrow(seriesID: event.id, index: index, outcome: outcome) } }
        }.buttonStyle(.bordered).frame(minHeight: 44)
            .accessibilityLabel("Free throw\(index) \(outcome == nil ? "Pending" : outcome == .made ? "Make" : "Miss")")
            .accessibilityIdentifier("shot.ft.\(index).\(outcome?.rawValue ?? "pending")")
    }
}
