import AppKit

/// A desktop-level panel that displays Codex usage overview.
/// Unlike NotchPanel, this appears as a regular window on the desktop.
final class OverviewPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 450),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        level = .normal
        isMovableByWindowBackground = true
        title = "Codex Overview"
        center()

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        collectionBehavior = [.fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}