import Foundation

struct AccountConfiguration: Codable, Equatable, Sendable {
    enum Environment: String, Codable, CaseIterable, Sendable {
        case nonproduction
        case localTest
    }

    let url: URL
    let publicKey: String
    let environment: Environment

    init(url: String, publicKey: String, environment: Environment) throws {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmedURL), let host = parsed.host,
              !host.isEmpty, parsed.user == nil, parsed.password == nil,
              parsed.query == nil, parsed.fragment == nil,
              parsed.path.isEmpty || parsed.path == "/" else {
            throw AccountIssue.invalidConfiguration
        }
        let loopback = ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host.lowercased())
        guard (environment == .localTest && loopback && ["http", "https"].contains(parsed.scheme?.lowercased() ?? ""))
                || (environment == .nonproduction && !loopback && parsed.scheme?.lowercased() == "https") else {
            throw AccountIssue.invalidConfiguration
        }
        let key = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isPublicKey(key) else { throw AccountIssue.privilegedOrInvalidKey }
        self.url = parsed
        self.publicKey = key
        self.environment = environment
    }

    var phoneDeliveryAllowed: Bool { environment == .localTest }

    private static func isPublicKey(_ key: String) -> Bool {
        if key.hasPrefix("sb_publishable_"), key.count > "sb_publishable_".count,
           key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) {
            return true
        }
        let segments = key.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return false }
        var payload = String(segments[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["role"] as? String == "anon" else { return false }
        return true
    }
}

enum AccountIssue: Error, LocalizedError, Equatable {
    case invalidConfiguration, privilegedOrInvalidKey, invalidEmail, invalidPhone, invalidCode
    case phoneDeliveryDisabled, noPendingCode, noVerifiedSession, storage, provider, configurationWhileSignedIn
    case signOutRemoteFailure

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Use an authorized HTTPS nonproduction URL, or explicitly select a loopback local test server. Enter the server root without credentials, a path, or query."
        case .privilegedOrInvalidKey: "Enter a publishable or legacy anon key. Secret and service-role keys must stay on the server."
        case .invalidEmail: "Enter a valid email address."
        case .invalidPhone: "Enter a phone number with + and its country code, using 8–15 digits."
        case .invalidCode: "Enter the code from your message."
        case .phoneDeliveryDisabled: "Remote phone delivery is disabled until a sender is verified to cost $0 with no overages. Local test codes are available only on a loopback test server."
        case .noPendingCode: "Request a code before verifying it."
        case .noVerifiedSession: "A verified account session was not returned. Sign in again."
        case .storage: "Secure account storage is unavailable. Unlock the device and retry."
        case .provider: "The account server could not complete this request. Check its setup or connection and retry."
        case .configurationWhileSignedIn: "Sign out before changing the account server."
        case .signOutRemoteFailure: "Signed out on this device. The server could not confirm session revocation; an existing access token may remain valid until it expires."
        }
    }
}

import Observation
import CryptoKit
import Supabase

enum AccountMethod: String, CaseIterable, Equatable, Sendable {
    case email, phone
}

enum AccountState: Equatable {
    case unconfigured, signedOut, pendingVerification(AccountMethod), authenticated(UUID), error
}

/// Authentication establishes an Auth UUID only. Team membership and capabilities
/// must be read/checked by authorized server commands, never derived from contact data.
@MainActor @Observable
final class BackendAccount {
    private(set) var configuration: AccountConfiguration?
    private(set) var state: AccountState = .unconfigured
    private(set) var isBusy = false
    private(set) var issue: AccountIssue?
    private(set) var pendingMethod: AccountMethod?
    @ObservationIgnored private var pendingIdentifier: String?
    @ObservationIgnored private let storage: any AuthLocalStorage
    @ObservationIgnored private let httpSession: URLSession
    @ObservationIgnored private var client: SupabaseClient?
    @ObservationIgnored private var didRestore = false
    @ObservationIgnored private let configurationKey = "configuration.v1"

    init(storage: any AuthLocalStorage = SecureSessionStorage(), session: URLSession = .shared) {
        self.storage = storage
        self.httpSession = session
    }

