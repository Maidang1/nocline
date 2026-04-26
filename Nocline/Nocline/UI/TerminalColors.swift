import AppKit
import SwiftUI

struct TerminalColorValue: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var nsColor: NSColor {
        NSColor(
            calibratedRed: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    func opacity(_ alpha: Double) -> TerminalColorValue {
        TerminalColorValue(red: red, green: green, blue: blue, alpha: alpha)
    }
}

struct TerminalColorPalette: Equatable {
    let accent: TerminalColorValue
    let accentSoft: TerminalColorValue
    let accentMuted: TerminalColorValue
    let accentGlow: TerminalColorValue
    let green: TerminalColorValue
    let amber: TerminalColorValue
    let red: TerminalColorValue
    let planMode: TerminalColorValue
    let acceptEdits: TerminalColorValue

    let shellBackground: TerminalColorValue
    let collapsedNotchBackground: TerminalColorValue
    let panelBackground: TerminalColorValue
    let elevatedSurface: TerminalColorValue
    let insetSurface: TerminalColorValue
    let border: TerminalColorValue
    let primaryText: TerminalColorValue
    let secondaryText: TerminalColorValue
    let dimmedText: TerminalColorValue
    let hoverBackground: TerminalColorValue
    let controlBackground: TerminalColorValue
    let toggleOffBackground: TerminalColorValue
    let toggleThumb: TerminalColorValue
    let codeBlockBackground: TerminalColorValue
    let codeBlockText: TerminalColorValue
    let heatmapEmpty: TerminalColorValue
    let shadow: TerminalColorValue
    let promptBubbleText: TerminalColorValue
    let promptBubbleStart: TerminalColorValue
    let promptBubbleEnd: TerminalColorValue
}

struct TerminalColors {
    static let darkPalette = TerminalColorPalette(
        accent: TerminalColorValue(red: 0.23, green: 0.55, blue: 0.98),
        accentSoft: TerminalColorValue(red: 0.39, green: 0.68, blue: 1.0),
        accentMuted: TerminalColorValue(red: 0.15, green: 0.24, blue: 0.39),
        accentGlow: TerminalColorValue(red: 0.38, green: 0.67, blue: 1.0),
        green: TerminalColorValue(red: 0.34, green: 0.78, blue: 0.56),
        amber: TerminalColorValue(red: 0.96, green: 0.74, blue: 0.32),
        red: TerminalColorValue(red: 0.95, green: 0.41, blue: 0.42),
        planMode: TerminalColorValue(red: 0.38, green: 0.67, blue: 1.0),
        acceptEdits: TerminalColorValue(red: 0.58, green: 0.67, blue: 0.96),
        shellBackground: TerminalColorValue(red: 0.03, green: 0.04, blue: 0.06),
        collapsedNotchBackground: TerminalColorValue(red: 0.01, green: 0.01, blue: 0.012),
        panelBackground: TerminalColorValue(red: 0.07, green: 0.08, blue: 0.11),
        elevatedSurface: TerminalColorValue(red: 0.10, green: 0.11, blue: 0.14),
        insetSurface: TerminalColorValue(red: 0.12, green: 0.13, blue: 0.17),
        border: TerminalColorValue(red: 1, green: 1, blue: 1, alpha: 0.08),
        primaryText: TerminalColorValue(red: 1, green: 1, blue: 1, alpha: 0.9),
        secondaryText: TerminalColorValue(red: 1, green: 1, blue: 1, alpha: 0.58),
        dimmedText: TerminalColorValue(red: 1, green: 1, blue: 1, alpha: 0.34),
        hoverBackground: TerminalColorValue(red: 1, green: 1, blue: 1, alpha: 0.06),
        controlBackground: TerminalColorValue(red: 1, green: 1, blue: 1, alpha: 0.04),
        toggleOffBackground: TerminalColorValue(red: 1, green: 1, blue: 1, alpha: 0.15),
        toggleThumb: TerminalColorValue(red: 1, green: 1, blue: 1),
        codeBlockBackground: TerminalColorValue(red: 1, green: 1, blue: 1, alpha: 0.08),
        codeBlockText: TerminalColorValue(red: 1, green: 1, blue: 1, alpha: 0.85),
        heatmapEmpty: TerminalColorValue(red: 1, green: 1, blue: 1, alpha: 0.045),
        shadow: TerminalColorValue(red: 0, green: 0, blue: 0, alpha: 0.55),
        promptBubbleText: TerminalColorValue(red: 1, green: 1, blue: 1),
        promptBubbleStart: TerminalColorValue(red: 0.15, green: 0.24, blue: 0.39),
        promptBubbleEnd: TerminalColorValue(red: 0.10, green: 0.11, blue: 0.14)
    )

