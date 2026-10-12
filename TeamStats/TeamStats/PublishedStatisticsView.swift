import Foundation
import SwiftUI

struct PublishedStatisticsView: View {
    let model: ConnectedStatistics
    let game: ConnectedGame

    var body: some View {
        List {
            ConnectedStatisticsFeedback(model: model)
            if !model.didLoadGame || model.selectedGame?.id != game.id {
                Section { Text("Published statistics are unavailable until this game loads successfully.") }
            } else {
                Section("Accepted dataset status") {
                    Text("These are the current server-accepted versions. Publication applies to each dataset independently.")
                        .foregroundStyle(.secondary)
                    ForEach(ConnectedDatasetType.allCases, id: \.self) { kind in
                        if let version = model.publishedVersions[kind] {
                            NavigationLink("\(kind.label) · Published revision \(version.revision)") {
                                ConnectedVersionDetailView(model: model, version: version)
                            }
                        } else { LabeledContent(kind.label, value: "Not published") }
                    }
                    if model.publishedVersions.count < ConnectedDatasetType.allCases.count {
                        Label("Partial published game — some datasets are not published.", systemImage: "info.circle")
                    }
                    Text("A missing optional count is Not entered; an entered zero is 0. No draft or pending proposal contributes to these metrics.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let box = model.publishedVersions[.boxScores] {
                    Section("Accepted player box scores") {
                        ConnectedVersionRecords(model: model, version: box, labels: model.rosterLabels(for: box))
                    }
                }
                if let paint = model.publishedVersions[.playerPaintTouches] {
                    Section("Accepted player paint-touch totals") {
                        ConnectedVersionRecords(model: model, version: paint, labels: model.rosterLabels(for: paint))
                    }
                }
                PublishedMetricSections(model: model)
                Section {
                    Text("Paint-touch player totals are independently collected. No player attribution or repeated-touch interpretation is inferred from team possession records.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Published statistics")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PublishedMetricSections: View {
    let model: ConnectedStatistics
    private var result: Result<GameStatistics?, Error> { Result { try model.publishedStatistics() } }
    var body: some View {
        switch result {
        case .failure:
            Section {
                Label("Accepted records could not be read. Metrics are unavailable.", systemImage: "exclamationmark.triangle")
                Button("Reload / Retry") { Task { await model.reload() } }.disabled(model.isBusy)
            }
        case .success(nil):
            Section { Text("No game statistics loaded.") }
        case .success(.some(let statistics)):
            Section("Our players · Accepted totals") {
                ForEach(BoxScoreField.allCases, id: \.self) { field in
                    LabeledContent(field.label, value: connectedStatistic(statistics.boxScoreTotal(field)))
                }
                LabeledContent("Total rebounds", value: connectedStatistic(statistics.boxScoreRebounds()))
                ForEach(StatisticShot.allCases, id: \.self) { shot in
                    LabeledContent("\(connectedShotLabel(shot)) attempts", value: connectedStatistic(statistics.boxScoreShotAttempts(shot)))
                    LabeledContent("\(connectedShotLabel(shot)) percentage", value: connectedPercentage(statistics.boxScoreShootingPercentage(shot)))
                }
            }
            ForEach(PossessionTeam.allCases, id: \.self) { team in
                Section("\(team.label) · Accepted possession metrics") {
                    LabeledContent("Points from made shots", value: connectedStatistic(statistics.possessionPoints(team: team)))
                    ForEach(PossessionField.allCases, id: \.self) { field in
                        LabeledContent(field.label, value: connectedStatistic(statistics.possessionTotal(field, team: team)))
                    }
                    LabeledContent("Real Possessions", value: connectedStatistic(statistics.realPossessions(team: team)))
                    ForEach(StatisticShot.allCases, id: \.self) { shot in
                        LabeledContent("\(connectedShotLabel(shot)) attempts", value: connectedStatistic(statistics.possessionShotAttempts(shot, team: team)))
                        LabeledContent("\(connectedShotLabel(shot)) percentage", value: connectedPercentage(statistics.possessionShootingPercentage(shot, team: team)))
                    }
                    Text("Real Possessions = this team's game possessions − turnovers + offensive rebounds. Each team is calculated independently.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Box scores / Our possession sheet") {
                switch statistics.reconcile() {
                case .available(let comparisons):
                    ForEach(comparisons, id: \.field) { comparison in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(comparison.field.label, systemImage: comparison.matches ? "checkmark.circle" : "exclamationmark.triangle")
                            Text("Box scores: \(comparison.boxScoreTotal) · Our possession sheet: \(comparison.possessionTotal)")
                            Text(comparison.matches ? "Match" : "Disagree · Difference \(comparison.difference)")
                        }.foregroundStyle(comparison.matches ? Color.primary : Color.red)
                    }
                case .unavailable(let reason):
                    Label("Reconciliation unavailable: \(connectedUnavailable(reason))", systemImage: "info.circle")
                }
                Text("Comparison requires completed, matching accepted data for points, twos made/missed, threes made/missed and free throws made/missed. Missing data never counts as a match.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

struct ConnectedVersionRecords: View {
    let model: ConnectedStatistics
    let version: ConnectedVersion
    let labels: [ConnectedRosterLabel]
    private var snapshot: ConnectedRecordSnapshot {
        do {
            switch version.datasetType {
            case .boxScores: return .boxes(try version.boxScores())
            case .playerPaintTouches: return .paint(try version.paintTouches())
            case .ourPossessions, .opponentPossessions: return .possessions(try version.possessions())
            }
        } catch { return .unavailable }
    }
    var body: some View {
        switch snapshot {
        case .unavailable:
            Label("Saved records could not be read. No totals are shown.", systemImage: "exclamationmark.triangle")
        case .boxes(let records):
            if records.isEmpty { Text("No box-score records in this saved version.").foregroundStyle(.secondary) }
            ForEach(records, id: \.playerID) { record in
                NavigationLink(connectedPlayerLabel(record.playerID, labels: labels)) {
                    List {
                        Section("Saved box score") {
                            if model.didLoadGame {
                            ForEach(BoxScoreField.allCases, id: \.self) { field in
                                LabeledContent(field.label, value: summaryCount(record.values[field.rawValue]))
                            }
                            LabeledContent("Total rebounds", value: summaryRebounds(record.values))
                            ShotCheckNotice(message: summaryShotCheck(record.values))
                            } else { Text("Saved dataset unavailable. Reload authorized server data.") }
                        }
                    }.navigationTitle(connectedPlayerLabel(record.playerID, labels: labels))
                }
            }
        case .paint(let records):
            if records.isEmpty { Text("No paint-touch player records in this saved version.").foregroundStyle(.secondary) }
            ForEach(records, id: \.playerID) { record in
                LabeledContent(connectedPlayerLabel(record.playerID, labels: labels), value: summaryCount(record.total))
            }
        case .possessions(let records):
            LabeledContent("Records entered", value: String(records.count))
            if records.isEmpty { Text("No possession records in this saved version.").foregroundStyle(.secondary) }
            Text(version.status == .published ? "Accepted completed sheet. This dataset does not establish whole-game completion." : "Saved records in this dataset; not a published game total.")
                .font(.footnote).foregroundStyle(.secondary)
            ForEach(records.sorted { $0.number < $1.number }) { record in
                NavigationLink("\(record.team.label) · Record \(record.number)") {
                    List {
                        if model.didLoadGame {
                        ForEach(PossessionField.allCases, id: \.self) { field in
                            LabeledContent(field.label, value: summaryCount(record.values[field.rawValue]))
                        }
                        LabeledContent("Turnover", value: record.turnover.map { $0 ? "Yes" : "No" } ?? "Unanswered")
                        } else { Text("Saved dataset unavailable. Reload authorized server data.") }
                    }.navigationTitle("Record \(record.number)")
                }
            }
        }
    }
}

private enum ConnectedRecordSnapshot {
    case boxes([PlayerBoxScore]), paint([PlayerPaintTouchRecord]), possessions([PossessionRecord]), unavailable
}

struct ConnectedExportQueueView: View {
    let model: ConnectedStatistics
    var body: some View {
        List {
            ConnectedStatisticsFeedback(model: model)
            Section {
                Text("The server creates one immutable export outbox item for each accepted dataset version.")
                Text("Only Delivered confirms a server receipt. Delivery requires a separately configured trusted worker and an approved zero-cost Google setup. Queued items do not confirm spreadsheet delivery.")
                    .foregroundStyle(.secondary)
            }
            if model.access?.isOwner != true || !model.didLoadGame {
                Section { Text("Export queue unavailable. Owner access and a successful server load are required.") }
            } else {
                if model.isLoadingExportStatus { Section { ProgressView("Loading delivery status…") } }
                if let issue = model.exportIssue {
                    Section("Delivery status unavailable") {
                        Label(issue.localizedDescription, systemImage: "exclamationmark.triangle")
                        Button("Retry delivery status") { Task { await model.loadExportStatus() } }
                            .disabled(model.isLoadingExportStatus)
                    }
                }
                if model.didLoadExportStatus {
                    Section("Server delivery status") {
                        if model.exportStatus.isEmpty { Text("No export items returned for this game.").foregroundStyle(.secondary) }
                        ForEach(model.exportStatus) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.datasetType.label).font(.headline)
                                Label(item.state.label, systemImage: item.state == .delivered ? "checkmark.circle" : item.state == .failed ? "exclamationmark.triangle" : "clock")
                                Text("Publication generation \(item.publicationGeneration)")
                                Text("Accepted version \(item.acceptedVersionID.uuidString)").font(.caption).textSelection(.enabled)
                                Text("Delivery attempts: \(item.attempts)").foregroundStyle(.secondary)
                                if let code = item.errorCode { Text("Reason: \(code)").textSelection(.enabled) }
                                if let date = item.deliveredAt { Text("Confirmed \(date)").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }
        }.navigationTitle("Sheets export status")
            .task { await model.loadExportStatus() }
            .refreshable { await model.loadExportStatus() }
    }
}

func connectedPlayerLabel(_ id: String, labels: [ConnectedRosterLabel]) -> String {
    guard let player = labels.first(where: { $0.id.uuidString.caseInsensitiveCompare(id) == .orderedSame }) else {
        return "Historical player \(id) · label unavailable"
    }
    return "\(player.name) · #\(player.jerseyNumber)"
}

func connectedStatistic(_ value: StatisticValue<Int>) -> String {
    switch value {
    case .available(let number): String(number)
    case .unavailable(let reason): connectedUnavailable(reason)
    }
}
func connectedPercentage(_ value: StatisticValue<Double>) -> String {
    switch value {
    case .available(let number): number.formatted(.number.precision(.fractionLength(1))) + "%"
    case .unavailable(let reason): connectedUnavailable(reason)
    }
}
func connectedUnavailable(_ reason: StatisticUnavailable) -> String {
    switch reason {
    case .incompleteDataset: "Requires completed published dataset"
    case .missingInput: "Not entered — required input missing"
    case .invalidInput: "Unavailable — invalid records"
    case .overflow: "Unavailable — exceeds calculation range"
    case .zeroAttempts: "Unavailable — zero attempts"
    }
}
func connectedShotLabel(_ shot: StatisticShot) -> String {
    switch shot {
    case .twos: "Two-point"
    case .threes: "Three-point"
    case .freeThrows: "Free-throw"
    }
}
