import Foundation
import SwiftUI

/// Typed text stays in these buffers until an explicit server save succeeds.
/// Both box-score modes bind to the same player values.
struct ConnectedStatEntryView: View {
    let model: ConnectedStatistics
    let game: ConnectedGame
    let initialDataset: ConnectedDatasetType
    @State private var mode: BoxScoreEntryMode = .player
    @State private var selectedPlayerID = ""
    @State private var baseVersions: [ConnectedDatasetType: ConnectedVersion] = [:]
    @State private var coveredLabels: [ConnectedDatasetType: [ConnectedRosterLabel]] = [:]
    @State private var boxes: [String: [String: String]] = [:]
    @State private var paint: [String: String] = [:]
    @State private var possessions: [PossessionDraft] = []
    @State private var changed: Set<ConnectedDatasetType> = []
    @State private var loaded = false
    @State private var bufferIssue: String?
    @State private var bufferIssueKind: ConnectedDatasetType?
    @State private var preparationIssue: String?
    @State private var headerHeight: CGFloat = 0
    @State private var completionKind: ConnectedDatasetType?
    @State private var reloadCandidate: ConnectedDatasetType?
    @FocusState private var focused: String?
    @ScaledMetric(relativeTo: .body) private var possessionColumnWidth = 340.0
    @ScaledMetric(relativeTo: .body) private var boxColumnWidth = 110.0

