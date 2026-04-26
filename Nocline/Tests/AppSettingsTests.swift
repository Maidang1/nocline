import XCTest
@testable import Nocline

final class AppSettingsTests: XCTestCase {
    private var previousAppearanceMode: Any?

    override func setUp() {
        super.setUp()
        previousAppearanceMode = UserDefaults.standard.object(forKey: AppSettings.appearanceModeKey)
        UserDefaults.standard.removeObject(forKey: AppSettings.appearanceModeKey)
    }

    override func tearDown() {
        if let previousAppearanceMode {
            UserDefaults.standard.set(previousAppearanceMode, forKey: AppSettings.appearanceModeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: AppSettings.appearanceModeKey)
        }
        super.tearDown()
    }

    func testAppearanceModeDefaultsToSystem() {
        XCTAssertEqual(AppSettings.appearanceMode, .system)
    }

    func testAppearanceModePersistsSelection() {
        AppSettings.appearanceMode = .light
        XCTAssertEqual(AppSettings.appearanceMode, .light)

        AppSettings.appearanceMode = .dark
        XCTAssertEqual(AppSettings.appearanceMode, .dark)
    }

    func testAppearanceModeFallsBackToSystemForInvalidRawValue() {
        UserDefaults.standard.set("sepia", forKey: AppSettings.appearanceModeKey)

        XCTAssertEqual(AppSettings.appearanceMode, .system)
    }
}
