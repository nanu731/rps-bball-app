import SwiftUI
import UniformTypeIdentifiers

struct TeamStatsGuide: View {
    @ScaledMetric(relativeTo: .body) private var readingWidth = 640.0
    @State private var backup: DraftBackupDocument?
    @State private var exporting = false
    @State private var exportMessage: String?

    var body: some View {
        List {
            Section("After the game") {
                Text("Enter box scores, possessions and player paint touches after games. Choose the game, record observations and save your draft.")
            }
            Section("Local drafts") {
                Label("On this device", systemImage: "iphone").font(.headline).foregroundStyle(Color.accentColor)
                Text("Local games use the labeled temporary roster. A local save does not publish data or upload it to a team.")
                Text("Blank means not entered; 0 is an explicit observation. Individual and roster-table box-score modes edit the same values.")
            }
            Section("Optional shot recorder") {
                Text("Open Shot recorder from a game's details. Choose the next team, our player and attacking basket, then tap the schematic court and choose2PT/3PT Make or Miss. Selections do not reattribute a pending observation.")
                Text("Free throws are entered separately, with one answer per attempt. Unanswered means pending. Undo and corrections retain history. These captures do not replace or add to after-game official statistics.")
                Text("Recorded shot charts keep field goals and free throws separate and compare independent sources without adding them together. Score agreement does not establish attempt coverage; missing official values stay unavailable.")
                Text("For an authorized shared game, prepare its actual-roster capture online before going offline. Continue only that prepared capture on this device. Reconnect and explicitly submit; fresh server authority, separate review and publication still apply. Handoffs and competing branches need explicit recovery review, never an automatic merge.")
                Text("A saved-on-device receipt is local only. If saving fails, retry the same change or preserve a separate recovery copy before reopening. Original records are not uploaded automatically.")
            }
            Section("Manual-statistics pilot") {
                Text("Shared manual statistics are the first pilot scope. Automatic Sheets and hosted media delivery are not enabled. Saving a draft is separate from completion, review and publication.")
            }
            Section("Shared team records") {
                Label("Server-confirmed access", systemImage: "person.2").font(.headline).foregroundStyle(Color.accentColor)
                Text("Sign in through Account, then use Team to request admission or open an admitted team. Signing in alone does not grant team permissions.")
                Text("Save, entry completion, submission and publication are separate actions. Only a confirmed accepted version is published. Completed data needs authorized reopening before correction.")
                Text("If a request fails, keep your entries and use the offered Retry or recovery action. An earlier saved receipt does not confirm new edits.")
            }
            Section("Team content and saved clips") {
                Text("Playbook contains approved drawings and movement. Scouting PDFs and practice clips require their own permissions. Full-game film opens separately in Hudl, which controls its own access.")
                Text("Keep on this device explicitly retains a practice clip. Previously authorized saved clips can play offline when current rights cannot be checked. Sign-out, account switching and known access loss hide them in the app; delivered copies cannot reliably be recalled.")
            }
            Section("Copy saved local drafts") {
                Text("Export a private JSON copy of saved local games, observations and local shot journals, including pending attempts and correction history. Unsaved input, separate failed-save recovery copies, account credentials, shared records and clips are excluded. Recovery tooling restores only into a new isolated folder; no in-app import or automatic restore is provided.")
                Text("The copy contains your draft data. Choose a private destination you control.").font(.footnote)
                Button("Export saved local drafts", systemImage: "square.and.arrow.up") {
                    do {
                        backup = DraftBackupDocument(data: try LocalDraftBackup.snapshot().encodedData())
                        exportMessage = nil
                        exporting = true
                    } catch {
                        exportMessage = "Could not prepare the copy. No drafts were changed. \(error.localizedDescription)"
                    }
                }.frame(minHeight: 44)
                if let exportMessage { Text(exportMessage).fixedSize(horizontal: false, vertical: true) }
            }
            Section("Account recovery and privacy") {
                Text("Request a fresh sign-in link in Account to recover access. Team permissions still come from the server.")
                Link("Contact TeamStats for support, security or deletion requests", destination: URL(string: "mailto:happybuddha1008@gmail.com" )!)
                    .frame(minHeight: 44)
                Text("TODO_PRIVACY_POLICY · TODO_RETENTION_POLICY · TODO_ACCOUNT_DELETION_POLICY — retention, response commitments and deletion/ownership handling are not supplied. Account offers request-only deletion intake when its server supports it. Your account remains active; deletion execution is unavailable in this prototype.")
                    .font(.footnote).textSelection(.enabled)
            }
            Section("App information") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unavailable")
                LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unavailable")
                LabeledContent("Source revision", value: Bundle.main.object(forInfoDictionaryKey: "TeamStatsSourceRevision") as? String ?? "Not recorded in this build")
                Text("This prototype is not accepted for release. Hosted delivery, real-content accuracy and device coverage have separate verification requirements.")
                    .font(.footnote)
            }
        }
        .frame(maxWidth: readingWidth)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Using TeamStats")
        .fileExporter(isPresented: $exporting, document: backup, contentType: .json,
                      defaultFilename: "TeamStats-local-drafts") { result in
            switch result {
            case .success: exportMessage = "Saved local-draft copy to your selected destination."
            case .failure(let error): exportMessage = "Could not export the copy. No drafts were changed. \(error.localizedDescription)"
            }
        }
    }
}

private struct DraftBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