    private var isPaired: Bool { initialDataset == .ourPossessions || initialDataset == .opponentPossessions }
    private var kinds: [ConnectedDatasetType] { isPaired ? [.ourPossessions, .opponentPossessions] : [initialDataset] }
    private var playerLabels: [ConnectedRosterLabel] { coveredLabels[initialDataset] ?? [] }
    private var unavailable: Bool { !model.didLoadGame || model.selectedGame?.id != game.id }
    private var invalidMessages: [String] {
        if initialDataset == .boxScores {
            return playerLabels.flatMap { player in
                BoxScoreField.allCases.compactMap { field in
                    BoxScoreCount(boxes[player.id.uuidString]?[field.rawValue] ?? "") == .invalid ? "\(player.name): \(field.label)" : nil
                }
            }
        }
        if initialDataset == .playerPaintTouches {
            return playerLabels.compactMap { player in BoxScoreCount(paint[player.id.uuidString] ?? "") == .invalid ? "\(player.name): paint-touch total" : nil }
        }
        return possessions.compactMap { row in row.invalidField.map { "\(row.team.label) record \(row.number): \($0.label)" } }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 8) {
                ScrollView {
                    entryHeader
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                }
                .frame(height: min(headerHeight, geometry.size.height * 0.45))
                .scrollBounceBehavior(.basedOnSize)
                if unavailable || !loaded {
                    ContentUnavailableView("Draft unavailable", systemImage: "exclamationmark.triangle", description: Text("Reload the shared game before opening an entry draft."))
                } else if let bufferIssue {
                    ContentUnavailableView {
                        Label("Could not read saved draft", systemImage: "exclamationmark.triangle")
                    } description: { Text(bufferIssue) } actions: {
                        Button("Reload / Retry saved draft") {
                            Task {
                                await model.reload()
                                if model.didLoadGame, let kind = bufferIssueKind {
                                    if changed.contains(kind) { reloadCandidate = kind } else { synchronize(kind) }
                                }
                            }
                        }.disabled(model.isBusy)
                    }
                } else if isPaired { pairedTable }
                else if initialDataset == .boxScores { if mode == .player { boxForm } else { boxTable } }
                else { paintForm }
            }
        }
        .navigationTitle(initialDataset == .boxScores ? "Box-score entry" : isPaired ? "Possession sheets" : "Player paint totals")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(!changed.isEmpty)
        .safeAreaInset(edge: .bottom) { saveBar }
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = nil } } }
        .task { if !loaded { hydrateInitial() } }
        .sheet(item: $completionKind) { kind in
            if let version = baseVersions[kind] {
                ConnectedCompletionSheet(model: model, version: version,
                    labels: coveredLabels[kind] ?? [],
                    hasNumericBlanks: numericBlanks(kind)) {
                        synchronize(kind)
                    }
            }
        }
        .confirmationDialog("Load the current saved version?", isPresented: Binding(get: { reloadCandidate != nil }, set: { if !$0 { reloadCandidate = nil } }), titleVisibility: .visible) {
            if let kind = reloadCandidate {
                Button("Replace this screen's unsaved values") {
                    reloadCandidate = nil
                    synchronize(kind)
                }
            }
            Button("Keep unsaved values", role: .cancel) { reloadCandidate = nil }
        } message: { Text("This replaces only the entry buffer with the currently loaded server version. Save or copy any values you need before continuing.") }
    }

    private var entryHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            if initialDataset == .boxScores { discrepancyBanner }
            if initialDataset == .boxScores {
                Picker("Entry mode", selection: $mode) {
                    ForEach(BoxScoreEntryMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
            }
            if model.isBusy { ProgressView("Contacting statistics server…") }
            if let issue = model.issue {
                Label(issue.localizedDescription, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                Button("Reload server state") { Task { await model.reload() } }.disabled(model.isBusy)
                Text("Reload preserves the values on this screen. If the saved revision changed, explicitly load its values before editing again.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let confirmation = model.confirmation { Label(confirmation, systemImage: "checkmark.circle") }
            Text(game.opponent).font(.headline)
            Text("Blank = not entered. Enter 0 explicitly. Use nonnegative whole numbers within the supported range.")
                .font(.footnote).foregroundStyle(.secondary)
            if isPaired {
                Text("Each team's numbering is independent. These paired rows do not mean simultaneous or chronological possessions.")
                Text("A possession runs from legal team possession until the opponent legally possesses the ball. Free throws, offensive rebounds and fouls remain within it. Period-ending actions count; a no-action hold does not.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else if initialDataset == .playerPaintTouches {
                Text("A paint touch is when a player intentionally establishes two feet in the paint with the ball.")
                Text("Enter independently collected game totals. No player attribution or repeated-touch interpretation is inferred from possessions.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("Draft discrepancies remain saveable. Completion requires valid entered values and no proven scoring contradiction. Optional missing values stay missing.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(kinds, id: \.self) { kind in datasetControls(kind) }
        }
        .padding(.horizontal).padding(.vertical, 8)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var discrepancyBanner: some View {
        let scoped = playerLabels.filter { mode == .table || $0.id.uuidString == selectedPlayerID }
        let affected = scoped.filter { boxScoreDiscrepancyDetail(boxes[$0.id.uuidString] ?? [:]) != nil }
        if !affected.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Points don’t align with made baskets.", systemImage: "exclamationmark.triangle")
                    .font(.headline).accessibilityAddTraits(.isHeader)
                ForEach(affected) { player in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.name).fontWeight(.semibold)
                        Text(boxScoreDiscrepancyDetail(boxes[player.id.uuidString] ?? [:]) ?? "")
                    }.accessibilityElement(children: .combine)
                }
            }.foregroundStyle(.red).accessibilityIdentifier("connected.scoring-discrepancy-warning")
        }
    }

    private func hasInvalidInputs(_ kind: ConnectedDatasetType) -> Bool {
        if isPaired {
            return possessions.contains { datasetKind($0.team) == kind && $0.invalidField != nil }
        }
        return !invalidMessages.isEmpty
    }

    @ViewBuilder private func datasetControls(_ kind: ConnectedDatasetType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kind.label).font(.headline)
            if let version = baseVersions[kind] {
                Text("\(version.status.rawValue.capitalized) · Server revision \(version.revision)")
                    .font(.caption).foregroundStyle(.secondary)
                if changed.contains(kind) { Text("Unsaved changes").font(.caption) }
                if stale(kind) {
                    Label("The server has a different saved revision. Review its saved values before continuing.", systemImage: "exclamationmark.triangle")
                    Button("Load current saved values") {
                        if changed.contains(kind) { reloadCandidate = kind } else { synchronize(kind) }
                    }.disabled(model.isBusy)
                } else if version.status == .draft {
                    Button("Complete \(kind.label.lowercased())") { focused = nil; completionKind = kind }
                        .disabled(changed.contains(kind) || model.isBusy || model.reloadRequired || hasInvalidInputs(kind) || !hasRecords(kind))
                    if changed.contains(kind) { Text("Save this dataset before completing it.").font(.footnote).foregroundStyle(.secondary) }
                } else {
                    Text("Completed data is read-only until an edit request is approved.").font(.footnote).foregroundStyle(.secondary)
                    NavigationLink("View status / Request edit") { ConnectedVersionDetailView(model: model, version: version) }
                }
            } else if let locked = lockedVersion(kind) {
                Text("\(locked.status.rawValue.capitalized) · Read-only saved version")
                NavigationLink("View dataset / Request edit") { ConnectedVersionDetailView(model: model, version: locked) }
                Text("Reload after an edit request is approved to open its new working revision.").font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("No working draft opened.").foregroundStyle(.secondary)
                Button("Start \(kind.label.lowercased()) draft") {
                    Task {
                        if let version = await model.openDraft(kind) { hydrate(version, newDraft: true) }
                    }
                }.disabled(model.isBusy || model.reloadRequired || unavailable || (!isPaired && activeLabels.isEmpty))
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var saveBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let preparationIssue { Label(preparationIssue, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red) }
            if !invalidMessages.isEmpty {
                Label("Fix invalid numbers: \(invalidMessages.joined(separator: "; ")).", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).font(.caption)
            }
            HStack(alignment: .center) {
                Text(changed.isEmpty ? "Only a server confirmation establishes a saved draft." : "Save before leaving. Unsaved changes remain on this screen.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(isPaired ? "Save both changed sheets" : "Save draft") {
                    focused = nil
                    Task { await save() }
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
                .disabled(model.isBusy || model.reloadRequired || unavailable || !loaded || bufferIssue != nil || changed.isEmpty || !invalidMessages.isEmpty || kinds.contains { stale($0) })
            }
        }.padding().background(.regularMaterial)
    }

    private var boxForm: some View {
        Form {
            if playerLabels.isEmpty { rosterEmpty }
            else if baseVersions[.boxScores] == nil { Section { Text("Start a draft to enter player box scores.") } }
            else {
                Picker("Player", selection: $selectedPlayerID) {
                    ForEach(playerLabels) { player in Text("\(player.name) · #\(player.jerseyNumber)").tag(player.id.uuidString) }
                }
                if let player = playerLabels.first(where: { $0.id.uuidString == selectedPlayerID }) {
                    Section("Player box score") {
                        ForEach(BoxScoreField.allCases, id: \.self) { field in
                            LabeledContent(field.label) { boxEntry(player, field).frame(minWidth: 95) }
                        }
                        LabeledContent("Total rebounds", value: bufferRebounds(boxes[player.id.uuidString] ?? [:]))
                    }
                    if boxScoreDiscrepancyDetail(boxes[player.id.uuidString] ?? [:]) == nil {
                        Section("Points check") { ShotCheckNotice(message: boxScoreShotCheck(boxes[player.id.uuidString] ?? [:])) }
                    }
                }
                coveredRosterSection
            }
        }
    }

    private var boxTable: some View {
        ScrollView([.horizontal, .vertical]) {
            if playerLabels.isEmpty { rosterEmpty.padding() }
            else if baseVersions[.boxScores] == nil { Text("Start a draft to enter player box scores.").padding() }
            else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 16) {
                    GridRow {
                        Text("Actual player").frame(minWidth: 170, alignment: .leading)
                        ForEach(BoxScoreField.allCases, id: \.self) { field in Text(field.label).frame(minWidth: boxColumnWidth) }
                        Text("Total rebounds").frame(minWidth: 150)
                        Text("Points check").frame(minWidth: 280, alignment: .leading)
                    }.font(.caption.bold())
                    ForEach(playerLabels) { player in
                        GridRow {
                            Text("\(player.name) · #\(player.jerseyNumber)").frame(minWidth: 170, alignment: .leading)
                            ForEach(BoxScoreField.allCases, id: \.self) { field in boxEntry(player, field).frame(width: boxColumnWidth) }
                            Text(bufferRebounds(boxes[player.id.uuidString] ?? [:])).frame(width: 150)
                            Group {
                                if boxScoreDiscrepancyDetail(boxes[player.id.uuidString] ?? [:]) == nil {
                                    ShotCheckNotice(message: boxScoreShotCheck(boxes[player.id.uuidString] ?? [:]))
                                }
                            }.frame(width: 280, alignment: .leading)
                        }
                    }
                }.padding()
            }
        }
    }

    private func boxEntry(_ player: ConnectedRosterLabel, _ field: BoxScoreField) -> some View {
        let key = player.id.uuidString
        return TextField("Not entered", text: Binding(get: { boxes[key]?[field.rawValue] ?? "" }, set: {
            boxes[key, default: [:]][field.rawValue] = $0
            changed.insert(.boxScores)
        }))
        .keyboardType(.numberPad).textFieldStyle(.roundedBorder)
        .focused($focused, equals: "box:\(key):\(field.rawValue)")
        .accessibilityLabel("\(player.name), \(field.label)")
        .frame(minHeight: 44)
        .disabled(!editable(.boxScores))
    }

    private var paintForm: some View {
        Form {
            if playerLabels.isEmpty { rosterEmpty }
            else if baseVersions[.playerPaintTouches] == nil { Section { Text("Start a draft to enter independently collected player totals.") } }
            else {
                ForEach(playerLabels) { player in
                    Section("\(player.name) · #\(player.jerseyNumber)") {
                        countControls("Game-total paint touches", text: Binding(get: { paint[player.id.uuidString] ?? "" }, set: {
                            paint[player.id.uuidString] = $0
                            changed.insert(.playerPaintTouches)
                        }), focusKey: "paint:\(player.id)", editable: editable(.playerPaintTouches), accessibility: "\(player.name), game-total paint touches")
                    }
                }
                coveredRosterSection
            }
        }
    }

    @ViewBuilder private var rosterEmpty: some View {
        Section { Text("TODO_TEAM_ROSTER — no actual covered roster available. An authorized roster administrator must add actual players before player datasets can be completed.").foregroundStyle(.secondary) }
    }

    private var coveredRosterSection: some View {
        Section("Covered actual roster") {
            ForEach(playerLabels) { player in
                Text("\(player.name) · #\(player.jerseyNumber) · Roster version \(player.version)")
            }
            Text("Completion confirms this covered roster. Optional box-score and player-total blanks stay missing.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var pairedTable: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    possessionHeader(.ours)
                    possessionHeader(.opponent)
                }
                let numbers = Array(Set(possessions.map(\.number))).sorted()
                if numbers.isEmpty { Text("No possession records added. Each side can add its next record independently.").frame(width: possessionColumnWidth * 2 + 16, alignment: .leading) }
                ForEach(numbers, id: \.self) { number in
                    HStack(alignment: .top, spacing: 16) {
                        possessionCell(.ours, number: number)
                        possessionCell(.opponent, number: number)
                    }
                }
            }.padding()
        }.accessibilityIdentifier("connected.paired-possession-table")
    }

    private func possessionHeader(_ team: PossessionTeam) -> some View {
        let kind = datasetKind(team)
        let count = possessions.filter { $0.team == team }.count
        return VStack(alignment: .leading, spacing: 8) {
            Text(team.label).font(.headline)
            Text(team == .ours ? connectedVenue(game.homeAway) : "\(game.opponent) · \(game.homeAway == "home" ? "Away" : "Home")")
            Text("Records entered: \(count)").monospacedDigit()
            Text(baseVersions[kind]?.status == .draft ? "Incomplete and unreviewed" : "This sheet retains its own server status")
                .font(.caption).foregroundStyle(.secondary)
            Button("Add next \(team.label.lowercased()) record", systemImage: "plus") {
                guard editable(kind), count < Int.max else { return }
                possessions.append(PossessionDraft(id: UUID(), team: team, number: count + 1, turnover: false))
                changed.insert(kind)
            }.frame(minHeight: 44).disabled(!editable(kind) || count == Int.max)
        }.frame(width: possessionColumnWidth, alignment: .leading)
    }

    @ViewBuilder private func possessionCell(_ team: PossessionTeam, number: Int) -> some View {
        if let index = possessions.firstIndex(where: { $0.team == team && $0.number == number }) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(team.label) · Record \(number)").font(.headline)
                ForEach(PossessionField.allCases, id: \.self) { field in
                    countControls(field.label, text: Binding(get: { possessions[index].values[field.rawValue] ?? "" }, set: {
                        possessions[index].values[field.rawValue] = $0
                        changed.insert(datasetKind(team))
                    }), focusKey: "pos:\(possessions[index].id):\(field.rawValue)", editable: editable(datasetKind(team)), accessibility: "\(team.label), record \(number), \(field.label)")
                }
                Picker("Turnover", selection: Binding(get: { turnoverSelection(possessions[index].turnover) }, set: {
                    possessions[index].turnover = $0 == "unanswered" ? nil : $0 == "yes"
                    changed.insert(datasetKind(team))
                })) {
                    Text("Unanswered").tag("unanswered")
                    Text("Yes").tag("yes")
                    Text("No").tag("no")
                }.pickerStyle(.segmented).disabled(!editable(datasetKind(team)))
                .accessibilityLabel("\(team.label), record \(number), turnover")
                if possessions[index].turnover == nil { Text("Answer Yes or No before completing this sheet.").font(.caption).foregroundStyle(.secondary) }
            }.frame(width: possessionColumnWidth, alignment: .leading)
            .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(team.label) · No record \(number)")
                Text("No opposite-side placeholder is saved. Use Add next record for this team.").font(.footnote).foregroundStyle(.secondary)
            }.frame(width: possessionColumnWidth, alignment: .leading)
        }
    }

    private func countControls(_ label: String, text: Binding<String>, focusKey: String, editable: Bool, accessibility: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline)
            HStack(spacing: 8) {
                Button {
                    if let next = adjustedPossessionCount(text.wrappedValue, by: -1) { text.wrappedValue = next }
                } label: { Image(systemName: "minus").frame(minWidth: 44, minHeight: 44) }
                .buttonStyle(.bordered).disabled(!editable || adjustedPossessionCount(text.wrappedValue, by: -1) == nil)
                .accessibilityLabel("Decrease \(accessibility)")
                TextField("Not entered", text: text).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                    .focused($focused, equals: focusKey).frame(minHeight: 44)
                    .accessibilityLabel(accessibility).disabled(!editable)
                Button {
                    if let next = adjustedPossessionCount(text.wrappedValue, by: 1) { text.wrappedValue = next }
                } label: { Image(systemName: "plus").frame(minWidth: 44, minHeight: 44) }
                .buttonStyle(.bordered).disabled(!editable || adjustedPossessionCount(text.wrappedValue, by: 1) == nil)
                .accessibilityLabel("Increase \(accessibility)")
            }
            if BoxScoreCount(text.wrappedValue) == .invalid {
                Label("Invalid whole number", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var activeLabels: [ConnectedRosterLabel] {
        model.roster.filter { $0.archivedAt == nil }.map { ConnectedRosterLabel(id: $0.id, teamID: $0.teamID, name: $0.displayName, jerseyNumber: $0.jerseyNumber, version: $0.version) }
    }
    private func lockedVersion(_ kind: ConnectedDatasetType) -> ConnectedVersion? {
        model.ownVersions.first { $0.datasetType == kind && $0.status != .draft } ?? model.publishedVersions[kind]
    }
    private func currentWorkingVersion(_ kind: ConnectedDatasetType) -> ConnectedVersion? {
        model.ownVersions.first { $0.datasetType == kind && $0.status == .draft } ??
        model.ownVersions.first { $0.datasetType == kind } ?? model.publishedVersions[kind]
    }
    private func stale(_ kind: ConnectedDatasetType) -> Bool {
        guard let base = baseVersions[kind] else { return currentWorkingVersion(kind)?.status == .draft }
        guard let current = model.versions.first(where: { $0.id == base.id }) else { return true }
        return current.revision != base.revision || current.status != base.status ||
        (currentWorkingVersion(kind)?.status == .draft && currentWorkingVersion(kind)?.id != base.id)
    }
    private func editable(_ kind: ConnectedDatasetType) -> Bool {
        baseVersions[kind]?.status == .draft && !stale(kind) && !model.isBusy && !model.reloadRequired && !unavailable
    }
    private func datasetKind(_ team: PossessionTeam) -> ConnectedDatasetType { team == .ours ? .ourPossessions : .opponentPossessions }
    private func turnoverSelection(_ value: Bool?) -> String { value.map { $0 ? "yes" : "no" } ?? "unanswered" }
    private func hasRecords(_ kind: ConnectedDatasetType) -> Bool {
        if kind == .boxScores || kind == .playerPaintTouches { return !(coveredLabels[kind] ?? []).isEmpty }
        return possessions.contains { datasetKind($0.team) == kind }
    }
    private func numericBlanks(_ kind: ConnectedDatasetType) -> Bool {
        possessions.filter { datasetKind($0.team) == kind }.contains { row in
            PossessionField.allCases.contains { BoxScoreCount(row.values[$0.rawValue] ?? "") == .missing }
        }
    }
    private func hydrateInitial() {
        guard !unavailable else { return }
        for kind in kinds {
            coveredLabels[kind] = activeLabels
            if let version = currentWorkingVersion(kind) { hydrate(version, newDraft: false) }
        }
        if selectedPlayerID.isEmpty { selectedPlayerID = playerLabels.first?.id.uuidString ?? "" }
        loaded = true
    }
    private func synchronize(_ kind: ConnectedDatasetType) {
        if let version = currentWorkingVersion(kind) { hydrate(version, newDraft: false) }
    }
    private func hydrate(_ version: ConnectedVersion, newDraft: Bool) {
        do {
            let kind = version.datasetType
            let savedLabels = model.rosterLabels(for: version)
            let labels = savedLabels.isEmpty && version.coveredRoster.isEmpty && version.status == .draft ? activeLabels : savedLabels
            switch kind {
            case .boxScores:
                let records = try version.boxScores()
                guard Set(records.map { $0.playerID.uppercased() }).count == records.count else { throw ConnectedStatisticsIssue.invalidResponse }
                boxes = Dictionary(uniqueKeysWithValues: records.map { ($0.playerID.uppercased(), $0.values.mapValues(String.init)) })
                for player in labels where boxes[player.id.uuidString] == nil { boxes[player.id.uuidString] = [:] }
            case .playerPaintTouches:
                let records = try version.paintTouches()
                guard Set(records.map { $0.playerID.uppercased() }).count == records.count else { throw ConnectedStatisticsIssue.invalidResponse }
                paint = Dictionary(uniqueKeysWithValues: records.map { ($0.playerID.uppercased(), $0.total.map(String.init) ?? "") })
                for player in labels where paint[player.id.uuidString] == nil { paint[player.id.uuidString] = "" }
            case .ourPossessions, .opponentPossessions:
                let records = try version.possessions()
                guard Set(records.map(\.id)).count == records.count, Set(records.map(\.number)).count == records.count else { throw ConnectedStatisticsIssue.invalidResponse }
                possessions.removeAll { datasetKind($0.team) == kind }
                possessions += records.map { PossessionDraft(id: $0.id, team: $0.team, number: $0.number, values: $0.values.mapValues(String.init), turnover: $0.turnover) }
            }
            baseVersions[kind] = version
            coveredLabels[kind] = labels
            changed.remove(kind)
            if version.status == .draft && !isPaired && version.coveredRoster.isEmpty && !labels.isEmpty { changed.insert(kind) }
            if newDraft && !isPaired && !labels.isEmpty { changed.insert(kind) }
            if selectedPlayerID.isEmpty || !playerLabels.contains(where: { $0.id.uuidString == selectedPlayerID }) {
                selectedPlayerID = playerLabels.first?.id.uuidString ?? ""
            }
            bufferIssue = nil
            bufferIssueKind = nil
            preparationIssue = nil
            loaded = true
        } catch {
            bufferIssueKind = version.datasetType
            bufferIssue = "The server draft has invalid or unsupported record data. Reload before editing. No saved records were changed."
        }
    }
    private func save() async {
        guard invalidMessages.isEmpty, !changed.isEmpty else { return }
        do {
            var batch: [ConnectedDraftSave] = []
            let saving = kinds.filter { changed.contains($0) }
            for kind in saving {
                guard let version = baseVersions[kind], editable(kind) else { return }
                let labels = coveredLabels[kind] ?? []
                let coverage = labels.map { ConnectedCoveredPlayer(id: $0.id, version: $0.version) }
                switch kind {
                case .boxScores:
                    let records = labels.map { player in PlayerBoxScore(gameID: game.id, playerID: player.id.uuidString,
                        values: (boxes[player.id.uuidString] ?? [:]).compactMapValues { BoxScoreCount($0).number }) }
                    batch.append(try ConnectedDraftSave(version: version, boxScores: records, coveredRoster: coverage))
                case .playerPaintTouches:
                    let records = labels.map { player in PlayerPaintTouchRecord(gameID: game.id, playerID: player.id.uuidString, total: BoxScoreCount(paint[player.id.uuidString] ?? "").number) }
                    batch.append(try ConnectedDraftSave(version: version, paintTouches: records, coveredRoster: coverage))
                case .ourPossessions, .opponentPossessions:
                    let records = possessions.filter { datasetKind($0.team) == kind }.map { $0.record(gameID: game.id) }
                    batch.append(try ConnectedDraftSave(version: version, possessions: records))
                }
            }
            if await model.saveDraftBatch(batch) { for kind in saving { synchronize(kind) } }
        } catch { preparationIssue = "Could not prepare the draft for saving. The server has not confirmed these changes." }
    }
}

private struct ConnectedCompletionSheet: View {
    let model: ConnectedStatistics
    let version: ConnectedVersion
    let labels: [ConnectedRosterLabel]
    let hasNumericBlanks: Bool
    let onComplete: () -> Void
    @State private var suppressWarning = false
    @State private var confirmedRoster = false
    @Environment(\.dismiss) private var dismiss
    private var isPlayerDataset: Bool { version.datasetType == .boxScores || version.datasetType == .playerPaintTouches }
    private var showZeroWarning: Bool { !isPlayerDataset && hasNumericBlanks && !model.suppressNumericWarning }
    var body: some View {
        NavigationStack {
            Form {
                ConnectedStatisticsFeedback(model: model)
                Section("Complete this dataset") {
                    Text(version.datasetType.label).font(.headline)
                    Text("This finishes entry and makes this saved version read-only. Submission or publication remains a separate action.")
                    if isPlayerDataset {
                        Text("Optional numeric blanks remain Not entered. Confirm the actual roster covered by this dataset.")
                        ForEach(labels) { player in Text("\(player.name) · #\(player.jerseyNumber) · Version \(player.version)") }
                        Toggle("I confirm this covered actual roster", isOn: $confirmedRoster)
                    } else if showZeroWarning {
                        Label("Blank numeric fields in added possession records will become 0 when you confirm.", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                        Text("Only existing records on this team sheet are affected. Unanswered turnovers must be answered; no opposite-side records are added.")
                        Toggle("Don't show this again", isOn: $suppressWarning)
                        Text("This preference is saved for your account only after successful confirmed completion.").font(.footnote).foregroundStyle(.secondary)
                    } else if !isPlayerDataset && hasNumericBlanks {
                        Text("Your saved preference allows blank numeric fields in added records to become 0 on this explicit completion action. Turnovers still require Yes or No.")
                    }
                    Button(showZeroWarning ? "Confirm" : "Confirm completion") {
                        Task {
                            if await model.complete(version, confirmRoster: isPlayerDataset && confirmedRoster,
                                confirmNumericZeros: showZeroWarning, suppressNumericWarning: showZeroWarning && suppressWarning) {
                                onComplete()
                                dismiss()
                            }
                        }
                    }.disabled(model.isBusy || model.reloadRequired || (isPlayerDataset && (!confirmedRoster || labels.isEmpty)))
                }
            }
            .navigationTitle("Complete dataset")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Go back") { dismiss() }.disabled(model.isBusy) } }
            .interactiveDismissDisabled(model.isBusy)
        }
    }
}

private func bufferRebounds(_ values: [String: String]) -> String {
    let offensive = BoxScoreCount(values[BoxScoreField.offensiveRebounds.rawValue] ?? "")
    let defensive = BoxScoreCount(values[BoxScoreField.defensiveRebounds.rawValue] ?? "")
    guard offensive != .invalid, defensive != .invalid else { return "Unavailable — invalid input" }
    guard let first = offensive.number, let second = defensive.number else { return "Not entered" }
    return boxScoreSum([first, second]).map(String.init) ?? "Unavailable — exceeds calculation range"
}

