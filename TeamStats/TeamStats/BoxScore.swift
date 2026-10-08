import Foundation
import SwiftUI

struct TemporaryPlayer: Identifiable {
    let id: String
    let name: String
    let number: Int
}

enum BoxScoreField: String, CaseIterable {
    case points, offensiveRebounds, defensiveRebounds, assists, turnovers
    case steals, blocks, fouls, chargesDrawn
    case twosMade, twosMissed, threesMade, threesMissed, freeThrowsMade, freeThrowsMissed

    var label: String {
        switch self {
        case .points: "Points"
        case .offensiveRebounds: "Offensive rebounds"
        case .defensiveRebounds: "Defensive rebounds"
        case .assists: "Assists"
        case .turnovers: "Turnovers"
        case .steals: "Steals"
        case .blocks: "Blocks"
        case .fouls: "Fouls"
        case .chargesDrawn: "Charges drawn"
        case .twosMade: "Twos made"
        case .twosMissed: "Twos missed"
        case .threesMade: "Threes made"
        case .threesMissed: "Threes missed"
        case .freeThrowsMade: "Free throws made"
        case .freeThrowsMissed: "Free throws missed"
        }
    }
}

enum BoxScoreCount: Equatable {
    case missing, invalid, value(Int)

    init(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            self = .missing
        } else if text.utf8.allSatisfy({ (48...57).contains($0) }), let value = Int(text) {
            self = .value(value)
        } else {
            self = .invalid
        }
    }

    var number: Int? {
        if case let .value(number) = self { return number }
        return nil
    }
}

struct PlayerBoxScore: Codable {
    let gameID: UUID
    let playerID: String
    // Absent keys mean not entered; an explicit zero remains a stored value.
    var values: [String: Int]

    var key: String { "\(gameID.uuidString):\(playerID)" }
}

enum BoxScoreStorage {
    static func fileURL() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("box-scores.json")
    }

    static func load(from url: URL) throws -> [PlayerBoxScore] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
        let records = try JSONDecoder().decode([PlayerBoxScore].self, from: data)
        try validate(records)
        return records
    }

    static func save(_ records: [PlayerBoxScore], to url: URL) throws {
        try validate(records)
        try JSONEncoder().encode(records).write(to: url, options: .atomic)
    }

    static func updating(_ records: [PlayerBoxScore], with drafts: [PlayerBoxScore]) -> [PlayerBoxScore] {
        let keys = Set(drafts.map(\.key))
        return records.filter { !keys.contains($0.key) } + drafts
    }

    private static func validate(_ records: [PlayerBoxScore]) throws {
        let fields = Set(BoxScoreField.allCases.map(\.rawValue))
        guard Set(records.map(\.key)).count == records.count,
              records.allSatisfy({ !$0.playerID.isEmpty && $0.values.allSatisfy {
                  fields.contains($0.key) && $0.value >= 0
              } }) else {
            throw CocoaError(.coderReadCorrupt)
        }
    }
}

// Checked arithmetic also keeps pasted, very large whole numbers from crashing calculations.
func boxScoreSum(_ numbers: [Int]) -> Int? {
    var sum = 0
    for number in numbers {
        let result = sum.addingReportingOverflow(number)
        guard !result.overflow else { return nil }
        sum = result.partialValue
    }
    return sum
}

func boxScoreShotCheck(_ values: [String: String]) -> String {
    let fields: [BoxScoreField] = [.points, .twosMade, .threesMade, .freeThrowsMade]
    let counts = fields.map { BoxScoreCount(values[$0.rawValue] ?? "") }
    if counts.contains(.invalid) { return "Shot check unavailable: fix invalid inputs." }
    let numbers = counts.compactMap(\.number)
    guard numbers.count == fields.count else {
        return "Shot check incomplete: enter points and all three made-shot counts."
    }
    let twos = numbers[1].multipliedReportingOverflow(by: 2)
    let threes = numbers[2].multipliedReportingOverflow(by: 3)
    guard !twos.overflow, !threes.overflow,
          let implied = boxScoreSum([twos.partialValue, threes.partialValue, numbers[3]]) else {
        return "Shot check unavailable: counts exceed the supported calculation range."
    }
    if numbers[0] != implied {
        return "Points disagree: entered \(numbers[0]); made shots imply \(implied)."
    }
    return "Points match made shots (\(implied))."
}

enum BoxScoreEntryMode: String, CaseIterable, Identifiable {
    case player = "Single player"
    case table = "Roster table"
    var id: String { rawValue }
}

struct BoxScoreEditor: View {
    let gameID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var mode: BoxScoreEntryMode
    @State private var selectedPlayerID = temporaryRoster[0].id
    @State private var drafts: [String: [String: String]] = [:]
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var loaded = false
    @State private var hasChanges = false
    @State private var saved = false

    init(gameID: UUID, initialMode: BoxScoreEntryMode) {
        self.gameID = gameID
        _mode = State(initialValue: initialMode)
    }

    private var invalidEntries: [String] {
        temporaryRoster.flatMap { player in
            BoxScoreField.allCases.compactMap { field in
                count(player, field) == .invalid ? "\(player.name): \(field.label)" : nil
            }
        }
    }

