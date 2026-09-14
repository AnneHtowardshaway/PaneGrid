import XCTest
import CoreGraphics
@testable import PaneGridCore

final class WindowFrameDriverTests: XCTestCase {
    func testDeferredSizeMustNotPutAnAlreadyResizedWindowBackAtItsOldOrigin() {
        var clock = 0.0
        var actual = CGRect(x: 120, y: 170, width: 1100, height: 800)
        let target = CGRect(x: 1285, y: 38, width: 1270, height: 699)
        var pending: (at: Double, frame: CGRect)?
        var sizeRequests = 0
        let result = WindowFrameDriver.adjust(to: target, read: {
            if let due = pending, clock >= due.at { actual = due.frame; pending = nil }
            return actual
        }, setPosition: { actual.origin = $0; return .accepted }, setSize: {
            sizeRequests += 1
            // Like real frame-based AX implementations: an async size change captures its current origin.
            pending = (clock + 0.08, CGRect(origin: actual.origin, size: $0))
            return .accepted
        }, now: { clock }, wait: { clock += $0 })
        XCTAssertTrue(result.reachedTarget, "The size is correct but stale origin must not cause a rollback.")
        XCTAssertEqual(actual, target)
        XCTAssertEqual(sizeRequests, 1, "Do not resend size to repair position.")
    }

    func testGrowingFromBottomEdgeMovesFirstInsteadOfClippingTheNewHeight() {
        var clock = 0.0
        var actual = CGRect(x: 2500, y: 1453, width: 1269, height: 699)
        let target = CGRect(x: 1320, y: 680, width: 1200, height: 800)
        var sizeRequests = 0
        var positionRequests = 0
        let result = WindowFrameDriver.adjust(to: target, read: { actual }, setPosition: {
            positionRequests += 1
            actual.origin = $0; return .accepted
        }, setSize: {
            sizeRequests += 1
            // Observed with an actual empty Code window: the bottom edge clips a size-first request.
            actual.size = CGSize(width: $0.width, height: min($0.height, 2160 - actual.minY))
            return .accepted
        }, now: { clock }, wait: { clock += $0 })
        XCTAssertTrue(result.reachedTarget)
        XCTAssertEqual(actual, target)
        XCTAssertLessThan(clock, 0.5, "A position-dependent cap is not a real minimum and needs no 1.2s retry.")
        XCTAssertEqual(sizeRequests, 1, "Only one size request after moving clear of the edge.")
        XCTAssertEqual(positionRequests, 1)
        XCTAssertEqual(result.writes, 2, "The driver now counts actual axis writes, not combined frame requests.")
    }

    func testPositionOnlyMoveNeverReissuesAnAlreadyCorrectSize() {
        var clock = 0.0
        let target = CGRect(x: 8, y: 38, width: 1269, height: 699)
        var actual = target.offsetBy(dx: 800, dy: 600)
        var sizeRequests = 0
        let result = WindowFrameDriver.adjust(to: target, read: { actual }, setPosition: {
            actual.origin = $0; return .accepted
        }, setSize: { _ in sizeRequests += 1; return .accepted }, now: { clock }, wait: { clock += $0 })
        XCTAssertTrue(result.reachedTarget)
        XCTAssertEqual(sizeRequests, 0)
    }
}
