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

struct BoxScoreSubtotal {
    let entered: Int
    let players: Int
    private let sum: Int?

    init(_ points: [Int?]) {
        let known = points.compactMap { $0 }
        entered = known.count
        players = points.count
        sum = boxScoreSum(known)
    }

    var valueText: String {
        entered == 0 ? "Not entered" : sum.map(String.init) ?? "Unavailable"
    }

    var coverageText: String {
        "Entered points subtotal · \(entered) of \(players) player totals"
    }
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

struct ScoringDiscrepancy: Identifiable {
    let id: String
    let player: String
    let detail: String
}

/// Informational draft feedback; invalid numbers and failed saves have separate errors.
struct ScoringNotice: View {
    let discrepancies: [ScoringDiscrepancy]
    let identifier: String
    @State private var showingDetails = false

    var body: some View {
        if !discrepancies.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(TeamStatsStyle.secondaryText).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Check scoring").font(.headline).accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier(identifier)
                    Text("Entered points and made baskets differ.")
                        .font(.subheadline).foregroundStyle(TeamStatsStyle.secondaryText)
                    if discrepancies.count == 1, let item = discrepancies.first {
                        detail(item)
                    } else {
                        DisclosureGroup("Scoring details · \(discrepancies.count) players", isExpanded: $showingDetails) {
                            ForEach(discrepancies) { detail($0).padding(.vertical, 4) }
                        }
                        .font(.subheadline)
                        .accessibilityIdentifier("\(identifier).details")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
    }

    private func detail(_ item: ScoringDiscrepancy) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.player).fontWeight(.semibold)
            Text(item.detail)
        }
        .font(.footnote).foregroundStyle(TeamStatsStyle.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

/// Shared by local and shared entry, using the existing blank/zero/overflow rules.
struct BoxScoreCountEntry: View {
    @Binding var text: String
    let label: String
    let identifier: String
    let focus: FocusState<String?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                counter(-1)
                TextField("Not entered", text: $text,
                          prompt: Text("Not entered").foregroundColor(TeamStatsStyle.secondaryText))
                    .keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                    .monospacedDigit().multilineTextAlignment(.center)
                    .frame(minWidth: 64, maxWidth: 140, minHeight: 44)
                    .focused(focus, equals: identifier)
                    .accessibilityLabel(label).accessibilityIdentifier(identifier)
                counter(1)
            }
            if BoxScoreCount(text) == .invalid {
                Text("Enter a nonnegative whole number within the supported range.")
                    .font(.caption).foregroundStyle(TeamStatsStyle.errorText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func counter(_ delta: Int) -> some View {
        Button {
            if let next = adjustedPossessionCount(text, by: delta) { text = next }
        } label: {
            Image(systemName: delta == 1 ? "plus" : "minus")
                .frame(minWidth: 20, minHeight: 30)
        }
        .buttonStyle(.bordered).controlSize(.regular)
        .frame(minWidth: 44, minHeight: 44)
        .disabled(adjustedPossessionCount(text, by: delta) == nil)
        .accessibilityLabel("\(delta == 1 ? "Add one" : "Subtract one"), \(label)")
        .accessibilityIdentifier("\(identifier).\(delta == 1 ? "increase" : "decrease")")
    }
}

/// One native horizontal scroller keeps columns aligned. Vertical scrolling is independent.
/// Geometry pins identity cells; it never intercepts or replaces native gestures.
struct BoxScoreTable<Header: View, Rows: View>: View {
    let width: CGFloat
    let header: (CGFloat) -> Header
    let rows: (CGFloat) -> Rows
    @State private var horizontalOffset: CGFloat = 0

    init(width: CGFloat, @ViewBuilder header: @escaping (CGFloat) -> Header,
         @ViewBuilder rows: @escaping (CGFloat) -> Rows) {
        self.width = width
        self.header = header
        self.rows = rows
    }

    var body: some View {
        ScrollView(.horizontal) {
            VStack(spacing: 0) {
                header(horizontalOffset)
                Divider()
                ScrollView(.vertical) { rows(horizontalOffset) }
            }
            .frame(width: width)
        }
        .scrollIndicators(.hidden, axes: .horizontal)
        .onScrollGeometryChange(for: CGFloat.self) { max(0, $0.contentOffset.x) } action: { _, value in
            horizontalOffset = value
        }
    }
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
    @ScaledMetric(relativeTo: .body) private var countWidth = 200.0
    @ScaledMetric(relativeTo: .body) private var playerWidth = 156.0
    @FocusState private var focusedCount: String?

    init(game: Game, initialMode: BoxScoreEntryMode, initialPlayerID: String? = nil) {
        self.game = game
        _mode = State(initialValue: initialMode)
        _selectedPlayerID = State(initialValue: initialPlayerID ?? temporaryRoster[0].id)
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
                    ScrollView {
                        entryHeader
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                    }
                    .frame(maxHeight: min(headerHeight, 200))
                    .scrollBounceBehavior(.basedOnSize)
                    .accessibilityIdentifier("box-score-entry-header")
                    Picker("Entry mode", selection: $mode) {
                        ForEach(BoxScoreEntryMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).padding(.horizontal)
                    if mode == .player { playerForm } else { rosterTable }
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
            ScoringNotice(discrepancies: affected.compactMap { player in
                guard let detail = boxScoreDiscrepancyDetail(drafts[player.id] ?? [:]) else { return nil }
                return ScoringDiscrepancy(id: player.id, player: player.name, detail: detail)
            }, identifier: "scoring-discrepancy-warning")
            VStack(alignment: .leading, spacing: 4) {
                Text(game.opponent).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(game.date, format: .dateTime.month().day().year()).font(.caption)
                    .foregroundStyle(TeamStatsStyle.secondaryText)
            }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Player", selection: $selectedPlayerID) {
                    ForEach(temporaryRoster) { Text("\($0.name) #\($0.number)").tag($0.id) }
                }
                if let player = temporaryRoster.first(where: { $0.id == selectedPlayerID }) {
                    Text("Scoring").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                    ForEach([BoxScoreField.points, .twosMade, .twosMissed, .threesMade, .threesMissed,
                             .freeThrowsMade, .freeThrowsMissed], id: \.self) { field in
                        entryRow(player, field)
                    }
                    Text("Rebounds and contributions").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                    ForEach([BoxScoreField.offensiveRebounds, .defensiveRebounds, .assists,
                             .turnovers, .steals, .blocks, .fouls, .chargesDrawn], id: \.self) { field in
                        entryRow(player, field)
                    }
                    LabeledContent("Total rebounds", value: rebounds(player)).monospacedDigit()
                    if boxScoreDiscrepancyDetail(drafts[player.id] ?? [:]) == nil {
                        ShotCheckNotice(message: boxScoreShotCheck(drafts[player.id] ?? [:]))
                    }
                }
            }.padding(16)
        }
        .frame(maxHeight: .infinity).clipped()
        .accessibilityIdentifier("box-score-player-form")
    }

    private func entryRow(_ player: TemporaryPlayer, _ field: BoxScoreField) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(field.label).font(.headline)
            entry(player, field)
            Divider()
        }
    }

    private var rosterTable: some View {
        GeometryReader { geometry in
            let identityWidth = min(playerWidth, geometry.size.width * 0.4)
            VStack(alignment: .leading, spacing: 8) {
                Text("Swipe for more stats.")
                    .font(.footnote).foregroundStyle(TeamStatsStyle.secondaryText).padding(.horizontal)
                BoxScoreTable(width: identityWidth + countWidth * CGFloat(BoxScoreField.allCases.count) + 400) { offset in
                    HStack(spacing: 0) {
                        Text("Player").font(.caption.bold())
                            .frame(width: identityWidth, alignment: .leading)
                            .padding(.vertical, 8).background(.background).offset(x: offset).zIndex(1)
                        ForEach(BoxScoreField.allCases, id: \.self) { field in
                            Text(field.label).font(.caption.bold())
                                .frame(width: countWidth, alignment: .leading)
                        }
                        Text("Total rebounds").frame(width: 130)
                        Text("Points check").frame(width: 270, alignment: .leading)
                    }.background(Color(uiColor: .secondarySystemBackground))
                } rows: { offset in
                    VStack(spacing: 0) {
                        ForEach(temporaryRoster) { player in
                            HStack(alignment: .top, spacing: 0) {
                                VStack(alignment: .leading, spacing: 8) {
                                Text("\(player.name) #\(player.number)").font(.headline)
                                    .fixedSize(horizontal: false, vertical: true)
                                    Button("Review photo", systemImage: "photo") { photoPlayer = player }
                                        .frame(minHeight: 44).accessibilityLabel("Review photo for \(player.name)")
                                }
                                .frame(width: identityWidth, alignment: .leading).padding(.vertical, 12)
                                .background(.background).offset(x: offset).zIndex(1)
                                ForEach(BoxScoreField.allCases, id: \.self) { field in
                                    entry(player, field).padding(.horizontal, 8).frame(width: countWidth)
                                }
                                Text(rebounds(player)).frame(width: 130)
                                VStack(alignment: .leading) {
                                    if boxScoreDiscrepancyDetail(drafts[player.id] ?? [:]) == nil {
                                        ShotCheckNotice(message: boxScoreShotCheck(drafts[player.id] ?? [:]))
                                    }
                                }.frame(width: 270, alignment: .leading)
                            }.padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func entry(_ player: TemporaryPlayer, _ field: BoxScoreField) -> some View {
        BoxScoreCountEntry(text: Binding(
            get: { drafts[player.id]?[field.rawValue] ?? "" },
            set: {
                guard (drafts[player.id]?[field.rawValue] ?? "") != $0 else { return }
                drafts[player.id, default: [:]][field.rawValue] = $0
                hasChanges = true; saved = false; saveError = nil
            }), label: "\(player.name), \(field.label)",
            identifier: "\(player.id).\(field.rawValue)", focus: $focusedCount)
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

/// Saved values only. Entry remains an explicit action with its own unsaved buffer.
struct SavedBoxScoreTable: View {
    let records: [PlayerBoxScore]
    let paintTouches: [PlayerPaintTouchRecord]
    let paintError: String?
    @Binding var expanded: Set<String>
    let edit: (TemporaryPlayer) -> Void
    @ScaledMetric(relativeTo: .body) private var columnWidth = 76.0
    @ScaledMetric(relativeTo: .body) private var playerWidth = 164.0

    var body: some View {
        GeometryReader { geometry in
            let identityWidth = min(playerWidth, geometry.size.width * 0.4)
            VStack(alignment: .leading, spacing: 8) {
                Text("Box score").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text("Saved values · Temporary roster").font(.subheadline)
                Text("Swipe across for more statistics. Not entered is shown as —; zero stays 0.")
                    .font(.footnote).foregroundStyle(TeamStatsStyle.secondaryText)
                if records.isEmpty { Text("No box-score records saved for this game.").font(.subheadline) }
                BoxScoreTable(width: identityWidth + columnWidth * CGFloat(BoxScoreField.allCases.count + 1)) { offset in
                    HStack(spacing: 0) {
                        Text("Player").font(.caption.bold()).frame(width: identityWidth, alignment: .leading)
                            .padding(.vertical, 12).background(.background).offset(x: offset).zIndex(1)
                        ForEach(BoxScoreField.allCases, id: \.self) { field in
                            Text(abbreviation(field)).font(.caption.bold()).frame(width: columnWidth)
                                .accessibilityLabel(field.label)
                            if field == .points { Text("REB").font(.caption.bold()).frame(width: columnWidth).accessibilityLabel("Total rebounds") }
                        }
                    }.background(Color(uiColor: .secondarySystemBackground))
                } rows: { offset in
                    VStack(spacing: 0) {
                        ForEach(temporaryRoster) { player in
                            let values = records.first { $0.playerID == player.id }?.values ?? [:]
                            HStack(spacing: 0) {
                                Button {
                                    if expanded.contains(player.id) { expanded.remove(player.id) }
                                    else { expanded.insert(player.id) }
                                } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: expanded.contains(player.id) ? "chevron.down" : "chevron.right")
                                            .font(.caption).accessibilityHidden(true)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(player.name).font(.headline)
                                                .fixedSize(horizontal: false, vertical: true)
                                            Text("#\(player.number)").font(.subheadline)
                                        }
                                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(player.name), number \(player.number), read-only details")
                                .accessibilityValue(expanded.contains(player.id) ? "Expanded" : "Collapsed")
                                .accessibilityIdentifier("box-score.expand.\(player.id)")
                                .frame(width: identityWidth).padding(.vertical, 8)
                                .background(.background).offset(x: offset).zIndex(1)
                                ForEach(BoxScoreField.allCases, id: \.self) { field in
                                    Text(values[field.rawValue].map(String.init) ?? "—")
                                        .monospacedDigit().frame(width: columnWidth)
                                        .accessibilityLabel("\(player.name), \(field.label), \(summaryCount(values[field.rawValue]))")
                                    if field == .points {
                                        Text(rebounds(values)).monospacedDigit().frame(width: columnWidth)
                                            .accessibilityLabel("\(player.name), total rebounds, \(summaryRebounds(values))")
                                    }
                                }
                            }
                            Divider()
                            if expanded.contains(player.id) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("\(player.name) · Read-only details").font(.headline)
                                    ShotCheckNotice(message: summaryShotCheck(values))
                                    Text("Total rebounds: \(summaryRebounds(values))")
                                    if let paintError {
                                        Text("Could not load player paint touches: \(paintError). Retry from Game details.")
                                            .foregroundStyle(TeamStatsStyle.errorText)
                                    } else {
                                        Text("Game-total paint touches: \(summaryCount(paintTouches.first { $0.playerID == player.id }?.total))")
                                        Text("Independently recorded; not inferred from possessions.")
                                            .font(.footnote).foregroundStyle(TeamStatsStyle.secondaryText)
                                    }
                                    Button("Edit player stats") { edit(player) }
                                        .buttonStyle(.bordered).frame(minHeight: 44)
                                        .accessibilityLabel("Edit player stats for \(player.name)")
                                }
                                .padding(16).frame(width: max(0, min(geometry.size.width, 640)), alignment: .leading)
                                .background(.background).offset(x: offset)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Divider()
                            }
                        }
                    }
                }
                DisclosureGroup("Stat abbreviations") {
                    Text(BoxScoreField.allCases.map { "\(abbreviation($0)): \($0.label)" }.joined(separator: "; "))
                    Text("REB: offensive plus defensive rebounds; both inputs are required.")
                }.font(.footnote)
            }.padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    private func rebounds(_ values: [String: Int]) -> String {
        guard let offensive = values["offensiveRebounds"], let defensive = values["defensiveRebounds"] else { return "—" }
        return boxScoreSum([offensive, defensive]).map(String.init) ?? "Unavailable"
    }

    private func abbreviation(_ field: BoxScoreField) -> String {
        switch field {
        case .points: "PTS"
        case .offensiveRebounds: "ORB"
        case .defensiveRebounds: "DRB"
        case .assists: "AST"
        case .turnovers: "TO"
        case .steals: "STL"
        case .blocks: "BLK"
        case .fouls: "PF"
        case .chargesDrawn: "CHG"
        case .twosMade: "2PM"
        case .twosMissed: "2P miss"
        case .threesMade: "3PM"
        case .threesMissed: "3P miss"
        case .freeThrowsMade: "FTM"
        case .freeThrowsMissed: "FT miss"
        }
    }
}
