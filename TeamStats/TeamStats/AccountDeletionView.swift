import SwiftUI

struct AccountDeletionView: View {
    @State var model: AccountDeletionRequest
    @State private var confirming = false

    var body: some View {
        Form {
            if !model.isCurrentSession {
                Section { Text("Your account session changed. Return to Account and verify your session.") }
            } else {
                Section {
                    Text("Request account deletion")
                        .font(.headline)
                    Text("This records your request only. Your account remains active. Deletion processing is not available in this prototype; no deletion date is promised.")
                    Text("Shared records, local drafts and team ownership are unchanged.")
                        .foregroundStyle(TeamStatsStyle.secondaryText)
                }
                Section("Request status") {
                    if model.isBusy {
                        ProgressView("Checking with the account server…")
                    } else if let receipt = model.receipt {
                        Label("Request recorded. Your account remains active.", systemImage: "checkmark.circle")
                            .accessibilityIdentifier("account-deletion.received")
                        if let date = receipt.date {
                            LabeledContent("Recorded", value: date.formatted(date: .abbreviated, time: .shortened))
                        }
                        Text("Request reference").font(.caption)
                        Text(receipt.id.uuidString).font(.caption.monospaced())
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    } else if model.didLoad {
                        Text("No account-deletion request is recorded for this account.")
                    }
                    if let issue = model.issue {
                        Label(issue.message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(TeamStatsStyle.errorText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("account-deletion.error")
                    }
                    Button("Reload request") { Task { await model.load() } }
                        .frame(minHeight: 44).disabled(model.isBusy)
                        .accessibilityIdentifier("account-deletion.reload")
                }
                if model.canSubmit {
                    Section {
                        Button("Request account deletion") { confirming = true }
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("account-deletion.request")
                    }
                }
            }
        }
        .navigationTitle("Account deletion")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .onChange(of: model.isCurrentSession) { _, current in
            if !current { model.invalidate(); confirming = false }
        }
        .alert("Record an account-deletion request?", isPresented: $confirming) {
            Button("Cancel", role: .cancel) {}
            Button("Record request") { Task { await model.submit() } }
        } message: {
            Text("The server will record your request. This does not delete or disable your account, remove records or transfer team ownership. Deletion processing is unavailable in this prototype.")
        }
    }
}
