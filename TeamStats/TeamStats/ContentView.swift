//
//  ContentView.swift
//  TeamStats
//
//  Created by Narayan Lekhi on 10/8/26.
//

import SwiftUI
import Foundation

struct ContentView: View {
    @State private var account = BackendAccount()
    @State private var selectedTab = Tab.local
    private enum Tab: Hashable { case local, players, team, clips, account }
    @State private var games: [Game] = []
    @State private var loadError: String?
    @State private var showingNewGame = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                Group {
                    if let loadError {
                        ContentUnavailableView {
                            Label("Could not load games", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(loadError)
                        } actions: {
                            Button("Retry", action: loadGames)
                        }
                    } else if games.isEmpty {
                        ContentUnavailableView {
                            Label("No games yet", systemImage: "basketball")
                        } description: {
                            Text("Add a local draft on this device. Use Team for official shared records.")
                        }
                    } else {
                        List(games) { game in
                            NavigationLink {
                                GameDetailsView(game: game)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(game.opponent).font(.headline)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(game.date, format: .dateTime.month().day().year())
                                        .font(.subheadline.weight(.semibold)).foregroundStyle(Color.accentColor)
                                    Text("\(game.venue.rawValue) · \(game.kind.rawValue)")
                                        .font(.subheadline)
                                }.padding(.vertical, 8)
                            }
                        }
                    }
                }
                .navigationTitle("Local games")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink { TeamStatsGuide() } label: {
                            Label("Using TeamStats", systemImage: "questionmark.circle")
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink { PreparedShotCapturesView(account: account) } label: { Label("Device shot captures", systemImage: "basketball.fill") }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Add game", systemImage: "plus") {
                            showingNewGame = true
                        }
                        .disabled(loadError != nil)
                    }
                }
                .sheet(isPresented: $showingNewGame) {
                    NewGameView { game in
                        let updatedGames = [game] + games
                        do {
                            try GameStorage.save(updatedGames)
                            games = updatedGames
                            return nil
                        } catch {
                            return error.localizedDescription
                        }
                    }
                }
            }
            .tabItem {
                Label("Local drafts", systemImage: "basketball")
            }
            .tag(Tab.local)

            NavigationStack {
                List {
                    Section {
                        ForEach(temporaryRoster) { player in
                            HStack(alignment: .firstTextBaseline, spacing: 16) {
                                Text("#\(player.number)").font(.title3.bold()).monospacedDigit()
                                    .foregroundStyle(Color.accentColor).frame(minWidth: 44, alignment: .leading)
                                Text(player.name).font(.headline)
                            }.frame(minHeight: 44).accessibilityElement(children: .combine)
                        }
                    } header: {
                        Text("Temporary roster")
                    } footer: {
                        Text("Development placeholders. The actual team roster will replace these after tryouts.")
                    }
                }
                .navigationTitle("Players")
            }
            .tabItem {
                Label("Players", systemImage: "person.3")
            }
            .tag(Tab.players)

            TeamWorkspaceView(account: account) { selectedTab = .account }
                .id(account.sessionContextID)
                .tabItem { Label("Team", systemImage: "person.2") }
                .tag(Tab.team)

            NavigationStack {
                OfflineClipsView(account: account) { selectedTab = .account }
            }
            .id(account.offlineClipActorID)
            .tabItem { Label("Saved clips", systemImage: "arrow.down.circle") }
            .tag(Tab.clips)

            NavigationStack {
                AccountView(account: account) { selectedTab = .team }
            }
            .id(account.sessionContextID)
            .tabItem {
                Label("Account", systemImage: "person.crop.circle")
            }
            .tag(Tab.account)
        }
        .tint(.accentColor)
        .toggleStyle(SwitchToggleStyle(tint: TeamStatsStyle.filledAccent))
        .task { loadGames() }
        .onOpenURL { url in
            guard url.scheme == BackendAccount.emailRedirectURL.scheme else { return }
            Task { await account.handleEmailLink(url) }
        }
    }

    private func loadGames() {
        do {
            games = try GameStorage.load()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

struct Game: Codable, Identifiable {
    let id: UUID
    let date: Date
    let opponent: String
    let venue: Venue
    let kind: Kind

    enum Venue: String, Codable, CaseIterable {
        case home = "Home"
        case away = "Away"
    }

    enum Kind: String, Codable, CaseIterable {
        case regularSeason = "Regular season"
        case playoff = "Playoff"
    }
}

enum GameStorage {
    static func fileURL() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("games.json")
    }

    static func load() throws -> [Game] { try load(from: fileURL()) }

    static func load(from url: URL) throws -> [Game] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
        let games = try JSONDecoder().decode([Game].self, from: data)
        try validate(games)
        return games
    }

    static func save(_ games: [Game]) throws { try save(games, to: fileURL()) }

    static func save(_ games: [Game], to url: URL) throws {
        try validate(games)
        let data = try JSONEncoder().encode(games)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private static func validate(_ games: [Game]) throws {
        guard Set(games.map(\.id)).count == games.count,
              games.allSatisfy({ !$0.opponent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw CocoaError(.coderReadCorrupt)
        }
    }
}

private struct NewGameView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var initialDate: Date
    @State private var opponent = ""
    @State private var venue: Game.Venue = .home
    @State private var kind: Game.Kind = .regularSeason
    @State private var saveError: String?
    @State private var confirmingLeave = false

    let save: (Game) -> String?

    init(save: @escaping (Game) -> String?) {
        self.save = save
        let initial = Date()
        _date = State(initialValue: initial)
        _initialDate = State(initialValue: initial)
    }

    private var hasChanges: Bool {
        !opponent.isEmpty || date != initialDate || venue != .home || kind != .regularSeason
    }

    private var trimmedOpponent: String {
        opponent.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Game details") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Opponent", text: $opponent)
                        .textInputAutocapitalization(.words)
                    if trimmedOpponent.isEmpty {
                        Text("Opponent is required.")
                            .foregroundStyle(TeamStatsStyle.secondaryText)
                    }
                    Picker("Our team", selection: $venue) {
                        ForEach(Game.Venue.allCases, id: \.self) { venue in
                            Text(venue.rawValue).tag(venue)
                        }
                    }
                    Picker("Game type", selection: $kind) {
                        ForEach(Game.Kind.allCases, id: \.self) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                }
                Section {
                    Text("Saved only on this device. Player box-score drafts are available from game details.")
                        .foregroundStyle(TeamStatsStyle.secondaryText)
                }
                if let saveError {
                    Section("Could not save game") {
                        Text(saveError)
                    }
                }
            }
            .navigationTitle("New game")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges { confirmingLeave = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard !trimmedOpponent.isEmpty else { return }
                        let game = Game(id: UUID(), date: date, opponent: trimmedOpponent,
                                        venue: venue, kind: kind)
                        saveError = save(game)
                        if saveError == nil { dismiss() }
                    }
                    .disabled(trimmedOpponent.isEmpty)
                }
            }
            .interactiveDismissDisabled(hasChanges)
            .confirmationDialog("Discard unsaved game details?", isPresented: $confirmingLeave, titleVisibility: .visible) {
                Button("Discard unsaved details", role: .destructive) { dismiss() }
                Button("Keep editing") { }
            } message: {
                Text("These new game details have not been saved. Existing games stay unchanged.")
            }
        }
    }
}