    var verifiedUserID: UUID? {
        if case .authenticated(let id) = state { return id }
        return nil
    }

    func configure(url: String, publicKey: String, environment: AccountConfiguration.Environment) async {
        guard !isBusy else { return }
        guard verifiedUserID == nil, client?.auth.currentSession == nil else { fail(.configurationWhileSignedIn); return }
        isBusy = true
        defer { isBusy = false }
        do {
            let value = try AccountConfiguration(url: url, publicKey: publicKey, environment: environment)
            do { try storage.store(key: configurationKey, value: JSONEncoder().encode(value)) }
            catch { throw AccountIssue.storage }
            configuration = value
            client = makeClient(value)
            pendingMethod = nil
            pendingIdentifier = nil
            issue = nil
            state = .signedOut
        } catch { fail(error as? AccountIssue ?? .storage) }
    }

    func requestCode(method: AccountMethod, identifier: String) async {
        guard !isBusy else { return }
        guard let configuration, let client else { fail(.invalidConfiguration); return }
        guard verifiedUserID == nil else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let contact: String
            do { contact = try normalized(identifier, method: method) }
            catch {
                pendingMethod = nil
                pendingIdentifier = nil
                throw error
            }
            // A new target cannot reuse the previous target's verification challenge.
            // Retain the same challenge on a failed resend so an existing code still works.
            if method != pendingMethod || contact != pendingIdentifier {
                pendingMethod = nil
                pendingIdentifier = nil
            }
            if method == .phone && !configuration.phoneDeliveryAllowed { throw AccountIssue.phoneDeliveryDisabled }
            if method == .email {
                try await client.auth.signInWithOTP(email: contact)
            } else {
                try await client.auth.signInWithOTP(phone: contact, channel: .sms)
            }
            pendingIdentifier = contact
            pendingMethod = method
            issue = nil
            state = .pendingVerification(method)
        } catch { fail(error as? AccountIssue ?? .provider) }
    }


    func restoreIfNeeded() async {
        guard !didRestore else { return }
        didRestore = true
        await restore()
    }

    /// Rechecks persisted credentials against Auth. A local token alone never
    /// establishes authenticated state after restart or a failed request.
    func restore() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            guard let data = try read(key: configurationKey) else {
                state = .unconfigured
                issue = nil
                return
            }
            let stored: AccountConfiguration
            do { stored = try JSONDecoder().decode(AccountConfiguration.self, from: data) }
            catch { throw AccountIssue.invalidConfiguration }
            let validated = try AccountConfiguration(url: stored.url.absoluteString, publicKey: stored.publicKey, environment: stored.environment)
            configuration = validated
            // Read and decode explicitly: the SDK otherwise turns read errors
            // into an absent session and suppresses write/delete errors.
            guard let sessionData = try read(key: sessionKey(validated)) else {
                client = makeClient(validated)
                state = .signedOut
                issue = nil
                return
            }
            do { _ = try JSONDecoder().decode(Session.self, from: sessionData) }
            catch { throw AccountIssue.storage }
            let restoredClient = makeClient(validated)
            client = restoredClient
            try await acceptSession(from: restoredClient)
        } catch { fail(error as? AccountIssue ?? .provider) }
    }

    func verifyCode(_ code: String) async {
        guard !isBusy else { return }
        guard let client, let method = pendingMethod, let contact = pendingIdentifier else { fail(.noPendingCode); return }
        let token = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (4...12).contains(token.count), token.allSatisfy({ $0.isASCII && $0.isNumber }) else { fail(.invalidCode); return }
        isBusy = true
        defer { isBusy = false }
        do {
            let response: AuthResponse
            if method == .email {
                response = try await client.auth.verifyOTP(email: contact, token: token, type: .email)
            } else {
                guard configuration?.phoneDeliveryAllowed == true else { throw AccountIssue.phoneDeliveryDisabled }
                response = try await client.auth.verifyOTP(phone: contact, token: token, type: .sms)
            }
            guard let session = response.session, let configuration else { throw AccountIssue.noVerifiedSession }
            do { try storage.store(key: sessionKey(configuration), value: JSONEncoder().encode(session)) }
            catch { throw AccountIssue.storage }
            try await acceptSession(from: client)
            pendingMethod = nil
            pendingIdentifier = nil
        } catch { fail(error as? AccountIssue ?? .provider) }
    }

    func resendCode() async {
        guard let method = pendingMethod, let contact = pendingIdentifier else { fail(.noPendingCode); return }
        await requestCode(method: method, identifier: contact)
    }

    /// Caller uses this verified session to invoke server-authorized commands.
    /// The server alone decides team admission, grants and owner authority.
    func authenticatedClient() async throws -> SupabaseClient {
        guard !isBusy, verifiedUserID != nil, let client else { throw AccountIssue.noVerifiedSession }
        isBusy = true
        defer { isBusy = false }
        do {
            try await acceptSession(from: client)
            return client
        } catch {
            let issue = error as? AccountIssue ?? .provider
            fail(issue)
            throw issue
        }
    }

    func signOut() async {
        guard !isBusy, let configuration else { return }
        isBusy = true
        defer { isBusy = false }
        let oldClient = client
        // The SDK captures the token, removes its local session, then requests
        // server revocation. Explicit deletion below also checks suppressed failures.
        var remoteFailure = false
        do { try await oldClient?.auth.signOut(scope: .local) }
        catch { remoteFailure = true }
        do { try storage.remove(key: sessionKey(configuration)) }
        catch { fail(.storage); return }
        client = nil
        pendingMethod = nil
        pendingIdentifier = nil
        issue = remoteFailure ? .signOutRemoteFailure : nil
        state = .signedOut
        client = makeClient(configuration)
    }

    private func acceptSession(from client: SupabaseClient) async throws {
        guard let configuration else { throw AccountIssue.invalidConfiguration }
        _ = try read(key: sessionKey(configuration))
        let session = try await client.auth.session
        let verifiedUser = try await client.auth.user(jwt: session.accessToken)
        guard !verifiedUser.isAnonymous, verifiedUser.id == session.user.id,
              !session.accessToken.isEmpty, !session.refreshToken.isEmpty else { throw AccountIssue.noVerifiedSession }
        do { try storage.store(key: sessionKey(configuration), value: JSONEncoder().encode(session)) }
        catch { throw AccountIssue.storage }
        issue = nil
        state = .authenticated(verifiedUser.id)
    }

    private func read(key: String) throws -> Data? {
        do { return try storage.retrieve(key: key) }
        catch { throw AccountIssue.storage }
    }

    private func makeClient(_ value: AccountConfiguration) -> SupabaseClient {
        SupabaseClient(supabaseURL: value.url, supabaseKey: value.publicKey, options: .init(
            auth: .init(storage: storage, storageKey: sessionKey(value), autoRefreshToken: false, emitLocalSessionAsInitialSession: true),
            global: .init(session: httpSession, logger: nil)
        ))
    }

    private func sessionKey(_ value: AccountConfiguration) -> String {
        let namespace = value.environment.rawValue + "|" + value.url.absoluteString + "|" + value.publicKey
        let digest = SHA256.hash(data: Data(namespace.utf8)).map { String(format: "%02x", $0) }.joined()
        return "session.v1." + digest
    }

    private func normalized(_ identifier: String, method: AccountMethod) throws -> String {
        let value = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        switch method {
        case .email:
            let parts = value.split(separator: "@", omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
                  !value.contains(where: { $0.isWhitespace }), value.count <= 254 else { throw AccountIssue.invalidEmail }
            return value
        case .phone:
            let compact = value.filter { ![" ", "-", "(", ")"].contains($0) }
            guard compact.first == "+", (9...16).contains(compact.count),
                  compact.dropFirst().allSatisfy({ $0.isASCII && $0.isNumber }), compact.dropFirst().first != "0" else {
                throw AccountIssue.invalidPhone
            }
            return compact
        }
    }

    private func fail(_ issue: AccountIssue) {
        self.issue = issue
        state = .error
    }
}
