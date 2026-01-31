import SwiftUI

struct SettingsView: View {
    @State private var sessionKey = ""
    @State private var organizationId = ""
    @State private var showSessionKey = false
    @State private var saveStatus: SaveStatus = .idle
    var usageService: ClaudeUsageService = .shared

    private var hasStoredCredentials: Bool {
        KeychainManager.hasCredentials
    }

    private var isSessionKeyValid: Bool {
        sessionKey.hasPrefix("sk-ant-") || sessionKey.contains("sessionKey=sk-ant-")
    }

    var body: some View {
        Form {
            Section {
                credentialsSection
            } header: {
                Text("Claude Credentials")
            } footer: {
                instructionsText
            }

            Section {
                statusSection
            } header: {
                Text("Status")
            }

            Section {
                actionsSection
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 420)
        .onAppear {
            loadStoredCredentials()
        }
    }

    private var credentialsSection: some View {
        Group {
            LabeledContent("Organization ID") {
                TextField("org-id-here", text: $organizationId)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
            }

            LabeledContent("Cookie") {
                HStack {
                    if showSessionKey {
                        TextField("Paste full cookie string", text: $sessionKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("Paste full cookie string", text: $sessionKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button {
                        showSessionKey.toggle()
                    } label: {
                        Image(systemName: showSessionKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }
                .frame(width: 280)
            }
        }
    }

    private var instructionsText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("To get your credentials:")
                .fontWeight(.medium)
            Text("1. Open claude.ai → Settings → Usage")
            Text("2. Open DevTools (⌘⌥I) → Network tab")
            Text("3. Refresh page, find 'usage' request")
            Text("4. From URL: copy the org ID (e.g. 5babc6bf-d5da-...)")
            Text("5. From Cookie header: copy the ENTIRE cookie value")
                .foregroundColor(.orange)
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .foregroundColor(.secondary)

                if case .saved = saveStatus {
                    Spacer()
                    Text("Saved!")
                        .foregroundColor(.green)
                        .font(.caption)
                } else if case .error(let message) = saveStatus {
                    Spacer()
                    Text(message)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }

            if !sessionKey.isEmpty && !isSessionKeyValid {
                Text("Cookie should contain 'sessionKey=sk-ant-...'")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            if let error = usageService.error {
                Text("API Error: \(error)")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private var statusColor: Color {
        if !hasStoredCredentials {
            return .orange
        }
        if usageService.error != nil {
            return .red
        }
        if usageService.currentUsage != nil {
            return .green
        }
        return .yellow
    }

    private var statusText: String {
        if !hasStoredCredentials {
            return "Not configured"
        }
        if usageService.error != nil {
            return "Error"
        }
        if usageService.currentUsage != nil {
            return "Connected"
        }
        if usageService.isLoading {
            return "Checking..."
        }
        return "Credentials saved"
    }

    private var actionsSection: some View {
        HStack {
            Button("Save") {
                saveCredentials()
            }
            .disabled(sessionKey.isEmpty || organizationId.isEmpty)

            Button("Test") {
                testConnection()
            }
            .disabled(!hasStoredCredentials || usageService.isLoading)

            Button("Clear", role: .destructive) {
                clearCredentials()
            }
            .disabled(!hasStoredCredentials)
        }
    }

    private func testConnection() {
        Task {
            await usageService.fetchUsage()
        }
    }

    private func loadStoredCredentials() {
        if let orgId = KeychainManager.getOrganizationId() {
            organizationId = orgId
        }
        if let key = KeychainManager.getSessionKey() {
            sessionKey = key
        }
    }

    private func saveCredentials() {
        let orgSaved = KeychainManager.save(organizationId: organizationId)
        let keySaved = KeychainManager.save(sessionKey: sessionKey)

        if orgSaved && keySaved {
            saveStatus = .saved
            ClaudeUsageService.shared.startPolling()

            Task {
                try? await Task.sleep(for: .seconds(2))
                saveStatus = .idle
            }
        } else {
            saveStatus = .error("Failed to save to Keychain")
        }
    }

    private func clearCredentials() {
        KeychainManager.deleteCredentials()
        sessionKey = ""
        organizationId = ""
        ClaudeUsageService.shared.stopPolling()
        ClaudeUsageService.shared.currentUsage = nil
        saveStatus = .idle
    }
}

private enum SaveStatus {
    case idle
    case saved
    case error(String)
}