private struct GameDetailsView: View {
    let game: Game
    @State private var entryMode: BoxScoreEntryMode?
    @State private var entryPlayerID: String?
    @State private var showingPossessions = false
    @State private var showingPlayerPaintTouches = false
    @State private var showingSummary = false
    @State private var showingBoxScore = false
    @State private var expandedPlayers: Set<String> = []
    @State private var boxes: [PlayerBoxScore] = []
    @State private var paint: [PlayerPaintTouchRecord] = []
    @State private var possessions: [PossessionRecord] = []
    @State private var errors: [String: String] = [:]
    @State private var loaded = false
    @State private var headerHeight: CGFloat = 0

    private var subtotal: BoxScoreSubtotal {
        BoxScoreSubtotal(temporaryRoster.map { player in boxes.first { $0.playerID == player.id }?.values["points"] })
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ScrollView {
                    GameLedgerHeader(game: game,
                        points: !loaded ? "Loading" : errors["box"] == nil ? subtotal.valueText : "Unavailable",
                        coverage: errors["box"] == nil ? subtotal.coverageText : "Could not load box scores")
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                }
                .frame(height: min(headerHeight, geometry.size.height * 0.4))
                .scrollBounceBehavior(.basedOnSize)
                HStack(spacing: 0) {
                    sectionButton("Game", selected: !showingBoxScore) { showingBoxScore = false }
                    sectionButton("Box score", selected: showingBoxScore) { showingBoxScore = true }
                    sectionButton("Enter stats", selected: entryMode != nil) { entryMode = .player }
                }
                Divider()
                if showingBoxScore {
                    if let error = errors["box"] {
                        ContentUnavailableView {
                            Label("Could not load box scores", systemImage: "exclamationmark.triangle")
                        } description: { Text(error) } actions: { Button("Retry", action: reload) }
                    } else if loaded {
                        SavedBoxScoreTable(records: boxes, paintTouches: paint, paintError: errors["paint"],
                            expanded: $expandedPlayers) { player in
                                entryPlayerID = player.id; entryMode = .player
                            }
                    } else { ProgressView("Loading saved box scores") }
                } else { gameTasks }
            }
            .background(Color(uiColor: .systemBackground))
        }
        .navigationTitle("Game").navigationBarTitleDisplayMode(.inline)
        .task { reload() }
        .sheet(item: $entryMode, onDismiss: reload) { mode in
            BoxScoreEditor(game: game, initialMode: mode, initialPlayerID: entryPlayerID)
        }
        .sheet(isPresented: $showingPossessions, onDismiss: reload) { PossessionEditor(game: game) }
        .sheet(isPresented: $showingPlayerPaintTouches, onDismiss: reload) { PlayerPaintTouchEditor(game: game) }
        .sheet(isPresented: $showingSummary) { GameSummaryView(game: game) }
    }

    private func sectionButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(selected ? .bold : .regular))
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay(alignment: .bottom) { if selected { Rectangle().frame(height: 3) } }
        }
        .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var gameTasks: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Game details").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Button("View box score") { showingBoxScore = true }
                    .buttonStyle(.borderedProminent).tint(TeamStatsStyle.filledAccent).frame(minHeight: 44)
                NavigationLink { LocalShotCaptureView(game: game) } label: {
                    TeamTaskLabel(title: "Shot recorder", detail: "Optional in-game capture · separate local draft", symbol: "basketball")
                }.accessibilityIdentifier("Shot recorder")
                task("Single-player entry", "One player's box score at a time", "person") { entryMode = .player }
                task("Whole-roster table entry", "The same draft, with native table scrolling", "tablecells") { entryMode = .table }
                task("Player paint-touch drafts", "Independently recorded game totals", "person.crop.rectangle") { showingPlayerPaintTouches = true }
                task("Possession draft entry", "Our team left; opponent right", "rectangle.split.2x1") { showingPossessions = true }
                task("Local game summary", "All saved observations, read-only", "list.bullet.rectangle") { showingSummary = true }
                Text("Record status").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                status("Player box scores", detail: "\(boxes.count) saved records", error: errors["box"])
                status("Our-team possessions", detail: "\(possessions.filter { $0.team == .ours }.count) records entered", error: errors["possessions"])
                status("Opponent possessions", detail: "\(possessions.filter { $0.team == .opponent }.count) records entered", error: errors["possessions"])
                status("Player paint touches", detail: "\(paint.filter { $0.total != nil }.count) entered totals", error: errors["paint"])
                Text("Saved on this device, not submitted or published. Possession counts are records entered, not final game possessions.")
                    .font(.footnote).foregroundStyle(TeamStatsStyle.secondaryText)
            }.padding(16)
        }
    }

    private func task(_ title: String, _ detail: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Button(action: action) { TeamTaskLabel(title: title, detail: detail, symbol: symbol) }.buttonStyle(.plain)
            Divider()
        }
    }

    private func status(_ title: String, detail: String, error: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            if let error {
                Text("Could not load: \(error)").foregroundStyle(TeamStatsStyle.errorText)
                Button("Retry saved observations", action: reload).frame(minHeight: 44)
            } else {
                Text(loaded ? detail : "Loading saved records")
                Text("Incomplete · Unreviewed").foregroundStyle(TeamStatsStyle.secondaryText)
            }
            Divider()
        }.font(.subheadline)
    }

    private func reload() {
        do { boxes = try BoxScoreStorage.load(from: BoxScoreStorage.fileURL()).filter { $0.gameID == game.id }; errors["box"] = nil }
        catch { boxes = []; errors["box"] = error.localizedDescription }
        do { paint = try PlayerPaintTouchStorage.load(from: PlayerPaintTouchStorage.fileURL()).filter { $0.gameID == game.id }; errors["paint"] = nil }
        catch { paint = []; errors["paint"] = error.localizedDescription }
        do { possessions = try PossessionStorage.load(from: PossessionStorage.fileURL()).filter { $0.gameID == game.id }; errors["possessions"] = nil }
        catch { possessions = []; errors["possessions"] = error.localizedDescription }
        loaded = true
    }
}

// These identities belong only to this temporary roster; never reuse them for actual players.
let temporaryRoster: [TemporaryPlayer] = [
    TemporaryPlayer(id: "temporary-roster-v1-a", name: "Temporary Player 1", number: 1),
    TemporaryPlayer(id: "temporary-roster-v1-b", name: "Temporary Player 2", number: 2),
    TemporaryPlayer(id: "temporary-roster-v1-c", name: "Temporary Player 3", number: 3),
    TemporaryPlayer(id: "temporary-roster-v1-d", name: "Temporary Player 4", number: 4),
    TemporaryPlayer(id: "temporary-roster-v1-e", name: "Temporary Player 5", number: 5)
]

#Preview {
    ContentView()
}