    private var scoringSummary: String {
        let counts = temporaryRoster.map { count($0, .points) }
        guard !counts.contains(.invalid) else { return "Scoring total unavailable: fix invalid points." }
        let numbers = counts.compactMap(\.number)
        guard !numbers.isEmpty else { return "No points entered (0 of \(counts.count) players)." }
        guard let sum = boxScoreSum(numbers) else { return "Scoring total exceeds the supported calculation range." }
        if numbers.count == counts.count {
            return "Game points: \(sum) — all \(counts.count) temporary players' points entered. Other stats may be incomplete."
        }
        return "Entered points subtotal: \(sum) — incomplete (\(numbers.count) of \(counts.count) players)."
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let loadError {
                    ContentUnavailableView {
                        Label("Could not load box scores", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Retry", action: load)
                    }
                } else if loaded {
                    Picker("Entry mode", selection: $mode) {
                        ForEach(BoxScoreEntryMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Temporary roster · Local draft").font(.headline)
                        Text("Blank = not entered. Enter 0 explicitly. Nonnegative whole numbers only.")
                        Text(scoringSummary)
                        Text("Advanced-sheet reconciliation unavailable; possession drafts are incomplete and unreviewed.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    if mode == .player { playerForm } else { rosterTable }
                }
            }
            .navigationTitle("Box-score draft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.disabled(hasChanges)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    if !invalidEntries.isEmpty {
                        Text("Fix invalid numbers: \(invalidEntries.joined(separator: "; ")).")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    if let saveError { Text("Could not save draft: \(saveError)").font(.caption) }
                    HStack {
                        Text(hasChanges ? "Unsaved changes — save before closing." :
                             (saved ? "Draft saved on this device." : "Incomplete drafts can be saved."))
                            .font(.caption)
                        Spacer()
                        Button("Save draft", action: save)
                            .buttonStyle(.borderedProminent)
                            .disabled(!loaded || !invalidEntries.isEmpty)
                    }
                }
                .padding()
                .background(.regularMaterial)
            }
        }
        .interactiveDismissDisabled(hasChanges)
        .task { load() }
    }

    private var playerForm: some View {
        Form {
            Picker("Player", selection: $selectedPlayerID) {
                ForEach(temporaryRoster) { Text("\($0.name) #\($0.number)").tag($0.id) }
            }
            if let player = temporaryRoster.first(where: { $0.id == selectedPlayerID }) {
                Section("Player box score") {
                    ForEach(BoxScoreField.allCases, id: \.self) { field in
                        LabeledContent(field.label) { entry(player, field).frame(width: 95) }
                    }
                    LabeledContent("Total rebounds", value: rebounds(player))
                }
                Section("Points check") {
                    Text(boxScoreShotCheck(drafts[player.id] ?? [:]))
                }
            }
        }
    }

    private var rosterTable: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 12) {
                GridRow {
                    Text("Temporary player").frame(width: 170, alignment: .leading)
                    ForEach(BoxScoreField.allCases, id: \.self) { field in
                        Text(field.label).frame(width: 95)
                    }
                    Text("Total rebounds").frame(width: 130)
                    Text("Points check").frame(width: 270, alignment: .leading)
                }.font(.caption.bold())
                ForEach(temporaryRoster) { player in
                    GridRow {
                        Text("\(player.name) #\(player.number)")
                            .frame(width: 170, alignment: .leading)
                        ForEach(BoxScoreField.allCases, id: \.self) { field in
                            entry(player, field).frame(width: 95)
                        }
                        Text(rebounds(player)).frame(width: 130)
                        Text(boxScoreShotCheck(drafts[player.id] ?? [:]))
                            .font(.caption).frame(width: 270, alignment: .leading)
                    }
                }
            }.padding()
        }
    }

    private func entry(_ player: TemporaryPlayer, _ field: BoxScoreField) -> some View {
        TextField("Not entered", text: Binding(
            get: { drafts[player.id]?[field.rawValue] ?? "" },
            set: {
                drafts[player.id, default: [:]][field.rawValue] = $0
                hasChanges = true
                saved = false
                saveError = nil
            }
        ))
        .keyboardType(.numberPad)
        .textFieldStyle(.roundedBorder)
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(count(player, field) == .invalid ? .red : .clear))
        .accessibilityLabel("\(player.name), \(field.label)")
        .accessibilityIdentifier("\(player.id).\(field.rawValue)")
    }

    private func count(_ player: TemporaryPlayer, _ field: BoxScoreField) -> BoxScoreCount {
        BoxScoreCount(drafts[player.id]?[field.rawValue] ?? "")
    }

    private func rebounds(_ player: TemporaryPlayer) -> String {
        let counts = [count(player, .offensiveRebounds), count(player, .defensiveRebounds)]
        if counts.contains(.invalid) { return "Invalid input" }
        let numbers = counts.compactMap(\.number)
        guard numbers.count == 2 else { return "Not entered" }
        return boxScoreSum(numbers).map(String.init) ?? "Out of range"
    }

    private func load() {
        do {
            let records = try BoxScoreStorage.load(from: BoxScoreStorage.fileURL())
            drafts = Dictionary(uniqueKeysWithValues: records.filter { $0.gameID == gameID }.map {
                ($0.playerID, $0.values.mapValues(String.init))
            })
            loadError = nil
            loaded = true
        } catch {
            loadError = error.localizedDescription
            loaded = false
        }
    }

    private func save() {
        guard loaded, invalidEntries.isEmpty else { return }
        do {
            let url = try BoxScoreStorage.fileURL()
            let existing = try BoxScoreStorage.load(from: url)
            let records = temporaryRoster.map { player in
                let values = BoxScoreField.allCases.reduce(into: [String: Int]()) { values, field in
                    if let number = count(player, field).number { values[field.rawValue] = number }
                }
                return PlayerBoxScore(gameID: gameID, playerID: player.id, values: values)
            }
            try BoxScoreStorage.save(BoxScoreStorage.updating(existing, with: records), to: url)
            hasChanges = false
            saved = true
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}
