import AppKit
import SwiftUI

final class OverviewWindowController {
    static let shared = OverviewWindowController()

    private var panel: OverviewPanel?
    private var hostingView: NSHostingView<NoclineAppearanceRoot<OverviewView>>?

    private init() {}

    func show() {
        if panel == nil {
            let panel = OverviewPanel()
            let hostingView = NSHostingView(rootView: NoclineAppearanceRoot {
                OverviewView()
            })
            panel.contentView = hostingView
            hostingView.frame = NSRect(x: 0, y: 0, width: 500, height: 450)
            self.panel = panel
            self.hostingView = hostingView
        }

        panel?.center()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }
}
