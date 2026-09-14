import XCTest
import CoreGraphics
@testable import PaneGridCore

final class AsynchronousAxesTests: XCTestCase {
    func testNeverStartsResizeWhilePositionAnimationIsPending() {
        var clock = 0.0
        var current = CGRect(x: 2882, y: 745, width: 950, height: 700)
        let target = CGRect(x: 1285, y: 745, width: 1270, height: 700)
        var pending: [(time: Double, frame: CGRect, position: Bool)] = []
        var concurrentAxes = 0
        let result = WindowFrameDriver.adjust(to: target, read: {
            pending.sort { $0.time < $1.time }
            while let next = pending.first, next.time <= clock { current = next.frame; pending.removeFirst() }
            return current
        }, setPosition: {
            pending.append((clock + 0.55, CGRect(origin: $0, size: current.size), true))
            return .accepted
        }, setSize: {
            if pending.contains(where: { $0.position }) { concurrentAxes += 1 }
            pending.append((clock + 0.18, CGRect(origin: current.origin, size: $0), false))
            return .accepted
        }, now: { clock }, wait: { clock += $0 })
        XCTAssertEqual(concurrentAxes, 0, "Two async operations can both capture stale geometry. Wait for the first axis before sending the second.")
        XCTAssertTrue(result.reachedTarget)
        clock += 1
        pending.sort { $0.time < $1.time }
        while let next = pending.first, next.time <= clock { current = next.frame; pending.removeFirst() }
        XCTAssertEqual(current, target, "No pending previous-axis completion may overwrite the final frame.")
    }

    func testBothAxesAreAsynchronousAndCaptureTheEntireOldFrame() {
        var clock = 0.0
        var current = CGRect(x: 2882, y: 745, width: 950, height: 700)
        let target = CGRect(x: 1285, y: 745, width: 1270, height: 700)
        var pending: [(time: Double, frame: CGRect)] = []
        let result = WindowFrameDriver.adjust(to: target, read: {
            while let next = pending.first, next.time <= clock { current = next.frame; pending.removeFirst() }
            return current
        }, setPosition: {
            pending.append((clock + 0.2, CGRect(origin: $0, size: current.size)))
            return .accepted
        }, setSize: {
            pending.append((clock + 0.2, CGRect(origin: current.origin, size: $0)))
            return .accepted
        }, now: { clock }, wait: { clock += $0 })
        XCTAssertTrue(result.reachedTarget, "Moving and resizing must be serialized, not just sent in a different order.")
        XCTAssertEqual(current, target)
        clock += 1
        while let next = pending.first, next.time <= clock { current = next.frame; pending.removeFirst() }
        XCTAssertEqual(current, target, "No stale pending write may reverse a completed arrangement.")
    }
}
