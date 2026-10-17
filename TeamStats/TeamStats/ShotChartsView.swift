import SwiftUI

struct ShotChartsView: View {
    let document: ShotCaptureDocument
    let status: String
    var score: ShotScoreReference? = nil
    var officialSources: (ShotTeam, String?) -> [ShotOfficialSource] = { _, _ in [] }
    var isVisible: () -> Bool = { true }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var team: ShotTeam = .our
    @State private var playerID = ""
    @State private var flipped = false
    @State private var observationLimit = 20
    private var analysis: Result<ShotAnalysis, Error> {
        Result { try ShotAnalysis(document: document, team: team, playerID: playerID.isEmpty ? nil : playerID) }
    }
    var body: some View {
        if !isVisible() { ContentUnavailableView("Capture concealed", systemImage: "lock") }
        else {
            List {
                Section("Capture scope") {
                    Text(status).font(.headline)
                    Text("Attempt coverage unverified. Score agreement cannot prove that missed attempts or every location were recorded. Final coverage signoff still needs an owner decision.")
                        .font(.footnote)
                    Picker("Chart team", selection: $team) { Text("Our team").tag(ShotTeam.our); Text("Opponent").tag(ShotTeam.opponent) }.pickerStyle(.segmented)
                        .accessibilityIdentifier("shot.chart.team")
                    if team == .our {
                        Picker("Chart player", selection: $playerID) {
                            Text("All our players").tag("")
                            ForEach(document.players) { Text("\($0.name) · #\($0.number)").tag($0.id) }
                        }.frame(minHeight: 44)
                        if dynamicTypeSize.isAccessibilitySize {
                            Text(playerID.isEmpty ? "All our players" : document.players.first(where: { $0.id == playerID }).map { "\($0.name) · #\($0.number)" } ?? "Player selection unavailable")
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("shot.chart.selection")
                        }
                    } else { Text("Opponent · team-only observations; no invented player identities.").font(.footnote) }
                }
                switch analysis {
                case .failure:
                    Section { Label("Captured data could not be validated. No chart totals are shown.", systemImage: "exclamationmark.triangle") }
                case .success(let analysis):
                    chartSections(analysis)
                }
            }
            .navigationTitle("Recorded shot charts").navigationBarTitleDisplayMode(.inline)
            .onChange(of: team) { _, _ in playerID = ""; observationLimit = 20 }
            .onChange(of: playerID) { _, _ in observationLimit = 20 }
        }
    }
    @ViewBuilder private func chartSections(_ analysis: ShotAnalysis) -> some View {
        Section("Recorded field-goal origins") {
            if analysis.events.isEmpty { Text("No observations entered for this selection. This does not mean no attempts occurred.") }
            ShotCourtView(events: analysis.fieldGoals, flipped: flipped)
                .aspectRatio(0.65, contentMode: .fit).frame(maxWidth: 420)
            Text("● Make · × Miss · ? Pending. Schematic full court; explicit2/3 values determine points. Free throws have no court dots.").font(.footnote)
            Button(flipped ? "Restore chart display" : "Flip chart display") { flipped.toggle() }.frame(minHeight: 44)
        }
        Section("Observed totals · separate from official stats") {
            LabeledContent(team == .opponent ? "Recorded points allowed" : "Recorded points", value: String(analysis.points))
            if analysis.pending > 0 { Text("Entered-data scoring subtotal / lower bound · \(analysis.pending) pending outcomes.").font(.footnote) }
            ForEach(ShotMetric.allCases) { metric in
                let count = analysis.count(metric)
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent(metric.label, value: String(count.value))
                    if count.pending > 0 { Text("Lower bound · \(count.pending) observations still affect this count").font(.caption) }
                }
            }
            Text("FT attempts include their explicitly entered pending answers; pending outcomes are never counted as misses. FG attempts with unknown2/3 value remain unclassified.").font(.footnote)
        }
        Section("Basket-relative field-goal bands") {
            Text("Equal-width left/center/right bands, normalized toward each shot’s attacking basket. These are supported schematic zones, not regulation arcs, distances or shot quality.").font(.footnote)
            ForEach(analysis.bands) { band in
                VStack(alignment: .leading, spacing: 4) {
                    Text(band.label).font(.headline)
                    Text("\(band.made) made · \(band.missed) missed · \(band.pending) pending · \(band.points) recorded points")
                    Text(band.conversion.map { "\(($0 * 100).formatted(.number.precision(.fractionLength(1))))% of \(band.answered) answered FG attempts" } ?? "Conversion unavailable — no answered FG attempts")
                        .font(.footnote)
                }.accessibilityElement(children: .combine)
            }
        }
        Section("Independent official score") {
            if playerID.isEmpty {
                let official = team == .our ? score?.our_points : score?.opponent_points
                LabeledContent("Confirmed score", value: official.map(String.init) ?? "Unavailable")
                Label(analysis.scoreCheck(official: official).label, systemImage: "info.circle")
                if let score, let source = score.source_note { Text("Independent reference revision \(score.revision): \(source)").font(.footnote) }
                Text("Matching recorded points is score agreement only. It does not establish attempt coverage, location accuracy, review or whole-game completion.").font(.footnote)
            } else { Text("Team score is not compared to one player. See independent player counts below.") }
        }
        Section("Independent after-game count comparisons") {
            let sources = officialSources(team, playerID.isEmpty ? nil : playerID)
            if sources.isEmpty { Text("Unavailable — no independent saved source loaded for this selection.") }
            ForEach(sources) { source in
                Text(source.label).font(.headline)
                ForEach(ShotMetric.allCases) { metric in
                    let official = source.counts[metric]
                    VStack(alignment: .leading, spacing: 4) {
                        Text(metric.label).font(.subheadline.bold())
                        Text("Captured \(analysis.count(metric).value) · Independent \(official?.value.map(String.init) ?? "Not entered / unavailable")")
                        Text(analysis.countCheck(metric, official: official?.value).label).font(.footnote)
                        if let official, official.missing > 0 { Text("\(official.missing) saved row inputs missing; no zero substitution.").font(.caption) }
                    }
                }
            }
            Text("Compare sources; never add them together or rewrite one to force agreement. Agreement in totals cannot establish event-by-event accuracy.").font(.footnote)
        }
        Section("Individual observations · read-only") {
            ForEach(Array(analysis.events.prefix(observationLimit))) { event in
                VStack(alignment: .leading, spacing: 4) {
                    if let player = document.players.first(where: { $0.id == event.playerID }) { Text("\(player.name) · #\(player.number)").font(.headline) }
                    if event.kind == .fieldGoal {
                        Text("\(event.value.map(String.init) ?? "Unclassified") PT · \(event.outcome?.rawValue ?? "Pending")")
                        if let p = event.location { Text("Approximate normalized location: \(p.x.formatted(.number.precision(.fractionLength(2)))), \(p.y.formatted(.number.precision(.fractionLength(2)))) · attacking \(event.basket?.rawValue ?? "Unavailable")").font(.footnote) }
                    } else {
                        Text("FT\(event.answers.filter { $0.outcome == .made }.count)/\(event.freeThrowAttempts ?? 0) made · \(event.answers.count) answered; remaining pending")
                    }
                }.accessibilityElement(children: .combine)
            }
            if analysis.events.count > observationLimit { Button("Show20 more observations") { observationLimit += 20 } }
        }
    }
}

