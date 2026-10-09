//
//  ContentView.swift
//  TeamStats
//
//  Created by Narayan Lekhi on 10/8/26.
//

import SwiftUI
import Foundation

struct ContentView: View {
    @State private var games: [Game] = []
    @State private var loadError: String?
    @State private var showingNewGame = false

    var body: some View {
        TabView {
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
                            Text("Add a game to save its details on this device.")
                        }
                    } else {
                        List(games) { game in
                            NavigationLink {
                                GameDetailsView(game: game)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(game.opponent)
                                        .font(.headline)
                                    Text(game.date, format: .dateTime.month().day().year())
                                        .foregroundStyle(.secondary)
                                    Text("\(game.venue.rawValue) · \(game.kind.rawValue)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Games")
                .toolbar {
                    Button("Add game", systemImage: "plus") {
                        showingNewGame = true
                    }
                    .disabled(loadError != nil)
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
                Label("Games", systemImage: "basketball")
            }

            NavigationStack {
                List {
                    Section {
                        ForEach(temporaryRoster) { player in
                            LabeledContent(player.name, value: "#\(player.number)")
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
        }
        .task { loadGames() }
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

private enum GameStorage {
    private static func fileURL() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("games.json")
    }

    static func load() throws -> [Game] {
        let url = try fileURL()
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
        return try JSONDecoder().decode([Game].self, from: data)
    }

    static func save(_ games: [Game]) throws {
        let data = try JSONEncoder().encode(games)
        try data.write(to: fileURL(), options: .atomic)
    }
}

private struct NewGameView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var opponent = ""
    @State private var venue: Game.Venue = .home
    @State private var kind: Game.Kind = .regularSeason
    @State private var saveError: String?

    let save: (Game) -> String?

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
                            .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
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
                    Button("Cancel") { dismiss() }
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
        }
    }
}

private struct GameDetailsView: View {
    let game: Game
    @State private var entryMode: BoxScoreEntryMode?
    @State private var showingPossessions = false
    @State private var showingPlayerPaintTouches = false
    @State private var showingSummary = false

    var body: some View {
        Form {
            Section("Game details") {
                LabeledContent("Date") {
                    Text(game.date, format: .dateTime.month().day().year())
                }
                LabeledContent("Opponent", value: game.opponent)
                LabeledContent("Our team", value: game.venue.rawValue)
                LabeledContent("Game type", value: game.kind.rawValue)
            }
            Section("Local box-score draft") {
                Button("Single-player entry") {
                    entryMode = .player
                }
                Button("Whole-roster table entry") {
                    entryMode = .table
                }
                Text("After-game entry only. Drafts are saved on this device, not published.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Local game summary") { showingSummary = true }
                Button("Player paint-touch drafts") { showingPlayerPaintTouches = true }
                Button("Possession draft entry") { showingPossessions = true }
                Text("Incomplete, unreviewed local drafts. Advanced-sheet reconciliation is unavailable.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(game.opponent)
        .sheet(item: $entryMode) { mode in
            BoxScoreEditor(gameID: game.id, initialMode: mode)
        }
        .sheet(isPresented: $showingPossessions) {
            PossessionEditor(game: game)
        }
        .sheet(isPresented: $showingPlayerPaintTouches) {
            PlayerPaintTouchEditor(game: game)
        }
        .sheet(isPresented: $showingSummary) {
            GameSummaryView(game: game)
        }
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
