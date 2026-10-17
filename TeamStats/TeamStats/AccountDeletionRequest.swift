import Foundation
import Observation
import Supabase

struct AccountDeletionReceipt: Decodable, Equatable, Sendable {
    let id: UUID
    let userID: UUID
    let requestedAt: String
    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id", requestedAt = "requested_at"
    }
    var date: Date? {
        let format = ISO8601DateFormatter()
        if let date = format.date(from: requestedAt) { return date }
        format.formatOptions.insert(.withFractionalSeconds)
        return format.date(from: requestedAt)
    }
}

enum AccountDeletionIssue: Error, Equatable {
    case unavailable, unconfirmed, denied, invalidResponse
    var message: String {
        switch self {
        case .unavailable: "Account-deletion requests are unavailable on this server. No request has been confirmed. Retry loading later."
        case .unconfirmed: "The server reply could not be confirmed. Reload the request before trying again; it may already be recorded."
        case .denied: "Current account access could not be verified. Check your session in Account before retrying."
        case .invalidResponse: "The server returned an unexpected request receipt. Reload before continuing."
        }
    }
}

/// Intake only: a receipt never means deletion is scheduled or executed.
@MainActor @Observable
final class AccountDeletionRequest {
    private(set) var receipt: AccountDeletionReceipt?
    private(set) var didLoad = false
    private(set) var isBusy = false
    private(set) var issue: AccountDeletionIssue?
    private let userID: UUID
    @ObservationIgnored private let authenticatedClient: () async throws -> SupabaseClient
    @ObservationIgnored private let currentSession: () -> Bool
    private var invalidated = false
    var isCurrentSession: Bool { !invalidated && currentSession() }
    var canSubmit: Bool { isCurrentSession && didLoad && !isBusy && receipt == nil && issue == nil }

    init(userID: UUID, authenticatedClient: @escaping () async throws -> SupabaseClient,
         isCurrentSession: @escaping () -> Bool) {
        self.userID = userID; self.authenticatedClient = authenticatedClient; currentSession = isCurrentSession
    }
    convenience init(account: BackendAccount, userID: UUID) {
        let generation = account.authenticationGeneration
        self.init(userID: userID, authenticatedClient: { try await account.authenticatedClient() },
                  isCurrentSession: { account.authenticationGeneration == generation && account.sessionContextID == userID })
    }
    func invalidate() {
        invalidated = true; receipt = nil; didLoad = false; issue = nil
    }
    func load() async { await perform(submitting: false) }
    func submit() async {
        guard canSubmit else { return }
        await perform(submitting: true)
    }
    private func perform(submitting: Bool) async {
        guard !isBusy else { return }
        guard isCurrentSession else { invalidate(); return }
        isBusy = true; defer { isBusy = false }
        didLoad = false; issue = nil; receipt = nil
        do {
            let client = try await authenticatedClient()
            try Task.checkCancellation()
            guard isCurrentSession else { invalidate(); return }
            let name = submitting ? "account_request_deletion" : "account_deletion_receipt"
            let result: AccountDeletionReceipt? = try await client.rpc(name).retry(enabled: false).execute().value
            try Task.checkCancellation()
            guard isCurrentSession else { invalidate(); return }
            if let result {
                guard result.userID == userID, result.id != UUID(uuidString: "00000000-0000-0000-0000-000000000000"),
                      result.requestedAt.count <= 64, result.date != nil else { throw AccountDeletionIssue.invalidResponse }
            } else if submitting { throw AccountDeletionIssue.invalidResponse }
            receipt = result; didLoad = true
        } catch {
            guard isCurrentSession else { invalidate(); return }
            if let error = error as? AccountDeletionIssue { issue = error }
            else if let error = error as? PostgrestError {
                switch error.code {
                case "42501", "PGRST301", "PGRST302", "PGRST303": issue = .denied
                case "PGRST202": issue = .unavailable
                default: issue = .unconfirmed
                }
            } else if error is DecodingError { issue = .invalidResponse }
            else { issue = .unconfirmed }
        }
    }
}
