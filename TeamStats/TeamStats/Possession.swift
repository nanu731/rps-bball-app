import Foundation
import SwiftUI

enum PossessionTeam: String, Codable, CaseIterable {
    case ours, opponent
    var label: String { self == .ours ? "Our team" : "Opponent" }
}

enum PossessionField: String, CaseIterable {
    case paintTouches, offensiveRebounds, twosMade, twosMissed
    case threesMade, threesMissed, freeThrowsMade, freeThrowsMissed

    var label: String {
        switch self {
        case .paintTouches: "Paint touches"
        case .offensiveRebounds: "Offensive rebounds"
        case .twosMade: "Twos made"
        case .twosMissed: "Twos missed"
        case .threesMade: "Threes made"
        case .threesMissed: "Threes missed"
        case .freeThrowsMade: "Free throws made"
        case .freeThrowsMissed: "Free throws missed"
        }
    }
}

struct PossessionRecord: Codable, Identifiable {
    let id: UUID
    let gameID: UUID
    let team: PossessionTeam
    let number: Int
    var values: [String: Int]
    var turnover: Bool?
}

// Text stays in the draft until validation; missing counts and unanswered turnover stay missing.
struct PossessionDraft: Identifiable {
    let id: UUID
    let team: PossessionTeam
    let number: Int
    var values: [String: String] = [:]
    var turnover: Bool?

    var invalidField: PossessionField? {
        PossessionField.allCases.first { BoxScoreCount(values[$0.rawValue] ?? "") == .invalid }
    }

    func record(gameID: UUID) -> PossessionRecord {
        PossessionRecord(id: id, gameID: gameID, team: team, number: number,
                         values: values.compactMapValues { BoxScoreCount($0).number }, turnover: turnover)
    }
}

enum PossessionStorage {
    static func fileURL() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("possessions.json")
    }

    static func load(from url: URL) throws -> [PossessionRecord] {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return [] }
        let records = try JSONDecoder().decode([PossessionRecord].self, from: data)
        try validate(records)
        return records
    }

    static func save(_ records: [PossessionRecord], to url: URL) throws {
        try validate(records)
        try JSONEncoder().encode(records).write(to: url, options: .atomic)
    }

    static func updating(_ records: [PossessionRecord], with drafts: [PossessionRecord]) -> [PossessionRecord] {
        let ids = Set(drafts.map(\.id))
        return records.filter { !ids.contains($0.id) } + drafts
    }

    private static func validate(_ records: [PossessionRecord]) throws {
        let fields = Set(PossessionField.allCases.map(\.rawValue))
        let positions = records.map { "\($0.gameID):\($0.team.rawValue):\($0.number)" }
        guard Set(records.map(\.id)).count == records.count,
              Set(positions).count == records.count,
              records.allSatisfy({ $0.number > 0 && $0.values.allSatisfy {
                  fields.contains($0.key) && $0.value >= 0
              } }) else { throw CocoaError(.coderReadCorrupt) }
    }
}

struct PossessionEditor: View {
    let game: Game
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [PossessionDraft] = []
    @State private var loaded = false
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var hasChanges = false
    @State private var saved = false
    @FocusState private var focusedField: String?

    private func teamDrafts(_ team: PossessionTeam) -> [PossessionDraft] {
        drafts.filter { $0.team == team }.sorted { $0.number < $1.number }
    }

