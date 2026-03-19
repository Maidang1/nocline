import XCTest
@testable import notchi

final class UsageBarViewTests: XCTestCase {
    func testPlaceholderShowsOnlyWhenTrulyDisconnected() {
        let view = UsageBarView(
            usage: nil,
            isLoading: false,
            error: nil,
            statusMessage: nil,
            isStale: false,
            recoveryAction: .none,
            isEnabled: false
        )

        XCTAssertTrue(view.shouldShowConnectPlaceholder)
    }

    func testPlaceholderDoesNotHideRealUsageState() {
        let view = UsageBarView(
            usage: QuotaPeriod(utilization: 42, resetDate: Date(timeIntervalSince1970: 4_102_444_800)),
            isLoading: false,
            error: nil,
            statusMessage: nil,
            isStale: false,
            recoveryAction: .none,
            isEnabled: false
        )

        XCTAssertFalse(view.shouldShowConnectPlaceholder)
    }

    func testPlaceholderDoesNotHideReconnectState() {
        let view = UsageBarView(
            usage: nil,
            isLoading: false,
            error: "Token expired",
            statusMessage: nil,
            isStale: false,
            recoveryAction: .reconnect,
            isEnabled: false
        )

        XCTAssertFalse(view.shouldShowConnectPlaceholder)
    }
}
