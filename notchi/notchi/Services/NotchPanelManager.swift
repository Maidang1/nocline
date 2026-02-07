import AppKit

@MainActor
@Observable
final class NotchPanelManager {
    static let shared = NotchPanelManager()

    private(set) var isExpanded = false
    private(set) var isPinned = false
    private(set) var notchSize: CGSize = .zero
    weak var panel: NSPanel?

    private var notchRect: CGRect = .zero
    private var panelRect: CGRect = .zero
    private var screenHeight: CGFloat = 0

    private var mouseDownMonitor: EventMonitor?
    private var mouseMoveMonitor: EventMonitor?

    private init() {
        setupEventMonitors()
    }

    func updateGeometry(for screen: NSScreen) {
        let newNotchSize = screen.notchSize
        let screenFrame = screen.frame

        notchSize = newNotchSize

        let notchCenterX = screenFrame.origin.x + screenFrame.width / 2
        let sideWidth = max(0, newNotchSize.height - 12) + 24
        let notchTotalWidth = newNotchSize.width + sideWidth

        notchRect = CGRect(
            x: notchCenterX - notchTotalWidth / 2,
            y: screenFrame.maxY - newNotchSize.height,
            width: notchTotalWidth,
            height: newNotchSize.height
        )

        let panelSize = NotchConstants.expandedPanelSize
        let panelWidth = panelSize.width + NotchConstants.expandedPanelHorizontalPadding
        panelRect = CGRect(
            x: notchCenterX - panelWidth / 2,
            y: screenFrame.maxY - panelSize.height,
            width: panelWidth,
            height: panelSize.height
        )

        screenHeight = screenFrame.height
    }

    private func setupEventMonitors() {
        mouseDownMonitor = EventMonitor(mask: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseDown()
            }
        }
        mouseDownMonitor?.start()

        mouseMoveMonitor = EventMonitor(mask: .mouseMoved) { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseMove()
            }
        }
        mouseMoveMonitor?.start()
    }

    private func handleMouseDown() {
        let location = NSEvent.mouseLocation

        if isExpanded {
            // Check if click is outside the panel (unless pinned)
            if !isPinned && !panelRect.contains(location) {
                collapse()
            }
        } else {
            // Check if click is on the notch area
            if notchRect.contains(location) {
                expand()
            }
        }
    }

    func expand() {
        guard !isExpanded else { return }
        isExpanded = true
        panel?.ignoresMouseEvents = isPinned
    }

    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        isPinned = false
        panel?.ignoresMouseEvents = true
    }

    func toggle() {
        if isExpanded {
            collapse()
        } else {
            expand()
        }
    }

    func togglePin() {
        isPinned.toggle()
        panel?.ignoresMouseEvents = isPinned
    }

    private func handleMouseMove() {
        guard isExpanded && isPinned else { return }

        let location = NSEvent.mouseLocation
        let mouseInPanel = panelRect.contains(location)

        panel?.ignoresMouseEvents = !mouseInPanel
    }
}
