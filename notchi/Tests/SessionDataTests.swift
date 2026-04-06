import CoreGraphics
import XCTest
@testable import notchi

@MainActor
final class SessionDataTests: XCTestCase {
    func testResolveXPositionReturnsCandidateWithinConfiguredRange() {
        let positions = stride(from: 0.05, through: 0.95, by: 0.15).map { CGFloat($0) }

        let resolved = SessionData.resolveXPositionForTesting(
            hash: 0,
            existingPositions: positions
        )

        XCTAssertGreaterThanOrEqual(resolved, CGFloat(0.05))
        XCTAssertLessThanOrEqual(resolved, CGFloat(0.95))
    }

    func testResolveXPositionFallsBackToMostSeparatedCandidateWhenAllCandidatesOverlap() {
        let positions = stride(from: 0.05, through: 0.95, by: 0.15).map { CGFloat($0) }

        let resolved = SessionData.resolveXPositionForTesting(
            hash: 0,
            existingPositions: positions
        )

        XCTAssertEqual(resolved, CGFloat(0.28), accuracy: 0.0001)
    }
}
