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
        try JSONEncoder().encode(records).write(to: url, options: [.atomic, .completeFileProtection])
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
    if counts.contains(.invalid) { return "Check unavailable: fix invalid points or made-shot inputs." }
    var contributions: [Int] = []
    for (count, weight) in zip(counts.dropFirst(), [2, 3, 1]) {
        // Only entered makes contribute to this lower bound; blanks remain missing.
        guard let number = count.number else { continue }
        let product = number.multipliedReportingOverflow(by: weight)
        guard !product.overflow else { return "Check unavailable: counts exceed the supported calculation range." }
        contributions.append(product.partialValue)
    }
    guard let implied = boxScoreSum(contributions) else {
        return "Check unavailable: counts exceed the supported calculation range."
    }
    guard let points = counts[0].number else { return "Check incomplete: points not entered." }
    if counts.dropFirst().contains(.missing) {
        if implied > points {
            return "Points disagree: entered \(points); entered made shots imply at least \(implied)."
        }
        return "Check incomplete: not all made-shot counts entered."
    }
    if points != implied {
        return "Points disagree: entered \(points); made shots imply \(implied)."
    }
    return "Points match made shots (\(implied))."
}

struct ShotCheckNotice: View {
    let message: String

    var body: some View {
        Group {
            if message.hasPrefix("Points disagree") {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.headline)
            } else {
                Text(message).foregroundStyle(TeamStatsStyle.secondaryText)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("shot-points-check")
    }
}

func boxScoreDiscrepancyDetail(_ values: [String: String]) -> String? {
    let message = boxScoreShotCheck(values)
    let prefix = "Points disagree: "
    guard message.hasPrefix(prefix) else { return nil }
    let kind = message.contains("at least") ? "Partial lower bound" : "Exact mismatch"
    return "\(kind): \(message.dropFirst(prefix.count))"
}

enum BoxScoreEntryMode: String, CaseIterable, Identifiable {
    case player = "Single player"
    case table = "Roster table"
    var id: String { rawValue }
}

struct BoxScoreEditor: View {
    let game: Game
    private var gameID: UUID { game.id }
    @Environment(\.dismiss) private var dismiss
    @State private var mode: BoxScoreEntryMode
    @State private var selectedPlayerID = temporaryRoster[0].id
    @State private var drafts: [String: [String: String]] = [:]
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var loaded = false
    @State private var hasChanges = false
    @State private var saved = false
    @State private var headerHeight: CGFloat = 0
    @State private var photoPlayer: TemporaryPlayer?
    @ScaledMetric(relativeTo: .body) private var countWidth = 132.0
    @ScaledMetric(relativeTo: .body) private var playerWidth = 190.0
    @FocusState private var focusedCount: String?
    private var inputWidth: CGFloat { min(countWidth, 280) }

