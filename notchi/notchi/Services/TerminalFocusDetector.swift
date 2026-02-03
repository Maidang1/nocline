import AppKit

struct TerminalFocusDetector {
    private static let terminalBundleIds: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "io.alacritty",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "co.zeit.hyper"
    ]

    static func isTerminalFocused() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        }
        return terminalBundleIds.contains(bundleId)
    }
}
