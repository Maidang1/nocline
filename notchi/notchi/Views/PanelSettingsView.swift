import ServiceManagement
import SwiftUI

struct PanelSettingsView: View {
    @AppStorage(AppSettings.hideSpriteWhenIdleKey) private var hideSpriteWhenIdle = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var codexHooksInstalled = CodexHookInstaller.isInstalled()
    @State private var codexHooksError = false
    @ObservedObject private var updateManager = UpdateManager.shared
    @ObservedObject private var codexUsageService = CodexUsageService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
                    systemSection
                    Divider().background(Color.white.opacity(0.08))
                    aboutSection
                }
                .padding(.top, SettingsLayout.topPadding)
            }
            .scrollIndicators(.hidden)

            Spacer()

            quitSection
        }
        .padding(.horizontal, SettingsLayout.panelHorizontalPadding)
        .padding(.top, SettingsLayout.topPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await codexUsageService.refreshIfNeeded()
        }
    }

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
            ScreenPickerRow(screenSelector: ScreenSelector.shared)

            SoundPickerView()

            Button(action: toggleLaunchAtLogin) {
                SettingsRowView(icon: "power", title: "Launch at Login") {
                    ToggleSwitch(isOn: launchAtLogin)
                }
            }
            .buttonStyle(.plain)

            Button(action: toggleHideSpriteWhenIdle) {
                SettingsRowView(icon: "pip.exit", title: "Hide Sprite When Idle") {
                    ToggleSwitch(isOn: hideSpriteWhenIdle)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
            Button(action: installCodexHooksIfNeeded) {
                SettingsRowView(icon: "terminal", title: "Codex CLI Hooks") {
                    hookStatusBadge(installed: codexHooksInstalled, hasError: codexHooksError)
                }
            }
            .buttonStyle(.plain)

            codexUsageSection

            Button(action: handleUpdatesAction) {
                SettingsRowView(icon: "arrow.triangle.2.circlepath", title: "Check for Updates") {
                    updateStatusView
                }
            }
            .buttonStyle(.plain)

            Button(action: openGitHubRepo) {
                SettingsRowView(icon: "star", title: "Star on GitHub") {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10))
                        .foregroundColor(TerminalColors.dimmedText)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var codexUsageSection: some View {
        let presentation = CodexUsageSectionPresentation.make(from: codexUsageService.state)

        return VStack(alignment: .leading, spacing: SettingsLayout.usageCardSpacing) {
            SettingsRowView(icon: "gauge.with.dots.needle.33percent", title: "Codex Usage") {
                HStack(spacing: 8) {
                    Button(action: refreshCodexUsage) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(
                                codexUsageService.state == .loading
                                    ? TerminalColors.dimmedText
                                    : TerminalColors.secondaryText
                            )
                            .frame(
                                width: SettingsLayout.usageRefreshButtonSize,
                                height: SettingsLayout.usageRefreshButtonSize
                            )
                            .background(Color.white.opacity(0.04))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(codexUsageService.state == .loading)

                    statusBadge(
                        presentation.statusText,
                        color: usageStatusColor(for: codexUsageService.state),
                        fixedWidth: false
                    )
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(presentation.rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 {
                        Divider().background(Color.white.opacity(0.06))
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(TerminalColors.primaryText)

                            HStack(spacing: 6) {
                                Text(row.detailText)
                                    .font(.system(size: 10))
                                    .foregroundColor(TerminalColors.dimmedText)

                                if let badgeText = row.badgeText {
                                    Text(badgeText)
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(TerminalColors.amber)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(TerminalColors.amber.opacity(0.14))
                                        .cornerRadius(4)
                                }
                            }
                        }

                        Spacer()

                        Text(row.remainingText)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(TerminalColors.primaryText)
                    }
                    .padding(.horizontal, SettingsLayout.usageCardHorizontalPadding)
                    .padding(.vertical, SettingsLayout.usageCardVerticalPadding)
                }
            }
            .background(TerminalColors.subtleBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.leading, 28)
        }
    }

    private func openGitHubRepo() {
        NSWorkspace.shared.open(URL(string: "https://github.com/sk-ruban/notchi")!)
    }

    private func openLatestReleasePage() {
        NSWorkspace.shared.open(URL(string: "https://github.com/sk-ruban/notchi/releases/latest")!)
    }

    private var quitSection: some View {
        Button(action: {
            NSApplication.shared.terminate(nil)
        }) {
            HStack {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 13))
                Text("Quit Notchi")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(TerminalColors.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, SettingsLayout.quitButtonVerticalPadding)
            .padding(.horizontal, SettingsLayout.quitButtonHorizontalPadding)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(TerminalColors.red.opacity(0.1))
                    .padding(.horizontal, -SettingsLayout.quitButtonHorizontalPadding)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            print("Failed to toggle launch at login: \(error)")
        }
    }

    private func toggleHideSpriteWhenIdle() {
        hideSpriteWhenIdle.toggle()
    }

    private func handleUpdatesAction() {
        if case .upToDate = updateManager.state {
            openLatestReleasePage()
        } else {
            updateManager.checkForUpdates()
        }
    }

    private func refreshCodexUsage() {
        Task {
            await codexUsageService.refresh()
        }
    }

    private func usageStatusColor(for state: CodexUsageState) -> Color {
        switch state {
        case .idle, .loading:
            return TerminalColors.amber
        case .loaded(let snapshot):
            return snapshot.isFromCache ? TerminalColors.amber : TerminalColors.accent
        case .unavailable:
            return TerminalColors.red
        }
    }

    private func installCodexHooksIfNeeded() {
        guard !codexHooksInstalled else { return }
        codexHooksError = false
        let success = CodexHookInstaller.installIfNeeded()
        if success {
            codexHooksInstalled = CodexHookInstaller.isInstalled()
        } else {
            codexHooksError = true
        }
    }

    @ViewBuilder
    private func hookStatusBadge(installed: Bool, hasError: Bool) -> some View {
        if hasError {
            statusBadge("Error", color: TerminalColors.red)
        } else if installed {
            statusBadge("Ready", color: TerminalColors.accent)
        } else {
            statusBadge("Setup Needed", color: TerminalColors.amber)
        }
    }

    private func statusBadge(_ text: String, color: Color, fixedWidth: Bool = true) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .cornerRadius(4)
            .frame(maxWidth: fixedWidth ? 160 : nil, alignment: .trailing)
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch updateManager.state {
        case .checking:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Checking...")
                    .font(.system(size: 10))
                    .foregroundColor(TerminalColors.dimmedText)
            }
        case .upToDate:
            statusBadge("Up to date", color: TerminalColors.accent)
        case .updateAvailable:
            statusBadge("Update available", color: TerminalColors.amber)
        case .downloading:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Downloading...")
                    .font(.system(size: 10))
                    .foregroundColor(TerminalColors.dimmedText)
            }
        case .readyToInstall:
            statusBadge("Ready to install", color: TerminalColors.accent)
        case .error(let failure):
            statusBadge(failure.label, color: TerminalColors.red)
        case .idle:
            Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                .font(.system(size: 10))
                .foregroundColor(TerminalColors.dimmedText)
        }
    }
}

struct SettingsRowView<Trailing: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(TerminalColors.secondaryText)
                .frame(width: 20)

            Text(title)
                .font(.system(size: 12))
                .foregroundColor(TerminalColors.primaryText)

            Spacer()

            trailing()
        }
        .padding(.vertical, SettingsLayout.rowVerticalPadding)
        .contentShape(Rectangle())
    }
}

struct ToggleSwitch: View {
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? TerminalColors.accent : Color.white.opacity(0.15))
                .frame(width: 32, height: 18)

            Circle()
                .fill(Color.white)
                .frame(width: 14, height: 14)
                .padding(2)
        }
        .animation(.easeInOut(duration: 0.15), value: isOn)
    }
}

#Preview {
    PanelSettingsView()
        .frame(width: 402, height: 400)
        .background(Color.black)
}