    static let lightPalette = TerminalColorPalette(
        accent: TerminalColorValue(red: 0.13, green: 0.38, blue: 0.82),
        accentSoft: TerminalColorValue(red: 0.20, green: 0.48, blue: 0.92),
        accentMuted: TerminalColorValue(red: 0.84, green: 0.90, blue: 0.99),
        accentGlow: TerminalColorValue(red: 0.28, green: 0.52, blue: 0.92),
        green: TerminalColorValue(red: 0.12, green: 0.55, blue: 0.33),
        amber: TerminalColorValue(red: 0.75, green: 0.47, blue: 0.10),
        red: TerminalColorValue(red: 0.76, green: 0.22, blue: 0.24),
        planMode: TerminalColorValue(red: 0.13, green: 0.38, blue: 0.82),
        acceptEdits: TerminalColorValue(red: 0.35, green: 0.43, blue: 0.82),
        shellBackground: TerminalColorValue(red: 0.95, green: 0.96, blue: 0.98),
        collapsedNotchBackground: TerminalColorValue(red: 0.01, green: 0.01, blue: 0.012),
        panelBackground: TerminalColorValue(red: 0.93, green: 0.94, blue: 0.96),
        elevatedSurface: TerminalColorValue(red: 0.985, green: 0.988, blue: 0.992),
        insetSurface: TerminalColorValue(red: 0.88, green: 0.90, blue: 0.94),
        border: TerminalColorValue(red: 0.06, green: 0.08, blue: 0.12, alpha: 0.10),
        primaryText: TerminalColorValue(red: 0.06, green: 0.08, blue: 0.12, alpha: 0.90),
        secondaryText: TerminalColorValue(red: 0.06, green: 0.08, blue: 0.12, alpha: 0.58),
        dimmedText: TerminalColorValue(red: 0.06, green: 0.08, blue: 0.12, alpha: 0.36),
        hoverBackground: TerminalColorValue(red: 0.06, green: 0.08, blue: 0.12, alpha: 0.055),
        controlBackground: TerminalColorValue(red: 0.06, green: 0.08, blue: 0.12, alpha: 0.045),
        toggleOffBackground: TerminalColorValue(red: 0.06, green: 0.08, blue: 0.12, alpha: 0.16),
        toggleThumb: TerminalColorValue(red: 1, green: 1, blue: 1),
        codeBlockBackground: TerminalColorValue(red: 0.06, green: 0.08, blue: 0.12, alpha: 0.07),
        codeBlockText: TerminalColorValue(red: 0.06, green: 0.08, blue: 0.12, alpha: 0.86),
        heatmapEmpty: TerminalColorValue(red: 0.06, green: 0.08, blue: 0.12, alpha: 0.05),
        shadow: TerminalColorValue(red: 0.06, green: 0.08, blue: 0.12, alpha: 0.18),
        promptBubbleText: TerminalColorValue(red: 1, green: 1, blue: 1),
        promptBubbleStart: TerminalColorValue(red: 0.13, green: 0.38, blue: 0.82),
        promptBubbleEnd: TerminalColorValue(red: 0.20, green: 0.48, blue: 0.92)
    )

    static func palette(for colorScheme: ColorScheme) -> TerminalColorPalette {
        colorScheme == .dark ? darkPalette : lightPalette
    }

    static let accent = dynamicColor(\.accent)
    static let accentSoft = dynamicColor(\.accentSoft)
    static let accentMuted = dynamicColor(\.accentMuted)
    static let accentGlow = dynamicColor(\.accentGlow)
    static let green = dynamicColor(\.green)
    static let amber = dynamicColor(\.amber)
    static let red = dynamicColor(\.red)
    static let planMode = dynamicColor(\.planMode)
    static let acceptEdits = dynamicColor(\.acceptEdits)

    static let shellBackground = dynamicColor(\.shellBackground)
    static let collapsedNotchBackground = dynamicColor(\.collapsedNotchBackground)
    static let panelBackground = dynamicColor(\.panelBackground)
    static let elevatedSurface = dynamicColor(\.elevatedSurface)
    static let insetSurface = dynamicColor(\.insetSurface)
    static let border = dynamicColor(\.border)
    static let primaryText = dynamicColor(\.primaryText)
    static let secondaryText = dynamicColor(\.secondaryText)
    static let dimmedText = dynamicColor(\.dimmedText)
    static let subtleBackground = elevatedSurface
    static let hoverBackground = dynamicColor(\.hoverBackground)
    static let controlBackground = dynamicColor(\.controlBackground)
    static let toggleOffBackground = dynamicColor(\.toggleOffBackground)
    static let toggleThumb = dynamicColor(\.toggleThumb)
    static let codeBlockBackground = dynamicColor(\.codeBlockBackground)
    static let codeBlockText = dynamicColor(\.codeBlockText)
    static let heatmapEmpty = dynamicColor(\.heatmapEmpty)
    static let shadow = dynamicColor(\.shadow)
    static let promptBubbleText = dynamicColor(\.promptBubbleText)
    static let promptBubbleStart = dynamicColor(\.promptBubbleStart)
    static let promptBubbleEnd = dynamicColor(\.promptBubbleEnd)

    private static func dynamicColor(_ keyPath: KeyPath<TerminalColorPalette, TerminalColorValue>) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let bestMatch = appearance.bestMatch(from: [.darkAqua, .aqua])
            let palette = bestMatch == .darkAqua ? darkPalette : lightPalette
            return palette[keyPath: keyPath].nsColor
        })
    }
}
