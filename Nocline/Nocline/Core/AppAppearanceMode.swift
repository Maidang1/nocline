import AppKit
import Combine
import SwiftUI

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var nsAppearanceName: NSAppearance.Name? {
        switch self {
        case .system:
            return nil
        case .light:
            return .aqua
        case .dark:
            return .darkAqua
        }
    }

    @MainActor
    func applyToApplication() {
        if let nsAppearanceName {
            NSApp.appearance = NSAppearance(named: nsAppearanceName)
        } else {
            NSApp.appearance = nil
        }
    }
}

extension Notification.Name {
    static let noclineAppearanceModeDidChange = Notification.Name("noclineAppearanceModeDidChange")
}

@MainActor
final class AppearanceSettings: ObservableObject {
    static let shared = AppearanceSettings()

    @Published private(set) var mode: AppAppearanceMode

    private var observer: NSObjectProtocol?

    private init() {
        mode = AppSettings.appearanceMode
        mode.applyToApplication()

        observer = NotificationCenter.default.addObserver(
            forName: .noclineAppearanceModeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshFromDefaults()
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func setMode(_ newMode: AppAppearanceMode) {
        guard mode != newMode else { return }
        AppSettings.appearanceMode = newMode
    }

    private func refreshFromDefaults() {
        let newMode = AppSettings.appearanceMode
        mode = newMode
        newMode.applyToApplication()
    }
}

struct NoclineAppearanceRoot<Content: View>: View {
    @ObservedObject private var appearanceSettings = AppearanceSettings.shared
    let content: () -> Content

    var body: some View {
        content()
            .preferredColorScheme(appearanceSettings.mode.colorScheme)
    }
}
