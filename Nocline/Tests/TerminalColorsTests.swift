import SwiftUI
import XCTest
@testable import Nocline

final class TerminalColorsTests: XCTestCase {
    func testLightPaletteUsesLightSurfacesAndDarkText() {
        let palette = TerminalColors.palette(for: .light)

        XCTAssertGreaterThan(palette.panelBackground.red, 0.9)
        XCTAssertLessThan(palette.primaryText.red, 0.1)
        XCTAssertGreaterThan(palette.primaryText.alpha, 0.8)
    }

    func testDarkPaletteUsesDarkSurfacesAndLightText() {
        let palette = TerminalColors.palette(for: .dark)

        XCTAssertLessThan(palette.panelBackground.red, 0.1)
        XCTAssertGreaterThan(palette.primaryText.red, 0.9)
        XCTAssertGreaterThan(palette.primaryText.alpha, 0.8)
    }

    func testCollapsedNotchBackgroundStaysPhysicalBlackAcrossThemes() {
        XCTAssertEqual(
            TerminalColors.palette(for: .light).collapsedNotchBackground,
            TerminalColors.palette(for: .dark).collapsedNotchBackground
        )
    }

    func testThemeSpecificUtilityTokensDifferBetweenLightAndDark() {
        XCTAssertNotEqual(
            TerminalColors.palette(for: .light).heatmapEmpty,
            TerminalColors.palette(for: .dark).heatmapEmpty
        )
        XCTAssertNotEqual(
            TerminalColors.palette(for: .light).border,
            TerminalColors.palette(for: .dark).border
        )
    }
}
