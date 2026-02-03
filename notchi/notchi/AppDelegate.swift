import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchPanel: NotchPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        setupNotchWindow()
        observeScreenChanges()
        startHookServices()
        startUsageService()
        observeSettingsRequest()
    }

    private func startHookServices() {
        HookInstaller.installIfNeeded()
        SocketServer.shared.start { event in
            Task { @MainActor in
                NotchiStateMachine.shared.handleEvent(event)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupNotchWindow() {
        let screen = NSScreen.builtInOrMain
        NotchPanelManager.shared.updateGeometry(for: screen)

        let screenFrame = screen.frame
        let windowHeight: CGFloat = 500
        let frame = NSRect(
            x: screenFrame.origin.x,
            y: screenFrame.maxY - windowHeight,
            width: screenFrame.width,
            height: windowHeight
        )

        let panel = NotchPanel(frame: frame)
        NotchPanelManager.shared.panel = panel

        let contentView = NotchContentView()
        let hostingView = NSHostingView(rootView: contentView)
        panel.contentView = hostingView
        panel.orderFrontRegardless()

        self.notchPanel = panel
    }

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(repositionWindow),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func repositionWindow() {
        guard let panel = notchPanel else { return }
        let screen = NSScreen.builtInOrMain

        // Recalculate notch geometry for new screen config
        NotchPanelManager.shared.updateGeometry(for: screen)

        let screenFrame = screen.frame
        let windowHeight: CGFloat = 500
        let frame = NSRect(
            x: screenFrame.origin.x,
            y: screenFrame.maxY - windowHeight,
            width: screenFrame.width,
            height: windowHeight
        )
        panel.setFrame(frame, display: true)
    }

    private func startUsageService() {
        ClaudeUsageService.shared.startPolling()
    }

    private func observeSettingsRequest() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettings),
            name: .notchiOpenSettings,
            object: nil
        )
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.showSettings()
    }
}