    init(game: Game, initialMode: BoxScoreEntryMode) {
        self.game = game
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
            GeometryReader { geometry in
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
                        ScrollView {
                            entryHeader
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                        }
                        .frame(height: min(headerHeight, geometry.size.height * 0.45))
                        .scrollBounceBehavior(.basedOnSize)
                        if mode == .player { playerForm } else { rosterTable }
                    }
                }
            }
            .navigationTitle("Box-score draft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let player = temporaryRoster.first(where: { $0.id == selectedPlayerID }) {
                        Button("Review photo for this player", systemImage: "photo") { photoPlayer = player }
                            .accessibilityLabel("Review photo for this player")
                            .disabled(!loaded || loadError != nil)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedCount = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.disabled(hasChanges)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    if !invalidEntries.isEmpty {
                        Text("Fix invalid numbers: \(invalidEntries.joined(separator: "; ")).")
                            .foregroundStyle(TeamStatsStyle.errorText)
                            .font(.caption)
                    }
                    if let saveError { Text("Could not save draft: \(saveError)").font(.caption) }
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Text(saveStatus).font(.caption).fixedSize()
                            Spacer(minLength: 8)
                            saveButton.fixedSize()
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(saveStatus).font(.caption)
                            saveButton.frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding()
                .background(.regularMaterial)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("local-draft-save-controls")
            }
        }
        .interactiveDismissDisabled(hasChanges)
        .task { load() }
        .sheet(item: $photoPlayer) { player in
            PhotoDraftImportSheet(targetLabel: "Selected game · \(player.name) #\(player.number)",
                fields: BoxScoreField.allCases.map { PhotoDraftField(id: $0.rawValue, label: $0.label) }) { reviewed in
                drafts[player.id, default: [:]].merge(reviewed) { _, new in new }
                hasChanges = true; saved = false; saveError = nil
            }
        }
    }

    private var saveStatus: String {
        hasChanges ? "Unsaved changes" :
            saved ? "Draft saved on this device." : "Local draft"
    }

    private var saveButton: some View {
        Button(action: save) { Text("Save draft").frame(minHeight: 44) }
            .buttonStyle(.borderedProminent)
            .tint(TeamStatsStyle.filledAccent)
            .disabled(!loaded || !invalidEntries.isEmpty)
    }

    private var entryHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            let players = temporaryRoster.filter { mode == .table || $0.id == selectedPlayerID }
            let affected = players.filter { boxScoreDiscrepancyDetail(drafts[$0.id] ?? [:]) != nil }
            VStack(alignment: .leading, spacing: 4) {
                Text(game.opponent).font(.headline).fixedSize(horizontal: false, vertical: true)
                Text(game.date, format: .dateTime.month().day().year()).font(.caption)
                    .foregroundStyle(TeamStatsStyle.secondaryText)
            }
            if !affected.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Points don’t align with made baskets.", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(affected) { player in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.name).fontWeight(.semibold)
                            Text(boxScoreDiscrepancyDetail(drafts[player.id] ?? [:]) ?? "")
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .foregroundStyle(TeamStatsStyle.errorText)
                .accessibilityIdentifier("scoring-discrepancy-warning")
            }
            Picker("Entry mode", selection: $mode) {
                ForEach(BoxScoreEntryMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 4) {
                Label("Temporary roster · Local draft", systemImage: "iphone").font(.subheadline.weight(.semibold)).foregroundStyle(Color.accentColor)
                Text(scoringSummary)
                DisclosureGroup("Entry guidance") {
                    Text("Blank = not entered. Enter 0 explicitly. Nonnegative whole numbers only.")
                    Text("Advanced-sheet reconciliation unavailable; possession drafts are incomplete and unreviewed.")
                        .foregroundStyle(TeamStatsStyle.secondaryText)
                }
            }
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
    }

    private var playerForm: some View {
        Form {
            Section {
                Picker("Player", selection: $selectedPlayerID) {
                    ForEach(temporaryRoster) { Text("\($0.name) #\($0.number)").tag($0.id) }
                }
            }
            if let player = temporaryRoster.first(where: { $0.id == selectedPlayerID }) {
                Section {
                    ForEach([BoxScoreField.points, .twosMade, .twosMissed, .threesMade, .threesMissed, .freeThrowsMade, .freeThrowsMissed], id: \.self) { field in
                        LabeledContent(field.label) { entry(player, field).frame(width: inputWidth) }
                    }
                } header: {
                    Text("Scoring").foregroundStyle(Color.primary)
                }
                Section {
                    ForEach([BoxScoreField.offensiveRebounds, .defensiveRebounds, .assists, .turnovers, .steals, .blocks, .fouls, .chargesDrawn], id: \.self) { field in
                        LabeledContent(field.label) { entry(player, field).frame(width: inputWidth) }
                    }
                    LabeledContent("Total rebounds", value: rebounds(player)).monospacedDigit()
                } header: {
                    Text("Rebounds and contributions").foregroundStyle(Color.primary)
                }
                if boxScoreDiscrepancyDetail(drafts[player.id] ?? [:]) == nil {
                    Section("Points check") {
                        ShotCheckNotice(message: boxScoreShotCheck(drafts[player.id] ?? [:]))
                    }
                }
            }
        }
    }

    private var rosterTable: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 12) {
                GridRow {
                    Text("Temporary player").frame(width: playerWidth, alignment: .leading)
                    ForEach(BoxScoreField.allCases, id: \.self) { field in
                        Text(field.label).foregroundStyle(Color.accentColor).frame(width: countWidth, alignment: .leading)
                    }
                    Text("Total rebounds").frame(width: 130)
                    Text("Points check").frame(width: 270, alignment: .leading)
                }.font(.caption.bold())
                ForEach(temporaryRoster) { player in
                    GridRow {
                        VStack(alignment: .leading) {
                            Text("\(player.name) #\(player.number)")
                            Button("Review photo", systemImage: "photo") { photoPlayer = player }
                                .frame(minHeight: 44)
                                .accessibilityLabel("Review photo for \(player.name)")
                        }.frame(width: playerWidth, alignment: .leading)
                        ForEach(BoxScoreField.allCases, id: \.self) { field in
                            entry(player, field).frame(width: inputWidth)
                        }
                        Text(rebounds(player)).frame(width: 130)
                        Group {
                            if boxScoreDiscrepancyDetail(drafts[player.id] ?? [:]) == nil {
                                ShotCheckNotice(message: boxScoreShotCheck(drafts[player.id] ?? [:]))
                            }
                        }.frame(width: 270, alignment: .leading)
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
        ), prompt: Text("Not entered").foregroundColor(TeamStatsStyle.secondaryText))
        .keyboardType(.numberPad)
        .textFieldStyle(.roundedBorder)
        .monospacedDigit()
        .frame(minHeight: 44)
        .focused($focusedCount, equals: "\(player.id).\(field.rawValue)")
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
