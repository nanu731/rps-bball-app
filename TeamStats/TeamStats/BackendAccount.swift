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
    case signOutRemoteFailure, invalidEmailLink

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
        case .invalidEmailLink: "This email link is unavailable or was not requested on this device. Request a new sign-in email, then open its link on the same device."
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
    static let emailRedirectURL = URL(string: "com.narayanlekhi.teamstats://auth/callback")!

    private(set) var configuration: AccountConfiguration?
    private(set) var state: AccountState = .unconfigured
    // Editing context survives a failed network check. It grants no authority;
    // commands still reverify Auth and server permissions before proceeding.
    private(set) var sessionContextID: UUID?
    // Keychain-backed prior Auth confirmation permits only scoped device clip viewing.
    // It never restores authenticated state or supplies a remote command client.
    private(set) var offlineClipActorID: UUID?
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
            sessionContextID = nil
            offlineClipActorID = nil
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
                try clearEmailLink(configuration)
                throw error
            }
            // A new target cannot reuse the previous target's verification challenge.
            // Retain the same challenge on a failed resend so an existing code still works.
            if method != pendingMethod || contact != pendingIdentifier {
                pendingMethod = nil
                pendingIdentifier = nil
                try clearEmailLink(configuration)
            }
            if method == .phone && !configuration.phoneDeliveryAllowed { throw AccountIssue.phoneDeliveryDisabled }
            if method == .email {
                let verifierKey = sessionKey(configuration) + "-code-verifier"
                let previousVerifier = try read(key: verifierKey)
                do {
                    try await client.auth.signInWithOTP(email: contact, redirectTo: Self.emailRedirectURL)
                } catch {
                    // A failed resend must not invalidate a previously delivered link.
                    if let previousVerifier {
                        do { try storage.store(key: verifierKey, value: previousVerifier) }
                        catch { throw AccountIssue.storage }
                    }
                    throw error
                }
                guard try read(key: verifierKey) != nil else { throw AccountIssue.storage }
                do { try storage.store(key: emailLinkKey(configuration), value: Data(contact.utf8)) }
                catch { throw AccountIssue.storage }
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
                sessionContextID = nil
                offlineClipActorID = nil
                issue = nil
                return
            }
            let stored: AccountConfiguration
            do { stored = try JSONDecoder().decode(AccountConfiguration.self, from: data) }
            catch { throw AccountIssue.invalidConfiguration }
            let validated = try AccountConfiguration(url: stored.url.absoluteString, publicKey: stored.publicKey, environment: stored.environment)
            offlineClipActorID = nil
            configuration = validated
            // Read and decode explicitly: the SDK otherwise turns read errors
            // into an absent session and suppresses write/delete errors.
            guard let sessionData = try read(key: sessionKey(validated)) else {
                client = makeClient(validated)
                state = .signedOut
                sessionContextID = nil
                offlineClipActorID = nil
                issue = nil
                return
            }
            let storedSession: Session
            do { storedSession = try JSONDecoder().decode(Session.self, from: sessionData) }
            catch { throw AccountIssue.storage }
            if let stamp = try read(key: offlineStampKey(validated)) {
                do {
                    let actor = try JSONDecoder().decode(OfflineActorStamp.self, from: stamp).actorID
                    // Binding prevents a failed account change from exposing a prior actor's clips.
                    // It supplies no remote authority; fresh Auth verification still follows.
                    if actor == storedSession.user.id { offlineClipActorID = actor }
                } catch { throw AccountIssue.storage }
            }
            let restoredClient = makeClient(validated)
            client = restoredClient
            try await acceptSession(from: restoredClient)
        } catch {
            var failure = error as? AccountIssue ?? .provider
            if knownSessionDenial(error) {
                sessionContextID = nil
                do { try invalidateOfflineActor() } catch { failure = .storage }
            }
            fail(failure)
        }
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
            try clearEmailLink(configuration)
            pendingMethod = nil
            pendingIdentifier = nil
        } catch { fail(error as? AccountIssue ?? .provider) }
    }

    /// Accept only a PKCE code for this exact app route and this device's saved
    /// email request. Bearer tokens in callbacks are never accepted or logged.
    func handleEmailLink(_ url: URL) async {
        guard !isBusy, verifiedUserID == nil else { return }
        await restoreIfNeeded()
        guard !isBusy, verifiedUserID == nil else { return }
        isBusy = true
        defer { isBusy = false }
        var receivedSession = false
        do {
            guard let configuration, let client,
                  let route = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  route.scheme == Self.emailRedirectURL.scheme,
                  route.host == "auth", route.path == "/callback",
                  route.user == nil, route.password == nil, route.fragment == nil,
                  let items = route.queryItems, items.count == 1,
                  items[0].name == "code", let code = items[0].value,
                  !code.isEmpty, code.count <= 512,
                  code.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }),
                  let target = try read(key: emailLinkKey(configuration)),
                  let email = String(data: target, encoding: .utf8),
                  try read(key: sessionKey(configuration) + "-code-verifier") != nil else {
                throw AccountIssue.invalidEmailLink
            }
            let session = try await client.auth.session(from: url)
            receivedSession = true
            do { try storage.store(key: sessionKey(configuration), value: JSONEncoder().encode(session)) }
            catch { throw AccountIssue.storage }
            try await acceptSession(from: client, expectedEmail: email)
            try clearEmailLink(configuration)
            pendingMethod = nil
            pendingIdentifier = nil
        } catch {
            let issue = error as? AccountIssue ?? .provider
            if receivedSession, let configuration {
                try? await client?.auth.signOut(scope: .local)
                do {
                    try storage.remove(key: sessionKey(configuration))
                    try clearEmailLink(configuration)
                } catch { fail(.storage); return }
                client = makeClient(configuration)
                pendingMethod = nil
                pendingIdentifier = nil
            }
            fail(issue)
        }
    }

    func resendCode() async {
        guard let method = pendingMethod, let contact = pendingIdentifier else { fail(.noPendingCode); return }
        await requestCode(method: method, identifier: contact)
    }

    /// Caller uses this verified session to invoke server-authorized commands.
    /// The server alone decides team admission, grants and owner authority.
    func authenticatedClient() async throws -> SupabaseClient {
        guard !isBusy else { throw AccountIssue.provider }
        guard let client,
              verifiedUserID != nil || (state == .error && sessionContextID != nil) else { throw AccountIssue.noVerifiedSession }
        isBusy = true
        defer { isBusy = false }
        do {
            try await acceptSession(from: client)
            return client
        } catch {
            var failure = error as? AccountIssue ?? .provider
            if knownSessionDenial(error) {
                sessionContextID = nil
                do { try invalidateOfflineActor() } catch { failure = .storage }
            }
            fail(failure)
            throw failure
        }
    }

    func signOut() async {
        guard !isBusy, let configuration else { return }
        isBusy = true
        defer { isBusy = false }
        sessionContextID = nil
        offlineClipActorID = nil
        do { try storage.store(key: offlineStampKey(configuration), value: JSONEncoder().encode(OfflineActorStamp(actorID: nil))) }
        catch { fail(.storage); return }
        let oldClient = client
        // The SDK captures the token, removes its local session, then requests
        // server revocation. Explicit deletion below also checks suppressed failures.
        var remoteFailure = false
        do { try await oldClient?.auth.signOut(scope: .local) }
        catch { remoteFailure = true }
        do {
            try storage.remove(key: sessionKey(configuration))
            try clearEmailLink(configuration)
        }
        catch { fail(.storage); return }
        client = nil
        pendingMethod = nil
        pendingIdentifier = nil
        issue = remoteFailure ? .signOutRemoteFailure : nil
        state = .signedOut
        client = makeClient(configuration)
    }

    private func acceptSession(from client: SupabaseClient, expectedEmail: String? = nil) async throws {
        guard let configuration else { throw AccountIssue.invalidConfiguration }
        _ = try read(key: sessionKey(configuration))
        let session = try await client.auth.session
        let verifiedUser = try await client.auth.user(jwt: session.accessToken)
        guard !verifiedUser.isAnonymous, verifiedUser.id == session.user.id,
              !session.accessToken.isEmpty, !session.refreshToken.isEmpty else { throw AccountIssue.noVerifiedSession }
        if let expectedEmail {
            guard verifiedUser.emailConfirmedAt != nil,
                  verifiedUser.email?.lowercased() == expectedEmail.lowercased() else { throw AccountIssue.invalidEmailLink }
        }
        do { try storage.store(key: sessionKey(configuration), value: JSONEncoder().encode(session)) }
        catch { throw AccountIssue.storage }
        let offlineID = verifiedUser.emailConfirmedAt != nil || verifiedUser.phoneConfirmedAt != nil ? verifiedUser.id : nil
        offlineClipActorID = nil
        do { try storage.store(key: offlineStampKey(configuration), value: JSONEncoder().encode(OfflineActorStamp(actorID: offlineID))) }
        catch { throw AccountIssue.storage }
        offlineClipActorID = offlineID
        issue = nil
        sessionContextID = verifiedUser.id
        state = .authenticated(verifiedUser.id)
    }

    private struct OfflineActorStamp: Codable { let actorID: UUID? }
    private func offlineStampKey(_ value: AccountConfiguration) -> String { "offline-actor.v1." + sessionKey(value) }
    private func invalidateOfflineActor() throws {
        offlineClipActorID = nil
        if let configuration {
            do { try storage.store(key: offlineStampKey(configuration), value: JSONEncoder().encode(OfflineActorStamp(actorID: nil))) }
            catch {
                // Either removal durably prevents restoring this revoked offline namespace.
                // Preserved clip bytes and all local game records remain untouched.
                try? storage.remove(key: sessionKey(configuration))
                try? storage.remove(key: offlineStampKey(configuration))
                throw AccountIssue.storage
            }
        }
    }
    private func knownSessionDenial(_ error: Error) -> Bool {
        if let error = error as? AuthError {
            switch error {
            case .api(_, let code, _, let response):
                return [401, 403, 404].contains(response.statusCode) || [.sessionNotFound, .sessionExpired, .refreshTokenNotFound, .refreshTokenAlreadyUsed, .userNotFound, .userBanned].contains(code)
            case .sessionMissing, .jwtVerificationFailed: return true
            default: return false
            }
        }
        return error as? AccountIssue == .noVerifiedSession
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

    private func emailLinkKey(_ value: AccountConfiguration) -> String { sessionKey(value) + ".email-link" }

    private func clearEmailLink(_ value: AccountConfiguration) throws {
        do {
            try storage.remove(key: emailLinkKey(value))
            try storage.remove(key: sessionKey(value) + "-code-verifier")
        } catch { throw AccountIssue.storage }
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
