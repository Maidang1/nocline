import SwiftUI

struct TerminalColors {
    static let accent = Color(red: 0.23, green: 0.55, blue: 0.98)
    static let accentSoft = Color(red: 0.39, green: 0.68, blue: 1.0)
    static let accentMuted = Color(red: 0.15, green: 0.24, blue: 0.39)
    static let accentGlow = Color(red: 0.38, green: 0.67, blue: 1.0)
    static let green = Color(red: 0.34, green: 0.78, blue: 0.56)
    static let amber = Color(red: 0.96, green: 0.74, blue: 0.32)
    static let red = Color(red: 0.95, green: 0.41, blue: 0.42)
    static let planMode = Color(red: 0.38, green: 0.67, blue: 1.0)
    static let acceptEdits = Color(red: 0.58, green: 0.67, blue: 0.96)

    static let shellBackground = Color(red: 0.03, green: 0.04, blue: 0.06)
    static let panelBackground = Color(red: 0.07, green: 0.08, blue: 0.11)
    static let elevatedSurface = Color(red: 0.10, green: 0.11, blue: 0.14)
    static let insetSurface = Color(red: 0.12, green: 0.13, blue: 0.17)
    static let border = Color.white.opacity(0.08)

    static let primaryText = Color.white.opacity(0.9)
    static let secondaryText = Color.white.opacity(0.58)
    static let dimmedText = Color.white.opacity(0.34)
    static let subtleBackground = elevatedSurface
    static let hoverBackground = Color.white.opacity(0.06)
}
