import Foundation
import SwiftUI

struct PlayerPaintTouchRecord: Codable {
    let gameID: UUID
    let playerID: String
    // Missing totals remain unentered, including in saved incomplete drafts.
    var total: Int?

    var key: String { "\(gameID.uuidString):\(playerID)" }
}

enum PlayerPaintTouchStorage {
    static func fileURL() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("player-paint-touches.json")
    }

    static func load(from url: URL) throws -> [PlayerPaintTouchRecord] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
        let records = try JSONDecoder().decode([PlayerPaintTouchRecord].self, from: data)
        try validate(records)
        return records
    }

    static func save(_ records: [PlayerPaintTouchRecord], to url: URL) throws {
        try validate(records)
        try JSONEncoder().encode(records).write(to: url, options: .atomic)
    }

    static func updating(_ records: [PlayerPaintTouchRecord],
                         with drafts: [PlayerPaintTouchRecord]) -> [PlayerPaintTouchRecord] {
        let keys = Set(drafts.map(\.key))
        return records.filter { !keys.contains($0.key) } + drafts
    }

    private static func validate(_ records: [PlayerPaintTouchRecord]) throws {
        guard Set(records.map(\.key)).count == records.count,
              records.allSatisfy({ !$0.playerID.isEmpty && ($0.total == nil || $0.total! >= 0) }) else {
            throw CocoaError(.coderReadCorrupt)
        }
    }
}

struct PlayerPaintTouchEditor: View {
    let game: Game
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]
    @State private var loaded = false
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var hasChanges = false
    @State private var saved = false
    @FocusState private var focusedPlayer: String?

    private var invalid: Bool {
        values.values.contains { BoxScoreCount($0) == .invalid }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(game.opponent).font(.headline)
                    Text("Temporary roster")
                    Text("Incomplete, unreviewed drafts saved on this device.")
                        .foregroundStyle(.secondary)
                    Text("A paint touch is when a player intentionally establishes two feet in the paint with the ball.")
                    Text("Enter independently collected player game totals. These are not calculated from possessions. Blank means unentered; zero is explicit.")
                        .foregroundStyle(.secondary)
                }
                if let loadError {
                    Section("Could not load drafts") {
                        Text(loadError).foregroundStyle(.red)
                        Button("Retry") { load() }
                    }
                } else if loaded {
                    ForEach(temporaryRoster) { player in
                        Section("\(player.name) · #\(player.number)") {
                            Text("Game-total paint touches")
                            HStack(spacing: 12) {
                                counter(player, delta: -1)
                                TextField("Unentered", text: Binding(
                                    get: { values[player.id] ?? "" },
                                    set: { text in
                                        guard (values[player.id] ?? "") != text else { return }
                                        values[player.id] = text
                                        changed()
                                    }
                                ))
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                                .frame(minHeight: 44)
                                .focused($focusedPlayer, equals: player.id)
                                .accessibilityLabel("\(player.name), game-total paint touches")
                                .accessibilityIdentifier("paint-touches.\(player.id)")
                                counter(player, delta: 1)
                            }
                            if BoxScoreCount(values[player.id] ?? "") == .invalid {
                                Text("Enter a nonnegative whole number within the supported integer range, or leave blank.")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Player paint touches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.disabled(hasChanges)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    if invalid { Text("Fix invalid entries before saving.").foregroundStyle(.red) }
                    if let saveError { Text("Could not save drafts: \(saveError)").foregroundStyle(.red) }
                    if focusedPlayer != nil {
                        Button("Hide keyboard") { focusedPlayer = nil }
                            .frame(minHeight: 44)
                    }
                    HStack {
                        Text(hasChanges ? "Unsaved changes" : saved ? "Draft saved locally" : "Local draft")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Save draft") { save() }
                            .buttonStyle(.borderedProminent)
                            .frame(minHeight: 44)
                            .disabled(!loaded || invalid)
                    }
                }
                .padding()
                .background(.bar)
            }
            .interactiveDismissDisabled(hasChanges)
            .task { load() }
        }
    }

    private func counter(_ player: TemporaryPlayer, delta: Int) -> some View {
        let next = adjustedPossessionCount(values[player.id] ?? "", by: delta)
        return Button {
            guard let next = adjustedPossessionCount(values[player.id] ?? "", by: delta) else { return }
            values[player.id] = next
            changed()
        } label: {
            Image(systemName: delta == 1 ? "plus" : "minus")
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .disabled(next == nil)
        .accessibilityLabel("\(delta == 1 ? "Increase" : "Decrease") \(player.name) game-total paint touches by 1")
        .accessibilityValue(BoxScoreCount(values[player.id] ?? "").number.map(String.init) ?? "Unentered or invalid")
        .accessibilityIdentifier("paint-touches.\(player.id).\(delta == 1 ? "increase" : "decrease")")
    }

    private func changed() {
        hasChanges = true
        saved = false
        saveError = nil
    }

    private func load() {
        do {
            let records = try PlayerPaintTouchStorage.load(from: PlayerPaintTouchStorage.fileURL())
            values = Dictionary(uniqueKeysWithValues: records.filter { $0.gameID == game.id }
                .map { ($0.playerID, $0.total.map(String.init) ?? "") })
            loaded = true
            loadError = nil
        } catch {
            loaded = false
            loadError = error.localizedDescription
        }
    }

    private func save() {
        guard loaded, !invalid else { return }
        do {
            let url = try PlayerPaintTouchStorage.fileURL()
            let existing = try PlayerPaintTouchStorage.load(from: url)
            let drafts = temporaryRoster.map {
                PlayerPaintTouchRecord(gameID: game.id, playerID: $0.id,
                                      total: BoxScoreCount(values[$0.id] ?? "").number)
            }
            try PlayerPaintTouchStorage.save(PlayerPaintTouchStorage.updating(existing, with: drafts), to: url)
            hasChanges = false
            saved = true
            saveError = nil
        } catch { saveError = error.localizedDescription }
    }
}