    // Only added records count; paired placeholders never enter this array.
    private var rowNumbers: [Int] { Array(Set(drafts.map(\.number))).sorted() }
    private var invalidMessage: String? {
        for draft in drafts {
            if let field = draft.invalidField {
                return "\(draft.team.label) possession \(draft.number): \(field.label) must be a nonnegative whole number within the supported range."
            }
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if let loadError {
                    ContentUnavailableView {
                        Label("Could not load possessions", systemImage: "exclamationmark.triangle")
                    } description: { Text(loadError) } actions: { Button("Retry", action: load) }
                } else if loaded {
                    GeometryReader { geometry in
                        ScrollViewReader { proxy in
                            ScrollView([.horizontal, .vertical]) {
                                LazyVStack(alignment: .leading, spacing: 16) {
                                    guidance.frame(width: max(1, geometry.size.width - 32))
                                    HStack(alignment: .top, spacing: 16) {
                                        teamHeader(.ours)
                                        teamHeader(.opponent)
                                    }
                                    if drafts.isEmpty {
                                        Text("No possession records added. Add the next possession for either team.")
                                            .foregroundStyle(.secondary)
                                            .frame(width: max(1, geometry.size.width - 32), alignment: .leading)
                                    }
                                    ForEach(rowNumbers, id: \.self) { number in
                                        HStack(alignment: .top, spacing: 16) {
                                            possessionCell(.ours, number: number)
                                            possessionCell(.opponent, number: number)
                                        }
                                        Divider()
                                    }
                                }
                                .padding()
                            }
                            .defaultScrollAnchor(.topLeading)
                            .scrollDismissesKeyboard(.interactively)
                            .onChange(of: focusedField) { _, field in
                                if let field { proxy.scrollTo(field, anchor: .center) }
                            }
                            .onChange(of: geometry.size.height) { _, _ in
                                if let focusedField { proxy.scrollTo(focusedField, anchor: .center) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Possession draft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.disabled(hasChanges)
                }
            }
            .safeAreaInset(edge: .bottom) { saveBar }
        }
        .interactiveDismissDisabled(hasChanges)
        .task { load() }
    }

    private var guidance: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Incomplete, unreviewed local draft").font(.headline)
            Text("After-game entry only. Row n pairs each team's independent nth possession, not chronological alignment.")
            Text("From legal team possession until the opponent legally possesses the ball. Free throws and offensive rebounds stay within it. Period-ending possessions with actions count; no-action holds until the buzzer do not.")
            Text("Paint touch: intentionally establish two feet in the paint with the ball. Blank counts and unanswered turnovers remain unentered; enter 0 explicitly.")
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func teamHeader(_ team: PossessionTeam) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(team == .ours ? "Our team (\(game.venue.rawValue))" :
                    "Opponent: \(game.opponent) (\(game.venue == .home ? "Away" : "Home"))")
                .font(.headline)
            Text("\(teamDrafts(team).count) draft records, incomplete").font(.caption)
            Button("Add next: \(team.label)") { add(team) }
                .buttonStyle(.bordered)
                .disabled(!loaded)
        }
        .frame(width: 280, alignment: .leading)
    }

    @ViewBuilder private func possessionCell(_ team: PossessionTeam, number: Int) -> some View {
        if let index = drafts.firstIndex(where: { $0.team == team && $0.number == number }) {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(team.label) possession \(number)").font(.headline)
                ForEach(PossessionField.allCases, id: \.self) { field in
                    HStack {
                        Text(field.label)
                        Spacer()
                        TextField("Unentered", text: Binding(
                            get: { drafts[index].values[field.rawValue] ?? "" },
                            set: { text in
                                guard (drafts[index].values[field.rawValue] ?? "") != text else { return }
                                drafts[index].values[field.rawValue] = text
                                changed()
                            }
                        ))
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .focused($focusedField, equals: "\(drafts[index].id).\(field.rawValue)")
                        .id("\(drafts[index].id).\(field.rawValue)")
                        .accessibilityLabel("\(team.label) possession \(number), \(field.label)")
                        .accessibilityIdentifier("\(team.rawValue).\(number).\(field.rawValue)")
                    }
                }
                LabeledContent("Turnover") {
                    Picker("Turnover", selection: Binding<Bool?>(
                        get: { drafts[index].turnover },
                        set: { answer in
                            guard drafts[index].turnover != answer else { return }
                            drafts[index].turnover = answer
                            changed()
                        }
                    )) {
                        Text("Unanswered").tag(nil as Bool?)
                        Text("Yes").tag(true as Bool?)
                        Text("No").tag(false as Bool?)
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("\(team.label) possession \(number), Turnover")
                }
                if let field = drafts[index].invalidField {
                    Text("Invalid \(field.label.lowercased()).").font(.caption).foregroundStyle(.red)
                }
            }
            .frame(width: 280, alignment: .leading)
        } else {
            Text("\(team.label) possession \(number) not added.")
                .foregroundStyle(.secondary)
                .frame(width: 280, alignment: .leading)
        }
    }

    private var saveBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let invalidMessage { Text(invalidMessage).font(.caption).foregroundStyle(.red) }
            if let saveError { Text("Could not save draft: \(saveError)").font(.caption) }
            if focusedField != nil {
                HStack {
                    Spacer()
                    Button("Hide keyboard") { focusedField = nil }
                }
            }
            HStack {
                Text(hasChanges ? "Unsaved changes. Save before closing." :
                        (saved ? "Draft saved on this device; unreviewed." : "Incomplete drafts can be saved."))
                    .font(.caption)
                Spacer()
                Button("Save draft", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(!loaded || invalidMessage != nil)
            }
        }
        .padding()
        .background(.regularMaterial)
    }

    private func changed() {
        hasChanges = true
        saved = false
        saveError = nil
    }

    private func add(_ team: PossessionTeam) {
        let next = (teamDrafts(team).last?.number ?? 0).addingReportingOverflow(1)
        guard !next.overflow else {
            saveError = "Possession numbering exceeds the supported range."
            return
        }
        drafts.append(PossessionDraft(id: UUID(), team: team, number: next.partialValue))
        changed()
    }

    private func load() {
        do {
            drafts = try PossessionStorage.load(from: PossessionStorage.fileURL())
                .filter { $0.gameID == game.id }.map {
                    PossessionDraft(id: $0.id, team: $0.team, number: $0.number,
                                    values: $0.values.mapValues(String.init), turnover: $0.turnover)
                }
            loaded = true
            loadError = nil
        } catch {
            loaded = false
            loadError = error.localizedDescription
        }
    }

    private func save() {
        guard loaded, invalidMessage == nil else { return }
        do {
            let url = try PossessionStorage.fileURL()
            let existing = try PossessionStorage.load(from: url)
            try PossessionStorage.save(PossessionStorage.updating(existing,
                with: drafts.map { $0.record(gameID: game.id) }), to: url)
            hasChanges = false
            saved = true
            saveError = nil
        } catch { saveError = error.localizedDescription }
    }
}
