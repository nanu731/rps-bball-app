import Foundation
import SwiftUI

func summaryCount(_ number: Int?) -> String {
    number.map(String.init) ?? "Not entered"
}

func summaryRebounds(_ values: [String: Int]) -> String {
    guard let offensive = values[BoxScoreField.offensiveRebounds.rawValue],
          let defensive = values[BoxScoreField.defensiveRebounds.rawValue] else {
        return "Not entered — requires offensive and defensive rebounds"
    }
    guard let total = boxScoreSum([offensive, defensive]) else {
        return "Unavailable — exceeds the supported calculation range"
    }
    return String(total)
}

func summaryShotCheck(_ values: [String: Int]) -> String {
    boxScoreShotCheck(values.mapValues(String.init))
}

struct GameSummaryView: View {
    let game: Game
    @Environment(\.dismiss) private var dismiss
    @State private var boxScores: [PlayerBoxScore] = []
    @State private var possessions: [PossessionRecord] = []
    @State private var paintTouches: [PlayerPaintTouchRecord] = []
    @State private var boxError: String?
    @State private var possessionError: String?
    @State private var paintError: String?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            List {
                Section("Game details") {
                    Text("Local draft — incomplete and unreviewed").font(.headline)
                    LabeledContent("Date") {
                        Text(game.date, format: .dateTime.month().day().year())
                    }
                    LabeledContent("Opponent", value: game.opponent)
                    LabeledContent("Our team", value: game.venue.rawValue)
                    LabeledContent("Game type", value: game.kind.rawValue)
                    Text("Read-only saved data. Use the entry screens to edit. Advanced-sheet reconciliation is unavailable.")
                        .foregroundStyle(.secondary)
                }
                if !loaded {
                    ProgressView("Loading saved drafts")
                } else {
                    Section("Our players · Temporary roster") {
                        if let boxError { failure("box scores", error: boxError) }
                        else if boxScores.isEmpty { Text("No box-score records saved for this game.") }
                        if let paintError { failure("player paint touches", error: paintError) }
                        else if paintTouches.isEmpty { Text("No player paint-touch records saved for this game.") }
                        ForEach(temporaryRoster) { player in
                            NavigationLink("\(player.name) · #\(player.number)") {
                                PlayerSummaryView(player: player,
                                    boxScore: boxScores.first { $0.playerID == player.id },
                                    paintTouch: paintTouches.first { $0.playerID == player.id },
                                    boxError: boxError, paintError: paintError)
                            }
                        }
                    }
                    if let possessionError {
                        Section("Possession records") { failure("possessions", error: possessionError) }
                    } else {
                        ForEach(PossessionTeam.allCases, id: \.self) { team in
                            Section("\(team.label) possession records") {
                                let records = possessions.filter { $0.team == team }.sorted { $0.number < $1.number }
                                LabeledContent("Records entered", value: String(records.count))
                                Text("Records entered, not final game possessions. Each team's numbering is independent.")
                                    .foregroundStyle(.secondary)
                                if records.isEmpty { Text("No possession records saved for this team.") }
                                ForEach(records) { record in
                                    NavigationLink("\(team.label) · Record \(record.number)") {
                                        PossessionSummaryView(record: record)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Local game summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { load() }
        }
    }

    private func failure(_ name: String, error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Could not load \(name): \(error)").foregroundStyle(.red)
            Button("Retry loading saved drafts") { load() }.frame(minHeight: 44)
        }
    }

    private func load() {
        do {
            boxScores = try BoxScoreStorage.load(from: BoxScoreStorage.fileURL()).filter { $0.gameID == game.id }
            boxError = nil
        } catch { boxScores = []; boxError = error.localizedDescription }
        do {
            possessions = try PossessionStorage.load(from: PossessionStorage.fileURL()).filter { $0.gameID == game.id }
            possessionError = nil
        } catch { possessions = []; possessionError = error.localizedDescription }
        do {
            paintTouches = try PlayerPaintTouchStorage.load(from: PlayerPaintTouchStorage.fileURL()).filter { $0.gameID == game.id }
            paintError = nil
        } catch { paintTouches = []; paintError = error.localizedDescription }
        loaded = true
    }
}

private struct PlayerSummaryView: View {
    let player: TemporaryPlayer
    let boxScore: PlayerBoxScore?
    let paintTouch: PlayerPaintTouchRecord?
    let boxError: String?
    let paintError: String?

    var body: some View {
        List {
            Section {
                Text("\(player.name) · #\(player.number)").font(.headline)
                Text("Temporary roster. Local draft — incomplete and unreviewed.")
                    .foregroundStyle(.secondary)
            }
            Section("Saved box score") {
                if let boxError {
                    Text("Could not load box score: \(boxError). Return to the summary to Retry.")
                        .foregroundStyle(.red)
                } else {
                    let values = boxScore?.values ?? [:]
                    ForEach(BoxScoreField.allCases, id: \.self) { field in
                        LabeledContent(field.label, value: summaryCount(values[field.rawValue]))
                    }
                    LabeledContent("Total rebounds", value: summaryRebounds(values))
                    Text(summaryShotCheck(values))
                }
            }
            Section("Independent player game total") {
                if let paintError {
                    Text("Could not load paint touches: \(paintError). Return to the summary to Retry.")
                        .foregroundStyle(.red)
                } else {
                    LabeledContent("Game-total paint touches", value: summaryCount(paintTouch?.total))
                    Text("Independently recorded; not calculated from possession records.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Player summary")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PossessionSummaryView: View {
    let record: PossessionRecord

    var body: some View {
        List {
            Section {
                Text("\(record.team.label) · Record \(record.number)").font(.headline)
                Text("Local draft — incomplete and unreviewed")
                    .foregroundStyle(.secondary)
            }
            Section("Saved possession record") {
                ForEach(PossessionField.allCases, id: \.self) { field in
                    LabeledContent(field.label, value: summaryCount(record.values[field.rawValue]))
                }
                LabeledContent("Turnover", value: record.turnover.map { $0 ? "Yes" : "No" } ?? "Not entered")
            }
        }
        .navigationTitle("Possession record")
        .navigationBarTitleDisplayMode(.inline)
    }
}
