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
                Text("Choose the game, enter observations, and save your draft. TeamStats does not track live games.")
            }
            Section("Local drafts") {
                Label("On this device", systemImage: "iphone").font(.headline).foregroundStyle(Color.accentColor)
                Text("Local games use the labeled temporary roster. A local save does not publish data or upload it to a team.")
                Text("Blank means not entered; 0 is an explicit observation. Individual and roster-table box-score modes edit the same values.")
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
                Text("Export a private JSON copy of saved local games and observations. Unsaved entries, account credentials, shared records and clips are excluded. No import or automatic restore is provided.")
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
                Text("TODO_PRIVACY_POLICY · TODO_REPORTING_CONTACT · TODO_RETENTION_POLICY · TODO_ACCOUNT_DELETION_POLICY — owner-approved policies, reporting channel and deletion/ownership handling are not supplied. Account offers request-only deletion intake when its server supports it. Your account remains active; deletion execution is unavailable in this prototype.")
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