struct LocalShotChartsView: View {
    let game: Game
    @State private var document: ShotCaptureDocument?
    @State private var issue: String?
    @State private var sourceIssues: [String] = []
    @State private var boxes: [PlayerBoxScore] = []
    @State private var possessions: [PossessionRecord] = []
    @State private var didLoad = false
    @State private var boxesLoaded = false
    @State private var possessionsLoaded = false
    var body: some View {
        Group {
            if let issue { ContentUnavailableView { Label("Could not load charts", systemImage: "exclamationmark.triangle") } description: { Text(issue) } actions: { Button("Retry") { Task { await load() } } } }
            else if let document {
                VStack(spacing: 0) {
                    if !sourceIssues.isEmpty {
                        VStack(alignment: .leading) { ForEach(sourceIssues, id: \.self) { Text($0).font(.footnote) }; Button("Retry independent sources") { Task { await load() } } }.padding()
                    }
                    ShotChartsView(document: document, status: "Local draft · incomplete and unreviewed · Temporary roster", officialSources: { team, player in
                        var result: [ShotOfficialSource] = []
                        if team == .our, boxesLoaded {
                            result.append(.boxes(boxes, expectedPlayerIDs: player.map { [$0] } ?? document.players.map(\.id), label: "Device box-score draft · independently entered, unreviewed"))
                        }
                        if player == nil, possessionsLoaded {
                            let rows = possessions.filter { $0.team == (team == .our ? .ours : .opponent) }
                            result.append(.possessions(rows, label: "Device possession draft · \(rows.count) records entered, not final game possessions"))
                        }
                        return result
                    })
                }
            } else if didLoad { ContentUnavailableView("No recorded shots", systemImage: "basketball", description: Text("Start the optional recorder from this game’s details. No observations were manufactured.")) }
            else { ProgressView("Loading saved capture") }
        }.navigationTitle("Recorded shot charts").task { await load() }
    }
    private func load() async {
        issue = nil; sourceIssues = []; document = nil; didLoad = false
        do {
            let url = try GameStorage.fileURL().deletingLastPathComponent().appendingPathComponent("shot-local-\(game.id.uuidString).json")
            if FileManager.default.fileExists(atPath: url.path) {
                document = try await ShotCaptureDisk.shared.load(from: url, context: ShotCaptureContext(gameID: game.id, teamID: nil, actorID: nil, assignmentRevision: nil))
            }
        } catch { issue = "Saved capture could not be read. Existing files remain; this is not an empty-data result." }
        do { boxes = try BoxScoreStorage.load(from: BoxScoreStorage.fileURL()).filter { $0.gameID == game.id }; boxesLoaded = true }
        catch { boxes = []; boxesLoaded = false; sourceIssues.append("Box-score source failed to load; its comparisons are unavailable.") }
        do { possessions = try PossessionStorage.load(from: PossessionStorage.fileURL()).filter { $0.gameID == game.id }; possessionsLoaded = true }
        catch { possessions = []; possessionsLoaded = false; sourceIssues.append("Possession source failed to load; its comparisons are unavailable.") }
        didLoad = true
    }
}
