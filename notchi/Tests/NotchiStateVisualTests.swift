import XCTest
@testable import notchi

final class NotchiStateVisualTests: XCTestCase {
    func testWorkingStateCarriesHighestHaloAndActivityArc() {
        XCTAssertGreaterThan(NotchiState.working.haloOpacity, NotchiState.idle.haloOpacity)
        XCTAssertGreaterThan(NotchiState.working.activityArcOpacity, NotchiState.waiting.activityArcOpacity)
    }

    func testSleepingStateDimsAvatarPresentation() {
        XCTAssertLessThan(NotchiState.sleeping.shellOpacity, NotchiState.idle.shellOpacity)
        XCTAssertLessThan(NotchiState.sleeping.avatarScale, NotchiState.idle.avatarScale)
    }
}
