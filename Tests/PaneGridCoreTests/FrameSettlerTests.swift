import XCTest
import CoreGraphics
@testable import PaneGridCore

final class FrameSettlerTests: XCTestCase {
    let original = CGRect(x: 100, y: 100, width: 1200, height: 800)
    let target = CGRect(x: 8, y: 38, width: 842.5, height: 693)

    func testLegacyImmediateRetriesRejectDelayedSuccessButSettlerDoesNot() {
        var legacyClock = 0.0
        var legacyAccepted = false
        for attempt in 0..<3 {
            if attempt > 0 { legacyClock += 0.035 }
            if legacyClock >= 0.2 { legacyAccepted = true; break }
        }
        XCTAssertFalse(legacyAccepted, "The original 70ms loop must fail this 200ms server response.")
        var clock = 0.0
        var requestedAt: Double?
        let result = FrameSettler.adjust(to: target, read: {
            requestedAt.map { clock - $0 >= 0.2 } == true ? self.target : self.original
        }, write: {
            if requestedAt == nil { requestedAt = clock }
            return .accepted
        }, now: { clock }, wait: { clock += $0 })
        XCTAssertTrue(result.reachedTarget)
        XCTAssertLessThanOrEqual(result.writes, 2)
        XCTAssertGreaterThanOrEqual(clock, 0.32)
        XCTAssertLessThan(clock, 1.2)
    }

    func testLostSetterReplyDoesNotOverrideVerifiedActualFrame() {
        var clock = 0.0
        var didWrite = false
        let result = FrameSettler.adjust(to: target, read: { didWrite ? self.target : self.original },
                                        write: { didWrite = true; return .retryable }, now: { clock }, wait: { clock += $0 })
        XCTAssertTrue(result.reachedTarget)
        XCTAssertEqual(result.writes, 1)
    }

    func testAcceptedRetriesDoNotKeepPostponingAValidPresetChange() {
        var clock = 0.0
        var completesAt: Double?
        // Real apps may coalesce resize requests: a repeated size request restarts their work.
        // Start in the previous preset, then request the new (smaller) portion without an Undo.
        let result = FrameSettler.adjust(to: target, read: {
            completesAt.map { clock >= $0 } == true ? self.target : self.original
        }, write: {
            completesAt = clock + 0.55
            return .accepted
        }, now: { clock }, wait: { clock += $0 })
        XCTAssertTrue(result.reachedTarget, "Do not roll back a valid new preset by continuously restarting its accepted resize.")
        XCTAssertEqual(result.actual, target)
        XCTAssertNil(result.constrainedMinimum, "The previous preset is not an app minimum.")
        XCTAssertEqual(result.writes, 1, "An accepted, pending resize needs a settling interval, not repeated duplicate writes.")
    }

    func testAnUnchangedPreviousPresetDoesNotProveAMinimumSize() {
        var clock = 0.0
        let result = FrameSettler.adjust(to: target, read: { self.original }, write: { .accepted },
                                        now: { clock }, wait: { clock += $0 })
        XCTAssertFalse(result.reachedTarget)
        XCTAssertNil(result.constrainedMinimum,
                     "A successful AX reply with no observed size response cannot justify auto-fitting back to the previous grid.")
    }

    func testTransientMatchDoesNotCountAsStableSuccess() {
        var clock = 0.0
        let result = FrameSettler.adjust(to: target, read: {
            clock >= 0.04 && clock < 0.10 ? self.target : self.original
        }, write: { .retryable }, now: { clock }, wait: { clock += $0 })
        XCTAssertFalse(result.reachedTarget)
        XCTAssertNil(result.constrainedMinimum, "A refused or timed-out size request is not evidence of an app minimum.")
        XCTAssertLessThanOrEqual(result.writes, 2)
        XCTAssertLessThanOrEqual(clock, FrameSettler.timeout + 0.0001)
    }

    func testMeasuresOnlyTheConstrainedDimension() {
        var clock = 0.0
        let actual = CGRect(x: 8, y: 38, width: 1000, height: target.height)
        var didWrite = false
        let result = FrameSettler.adjust(to: target, read: { didWrite ? actual : self.original },
                                        write: { didWrite = true; return .accepted }, now: { clock }, wait: { clock += $0 })
        XCTAssertFalse(result.reachedTarget)
        XCTAssertEqual(result.constrainedMinimum, CGSize(width: 1000, height: 0))
    }

    func testPositionOrHeightResponseDoesNotProveUnchangedWidthIsAMinimum() {
        var clock = 0.0
        var didWrite = false
        let actual = CGRect(x: target.minX, y: target.minY, width: original.width, height: target.height)
        let result = FrameSettler.adjust(to: target, read: { didWrite ? actual : self.original },
                                        write: { didWrite = true; return .accepted }, now: { clock }, wait: { clock += $0 })
        XCTAssertFalse(result.reachedTarget)
        XCTAssertNil(result.constrainedMinimum)
    }

    func testLostRepliesGetTheSameSettlingGraceAsAcceptedReplies() {
        var clock = 0.0
        var completesAt: Double?
        let result = FrameSettler.adjust(to: target, read: {
            completesAt.map { clock >= $0 } == true ? self.target : self.original
        }, write: { completesAt = clock + 0.9; return .retryable }, now: { clock }, wait: { clock += $0 })
        XCTAssertTrue(result.reachedTarget)
        XCTAssertEqual(result.writes, 1)
    }

    func testUnansweredFirstWriteGetsOneBoundedRetry() {
        var clock = 0.0
        var attempts = 0
        var completesAt: Double?
        let result = FrameSettler.adjust(to: target, read: {
            completesAt.map { clock >= $0 } == true ? self.target : self.original
        }, write: {
            attempts += 1
            if attempts == 2 { completesAt = clock + 0.55 }
            return .accepted
        }, now: { clock }, wait: { clock += $0 })
        XCTAssertTrue(result.reachedTarget)
        XCTAssertEqual(result.writes, 2)
        XCTAssertLessThan(clock, FrameSettler.timeout)
    }

    func testPermissionFailureStopsWithoutRetrying() {
        var clock = 0.0
        let result = FrameSettler.adjust(to: target, read: { self.original }, write: { .unavailable }, now: { clock }, wait: { clock += $0 })
        XCTAssertFalse(result.reachedTarget)
        XCTAssertTrue(result.unavailable)
        XCTAssertEqual(result.writes, 1)
        XCTAssertEqual(clock, 0)
    }

    func testNoWritesForAlreadySettledTargetAndNoUnboundedClockLoop() {
        var clock = 0.0
        let correct = FrameSettler.adjust(to: target, read: { self.target }, write: { XCTFail("No write necessary"); return .accepted },
                                         now: { clock }, wait: { clock += $0 })
        XCTAssertTrue(correct.reachedTarget)
        let stoppedClock = FrameSettler.adjust(to: target, read: { nil }, write: { .retryable }, now: { 0 }, wait: { _ in })
        XCTAssertFalse(stoppedClock.reachedTarget)
        XCTAssertEqual(stoppedClock.writes, 1)
    }
}
