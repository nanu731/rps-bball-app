import XCTest
import Foundation
@testable import TeamStats

/// Opt-in setup for rendered acceptance against actual isolated local services.
/// This saves only a real Auth session; it never creates team authority or data.
@MainActor
final class UIAcceptanceSetupTests: XCTestCase {
    func testPrepareVerifiedLocalAccountForRenderedAcceptance() async throws {
        guard let text = ProcessInfo.processInfo.environment["TEAMSTATS_UI_ACCOUNT_FIXTURE"] else {
            throw XCTSkip("Explicit synthetic UI account fixture is not configured")
        }
        guard Bundle.main.bundleIdentifier == "com.narayanlekhi.TeamStats.UIAcceptance" else {
            throw UIAccountSetupIssue.unsafeHost
        }
        let fixture = try JSONDecoder().decode(UIAccountSetupFixture.self, from: Data(text.utf8))
        let configuration = try AccountConfiguration(url: fixture.apiRoot,
            publicKey: fixture.publishableKey, environment: .localTest)
        guard configuration.url.host == "127.0.0.1", configuration.url.scheme == "http",
              fixture.mailpitURL.host == "127.0.0.1", fixture.mailpitURL.scheme == "http",
              fixture.mailpitURL.path.isEmpty || fixture.mailpitURL.path == "/",
              fixture.mailpitURL.user == nil, fixture.mailpitURL.password == nil,
              fixture.mailpitURL.query == nil, fixture.mailpitURL.fragment == nil,
              fixture.syntheticEmail.hasSuffix("@example.invalid") else {
            throw UIAccountSetupIssue.unsafeFixture
        }

        // The guarded app host uses the same Keychain namespace as its next UI launch.
        // Refuse to overwrite any unrelated configuration even in the isolated app.
        let storage = SecureSessionStorage()
        if let existing = try storage.retrieve(key: "configuration.v1") {
            guard try JSONDecoder().decode(AccountConfiguration.self, from: existing) == configuration else {
                throw UIAccountSetupIssue.existingConfiguration
            }
        }
        let account = BackendAccount(storage: storage)
        await account.restoreIfNeeded()
        guard account.issue == nil else { throw UIAccountSetupIssue.restoreFailed }
        if let actor = account.verifiedUserID {
            guard actor == fixture.syntheticOwnerUUID else { throw UIAccountSetupIssue.existingConfiguration }
            _ = try await account.authenticatedClient()
            guard account.offlineClipActorID == actor else { throw UIAccountSetupIssue.restoreFailed }
            XCTContext.runActivity(named: "Reused matching session after actual Auth verification; no new challenge") { _ in }
            return
        }
        await account.configure(url: fixture.apiRoot, publicKey: fixture.publishableKey, environment: .localTest)
        guard account.issue == nil else { throw UIAccountSetupIssue.configurationFailed }

        // Remember prior message IDs so an old consumed link cannot be selected.
        let prior = try await messages(at: fixture.mailpitURL)
        let previousIDs = Set(prior.messages.map(\.id))
        await account.requestCode(method: .email, identifier: fixture.syntheticEmail)
        guard account.issue == nil, account.pendingMethod == .email else {
            throw UIAccountSetupIssue.requestFailed
        }
        var messageID: String?
        for _ in 0..<30 {
            let list = try await messages(at: fixture.mailpitURL)
            messageID = list.messages.first {
                !previousIDs.contains($0.id) && $0.to.contains { $0.address == fixture.syntheticEmail }
            }?.id
            if messageID != nil { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        // Mailpit uses an opaque alphanumeric message ID, not an Auth UUID.
        guard let messageID, !messageID.isEmpty, messageID.utf8.count <= 128,
              messageID.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else {
            throw UIAccountSetupIssue.messageUnavailable
        }
        let messageBytes = try await boundedResponse(fixture.mailpitURL.appendingPathComponent("api/v1/message/" + messageID))
        let message = try JSONDecoder().decode(UIAccountSetupMailBody.self, from: messageBytes)
        let html = message.html.replacingOccurrences(of: "&amp;", with: "&")
        let regex = try NSRegularExpression(pattern: "https?[^\\s\"<>]+")
        let links = regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap {
            Range($0.range, in: html).flatMap { URL(string: String(html[$0])) }
        }
        guard let link = links.first(where: {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "token" } == true
        }), link.host == configuration.url.host, link.port == configuration.url.port,
              link.scheme == configuration.url.scheme, link.path == "/auth/v1/verify",
              URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems?.first(where: {
                  $0.name == "redirect_to"
              })?.value == BackendAccount.emailRedirectURL.absoluteString else {
            throw UIAccountSetupIssue.unsafeRedirect
        }

        // Never open a custom-scheme URL ambiguously among installed app copies.
        let session = URLSession(configuration: .ephemeral, delegate: UIAccountSetupRedirectStopper(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let response: URLResponse
        do { (_, response) = try await session.data(from: link) }
        catch { throw UIAccountSetupIssue.redirectUnavailable }
        guard let http = response as? HTTPURLResponse, http.statusCode == 303,
              let callback = http.value(forHTTPHeaderField: "Location").flatMap(URL.init(string:)) else {
            throw UIAccountSetupIssue.redirectUnavailable
        }
        let verified = BackendAccount(storage: storage)
        await verified.handleEmailLink(callback)
        guard verified.issue == nil, verified.verifiedUserID == fixture.syntheticOwnerUUID else {
            throw UIAccountSetupIssue.verificationFailed
        }
        _ = try await verified.authenticatedClient()
        let restored = BackendAccount(storage: storage)
        await restored.restoreIfNeeded()
        guard restored.issue == nil, restored.verifiedUserID == fixture.syntheticOwnerUUID,
              restored.offlineClipActorID == fixture.syntheticOwnerUUID else {
            throw UIAccountSetupIssue.restoreFailed
        }
        XCTContext.runActivity(named: "Fresh actual local email PKCE exchange and persisted session verified") { _ in }
        // Do not sign out: the next cold app launch must restore this real session.
    }

    private func messages(at root: URL) async throws -> UIAccountSetupMailList {
        try JSONDecoder().decode(UIAccountSetupMailList.self,
            from: await boundedResponse(root.appendingPathComponent("api/v1/messages")))
    }

    private func boundedResponse(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (bytes, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, bytes.count < 1_048_576 else {
            throw UIAccountSetupIssue.messageUnavailable
        }
        return bytes
    }
}

private struct UIAccountSetupFixture: Decodable {
    let apiRoot: String
    let publishableKey: String
    let syntheticEmail: String
    let syntheticOwnerUUID: UUID
    let mailpitURL: URL
}
private enum UIAccountSetupIssue: Error {
    case unsafeHost, unsafeFixture, existingConfiguration, configurationFailed
    case requestFailed, messageUnavailable, unsafeRedirect, redirectUnavailable
    case verificationFailed, restoreFailed
}
private struct UIAccountSetupMailList: Decodable {
    let messages: [Message]
    struct Message: Decodable {
        let id: String
        let to: [Recipient]
        enum CodingKeys: String, CodingKey { case id = "ID", to = "To" }
    }
    struct Recipient: Decodable {
        let address: String
        enum CodingKeys: String, CodingKey { case address = "Address" }
    }
}
private struct UIAccountSetupMailBody: Decodable {
    let html: String
    enum CodingKeys: String, CodingKey { case html = "HTML" }
}
private final class UIAccountSetupRedirectStopper: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
