import SwiftUI

struct AccountView: View {
    @Bindable var account: BackendAccount
    let openTeam: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var method: AccountMethod = .email
    @State private var identifier = ""
    @State private var code = ""
    @State private var serverURL = ""
    @State private var publicKey = ""
    @State private var environment: AccountConfiguration.Environment = .nonproduction
    @State private var authorizedServer = false
    @State private var confirmSignOut = false
    @FocusState private var focusedField: Field?

    private enum Field { case identifier, code, url, key }

    var body: some View {
        Form {
            Section {
                Label(statusText, systemImage: statusSymbol)
                if account.isBusy {
                    ProgressView("Contacting account server…")
                        .accessibilityLabel("Account request in progress")
                }
                if let issue = account.issue {
                    Label(issue.localizedDescription, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("account.error")
                }
                Text("Signing in verifies your account. Team access and permissions require server-confirmed admission and grants.")
                    .foregroundStyle(.secondary)
            }

            if let userID = account.verifiedUserID {
                Section("Verified account") {
                    Text(userID.uuidString)
                        .textSelection(.enabled)
                        .accessibilityLabel("Verified Auth account identifier, \(userID.uuidString)")
                    Button("Open Team", action: openTeam)
                    Text("Shared games, playbook and roster are in Team. Management controls require current server permission.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Check session again") { Task { await account.restore() } }
                        .frame(minHeight: 44)
                    Button("Sign out", role: .destructive) {
                        focusedField = nil
                        confirmSignOut = true
                    }
                    .frame(minHeight: 44)
                }
            } else if account.configuration != nil {
                Section("Sign in or recover your account") {
                    Picker("Contact method", selection: $method) {
                        Text("Email").tag(AccountMethod.email)
                        Text("Phone").tag(AccountMethod.phone)
                    }
                    TextField(method == .email ? "Email address" : "Phone with country code", text: $identifier)
                        .keyboardType(method == .email ? .emailAddress : .phonePad)
                        .textContentType(method == .email ? .emailAddress : .telephoneNumber)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .identifier)
                        .accessibilityIdentifier("account.identifier")
                    if method == .phone {
                        Text(account.configuration?.phoneDeliveryAllowed == true
                             ? "Local synthetic test codes only. The local Auth server must have external SMS disabled."
                             : "Phone signup is supported, but remote sending is disabled while zero-cost delivery is unverified.")
                        .foregroundStyle(.secondary)
                    } else {
                        Text("Open the sign-in email link on this device. If your authorized server sends a typed code, you can enter it below. Delivery must stay within the $0 budget.")
                            .foregroundStyle(.secondary)
                    }
                    Button(method == .email ? "Request sign-in email" : "Request code") {
                        focusedField = nil
                        code = ""
                        Task { await account.requestCode(method: method, identifier: identifier) }
                    }
                    .frame(minHeight: 44)
                    .disabled(identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (method == .phone && account.configuration?.phoneDeliveryAllowed != true))
                    .accessibilityIdentifier("account.requestCode")
                }

                if let pendingMethod = account.pendingMethod {
                    Section("Verify \(pendingMethod.rawValue) code") {
                        Text(pendingMethod == .email ? "Open the email link on this device, or enter a code if your server provided one. The server must allow this app’s email redirect." : "Use the code from your message. Requesting a code does not sign you in.")
                            .foregroundStyle(.secondary)
                        TextField("Verification code", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .focused($focusedField, equals: .code)
                            .accessibilityIdentifier("account.code")
                        Button("Verify code") {
                            focusedField = nil
                            Task { await account.verifyCode(code) }
                        }
                        .frame(minHeight: 44)
                        .disabled(code.isEmpty)
                        .accessibilityIdentifier("account.verifyCode")
                        Button("Request another code") {
                            focusedField = nil
                            Task { await account.resendCode() }
                        }
                        .frame(minHeight: 44)
                        Text("The server controls resend limits and expiry. Wait if it rejects a request, then retry.")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if account.state == .error {
                Section {
                    Button("Retry saved session") { Task { await account.restore() } }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("account.retrySession")
                    if account.configuration != nil {
                    Button("Sign out on this device", role: .destructive) { confirmSignOut = true }
                            .frame(minHeight: 44)
                    }
                }
            }

            if account.verifiedUserID == nil {
                Section("Account server") {
                    Picker("Environment", selection: $environment) {
                        Text("Nonproduction HTTPS").tag(AccountConfiguration.Environment.nonproduction)
                        Text("Local loopback test").tag(AccountConfiguration.Environment.localTest)
                    }
                    TextField("Server root URL", text: $serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .url)
                    SecureField("Publishable or anon key", text: $publicKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .key)
                    Toggle("I am authorized to use this nonproduction or local test server within the $0 budget", isOn: $authorizedServer)
                    Button("Save server on this device") {
                        focusedField = nil
                        Task {
                            await account.configure(url: serverURL, publicKey: publicKey, environment: environment)
                            if account.issue == nil { publicKey = "" }
                        }
                    }
                    .frame(minHeight: 44)
                    .disabled(!authorizedServer || serverURL.isEmpty || publicKey.isEmpty)
                    Text("Private configuration and sessions stay in this device's Keychain. Never enter a secret or service-role key. Local game records are not uploaded by signing in.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(account.isBusy)
        .navigationTitle("Account")
        .confirmationDialog("Sign out and close shared screens?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await account.signOut() } }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Unsent edits in shared screens will close. Saved local and shared records remain unchanged.")
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .task {
            await account.restoreIfNeeded()
            if let configuration = account.configuration {
                serverURL = configuration.url.absoluteString
                environment = configuration.environment
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, account.verifiedUserID != nil {
                Task { await account.restore() }
            }
        }
        .onChange(of: account.verifiedUserID) { _, id in
            if id != nil { identifier = ""; code = ""; publicKey = "" }
        }
    }

    private var statusText: String {
        switch account.state {
        case .unconfigured: "Account server not configured"
        case .signedOut: "Signed out"
        case .pendingVerification: "Sign-in requested; verification pending"
        case .authenticated: "Account verified"
        case .error: "Account request needs attention"
        }
    }

    private var statusSymbol: String {
        switch account.state {
        case .authenticated: "person.crop.circle.badge.checkmark"
        case .error: "exclamationmark.triangle"
        default: "person.crop.circle"
        }
    }
}
