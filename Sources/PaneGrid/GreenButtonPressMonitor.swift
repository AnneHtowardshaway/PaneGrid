import AppKit
import ApplicationServices

/// Delays only an annotated left-down on a recently AX-verified external zoom button.
/// All callbacks and timers run on the main run loop; `validate` must do AX work asynchronously.
@MainActor
final class GreenButtonPressMonitor {
    static let holdDuration: TimeInterval = 0.45
    static let cacheLifetime: TimeInterval = 0.35
    private static let replayMarker: Int64 = 0x5047_484F_4C44_0001
    private static let validationDeadline: TimeInterval = 0.9
    private static let movementTolerance: CGFloat = 2

    private struct Candidate {
        let target: ZoomTarget
        let verifiedAt: TimeInterval
    }

    private struct Press {
        let generation: Int
        let target: ZoomTarget
        let point: CGPoint
        let startedAt: TimeInterval
        var events: [CGEvent]
        var validationPoint: CGPoint?
        var opened = false
        var releasedSince: TimeInterval?
    }

    private let canCapture: @MainActor () -> Bool
    private let onCapture: @MainActor () -> Void
    private let validate: @MainActor (ZoomTarget, CGPoint) async -> ZoomTarget?
    private let open: @MainActor (ZoomTarget) -> Bool
    private let onRelease: @MainActor (ZoomTarget) -> Void
    private let onUnavailable: @MainActor () -> Void
    private var candidate: Candidate?
    private var press: Press?
    private var capturedDownTimestamp: CGEventTimestamp?
    private var generation = 0
    private var enabled = false
    private var reportedUnavailable = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var watchdog: Timer?
    private var validationTask: Task<Void, Never>?

    var isCapturing: Bool { press != nil }

    init(canCapture: @escaping @MainActor () -> Bool,
         onCapture: @escaping @MainActor () -> Void,
         validate: @escaping @MainActor (ZoomTarget, CGPoint) async -> ZoomTarget?,
         open: @escaping @MainActor (ZoomTarget) -> Bool,
         onRelease: @escaping @MainActor (ZoomTarget) -> Void,
         onUnavailable: @escaping @MainActor () -> Void) {
        self.canCapture = canCapture
        self.onCapture = onCapture
        self.validate = validate
        self.open = open
        self.onRelease = onRelease
        self.onUnavailable = onUnavailable
    }

    deinit {
        watchdog?.invalidate()
        validationTask?.cancel()
        // Invalidate the port before releasing its unretained callback context.
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let press, !press.opened {
            for event in press.events { event.post(tap: .cgAnnotatedSessionEventTap) }
            if !CGEventSource.buttonState(.hidSystemState, button: .left),
               let up = press.events.last?.copy() {
                up.type = .leftMouseUp
                up.post(tap: .cgAnnotatedSessionEventTap)
            }
        }
    }

    static func isReplay(_ event: CGEvent?) -> Bool {
        event?.getIntegerValueField(.eventSourceUserData) == replayMarker
    }

    /// NSEvent's global monitor may be delivered before OR after our mutable tap callback.
    /// Preserve only the exact captured down, or a down that is eligible for capture right now.
    func preservesTarget(for event: CGEvent?) -> Bool {
        guard let event, event.type == .leftMouseDown else { return false }
        if event.timestamp == capturedDownTimestamp { return true }
        return eligibleCandidate(for: event) != nil
    }

    func updateTarget(_ target: ZoomTarget?, verifiedAt: TimeInterval = 0) {
        candidate = target.map { Candidate(target: $0, verifiedAt: verifiedAt) }
    }

    func setEnabled(_ value: Bool) {
        if !value {
            enabled = false
            cancelPending()
            // A committed hold still owns its up. Drain only that sequence, never a new down.
            if press == nil, let tap { CGEvent.tapEnable(tap: tap, enable: false) }
            return
        }
        guard !enabled else { return }
        enabled = true
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
            if !CGEvent.tapIsEnabled(tap: tap) { reportUnavailable() }
        }
        else { installTap() }
    }

    /// Invalidates delayed validation but does not turn an already-opened picker into a native click.
    func cancelPending() {
        candidate = nil
        if let press, !press.opened { finish(replay: true) }
    }

    private func installTap() {
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .mouseMoved,
                                    .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callback: CGEventTapCallBack = { proxy, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            // This port's source is installed exclusively on CFRunLoopGetMain(). Swift 5 mode
            // cannot infer that isolation from the C callback signature.
            return MainActor.assumeIsolated {
                let monitor = Unmanaged<GreenButtonPressMonitor>.fromOpaque(context).takeUnretainedValue()
                return monitor.receive(proxy: proxy, type: type, event: event)
            }
        }
        guard let port = CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap, place: .headInsertEventTap,
                                           options: .defaultTap, eventsOfInterest: mask,
                                           callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            reportUnavailable(); return
        }
        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            reportUnavailable(); return
        }
        tap = port
        source = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        if !CGEvent.tapIsEnabled(tap: port) { reportUnavailable() }
    }

    private func reportUnavailable() {
        guard !reportedUnavailable else { return }
        reportedUnavailable = true
        // Do not construct SwiftUI/AppKit notice content inside an event-tap callback.
        let notify = onUnavailable
        Task { @MainActor in notify() }
    }

    private func receive(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let unchanged = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Release delayed native input first. Never resume an old validation after a tap outage.
            if let press, !press.opened { finish(replay: true, proxy: proxy, balanceMissingUp: true) }
            candidate = nil
            if enabled, canCapture(), let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
                if !CGEvent.tapIsEnabled(tap: tap) { reportUnavailable() }
            }
            return unchanged
        }
        guard !Self.isReplay(event) else { return unchanged }

        if type == .leftMouseDown {
            // A fresh down also clears ownership if an earlier up was lost during a tap outage.
            if let press { finish(replay: !press.opened, proxy: proxy, forceMissingUp: true) }
            guard let candidate = eligibleCandidate(for: event),
                  let down = copiedForReplay(event) else { return unchanged }
            generation += 1
            capturedDownTimestamp = event.timestamp
            press = Press(generation: generation, target: candidate.target, point: event.location,
                      startedAt: ProcessInfo.processInfo.systemUptime, events: [down])
            self.candidate = nil
            onCapture()
            let timer = Timer(timeInterval: 0.025, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkHold() }
            }
            watchdog = timer
            RunLoop.main.add(timer, forMode: .common)
            return nil
        }

        guard let press else { return unchanged }
        if type == .leftMouseUp {
            if press.opened { finish(replay: false); return nil }
            guard let up = copiedForReplay(event) else {
                finish(replay: true, proxy: proxy); return unchanged
            }
            self.press?.events.append(up)
            finish(replay: true, proxy: proxy)
            return nil
        }
        if type == .leftMouseDragged || type == .mouseMoved {
            if press.opened { return type == .leftMouseDragged ? nil : unchanged }
            guard enabled, canCapture(), contains(event.location, in: press),
                  event.getIntegerValueField(.eventTargetUnixProcessID) == Int64(press.target.window.app.pid) else {
                // Insert the saved down/drags ahead of THIS original drag, preserving native tracking.
                finish(replay: true, proxy: proxy); return unchanged
            }
            if type == .leftMouseDragged {
                guard press.events.count < 64, let drag = copiedForReplay(event) else {
                    finish(replay: true, proxy: proxy); return unchanged
                }
                self.press?.events.append(drag)
                return nil
            }
        } else if !press.opened {
            // Right/other clicks, scrolling and keyboard input always pass through unchanged.
            finish(replay: true, proxy: proxy)
        }
        return unchanged
    }

    private func eligibleCandidate(for event: CGEvent) -> Candidate? {
        let now = ProcessInfo.processInfo.systemUptime
        guard enabled, canCapture(), let candidate, let tap, CGEvent.tapIsEnabled(tap: tap),
              now - candidate.verifiedAt >= 0, now - candidate.verifiedAt <= Self.cacheLifetime,
              candidate.target.buttonFrame.contains(event.location),
              candidate.target.window.app.pid != ProcessInfo.processInfo.processIdentifier,
              // Missing destination annotation fails open; a stale rectangle must never
              // delay a click addressed to a different app.
              event.getIntegerValueField(.eventTargetUnixProcessID) == Int64(candidate.target.window.app.pid) else { return nil }
        return candidate
    }

    private func contains(_ point: CGPoint, in press: Press) -> Bool {
        press.target.buttonFrame.contains(point) && hypot(point.x - press.point.x, point.y - press.point.y) <= Self.movementTolerance
    }

    private func checkHold() {
        guard let press else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let buttonDown = CGEventSource.buttonState(.hidSystemState, button: .left)
        if press.opened {
            // Normally the tap sees up first. Clear a missed release after a small delivery grace;
            // ownership never leaks into the next physical down, even if the port was disabled.
            if buttonDown { self.press?.releasedSince = nil }
            else if let since = press.releasedSince, now - since >= 0.1 { finish(replay: false) }
            else if press.releasedSince == nil { self.press?.releasedSince = now }
            return
        }
        if !buttonDown, enabled, canCapture() {
            // Hardware state can lead delivery of the original up. Give it a bounded grace
            // instead of replacing an ordinary short click's exact up with a synthetic one.
            if let since = press.releasedSince, now - since >= 0.1 { finish(replay: true) }
            else if press.releasedSince == nil { self.press?.releasedSince = now }
            return
        }
        self.press?.releasedSince = nil
        guard enabled, canCapture(), buttonDown,
              let point = CGEvent(source: nil)?.location, contains(point, in: press),
              now - press.startedAt < Self.validationDeadline,
              let tap, CGEvent.tapIsEnabled(tap: tap) else {
            finish(replay: true); return
        }
        guard now - press.startedAt >= Self.holdDuration, press.validationPoint == nil else { return }
        self.press?.validationPoint = point
        let validate = self.validate
        validationTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            let result = await validate(press.target, point)
            guard !Task.isCancelled else { return }
            self?.validationFinished(result, generation: press.generation, point: point)
        }
    }

    private func validationFinished(_ target: ZoomTarget?, generation: Int, point: CGPoint) {
        guard let press, press.generation == generation, !press.opened else { return }
        validationTask = nil
        if enabled, canCapture(), !CGEventSource.buttonState(.hidSystemState, button: .left) {
            // Do not race the queued physical up when AX happens to complete just after release.
            if press.releasedSince == nil { self.press?.releasedSince = ProcessInfo.processInfo.systemUptime }
            return
        }
        guard let target, enabled, canCapture(),
              ProcessInfo.processInfo.systemUptime - press.startedAt < Self.validationDeadline,
              CGEventSource.buttonState(.hidSystemState, button: .left),
              CGEvent(source: nil)?.location == point, contains(point, in: press),
              let tap, CGEvent.tapIsEnabled(tap: tap) else {
            finish(replay: true); return
        }
        // Mark ownership before opening: show() invalidates pending gestures and AX completions.
        self.press?.opened = true
        if !open(target) {
            self.press?.opened = false
            finish(replay: true)
        }
    }

    private func copiedForReplay(_ event: CGEvent) -> CGEvent? {
        guard let copy = event.copy() else { return nil }
        // Retain the original timestamp, flags, location, click count and all other event fields.
        copy.setIntegerValueField(.eventSourceUserData, value: Self.replayMarker)
        return copy
    }

    private func finish(replay: Bool, proxy: CGEventTapProxy? = nil,
                        balanceMissingUp: Bool = false, forceMissingUp: Bool = false) {
        guard let press else { return }
        self.press = nil
        candidate = nil
        generation += 1
        validationTask?.cancel()
        validationTask = nil
        watchdog?.invalidate()
        watchdog = nil
        if replay {
            var events = press.events
            // A watchdog/teardown can discover a lost up. Balance the replayed native down in
            // that exceptional case; ordinary short clicks always replay the exact copied up.
            let needsUp = forceMissingUp || ((proxy == nil || balanceMissingUp) &&
                !CGEventSource.buttonState(.hidSystemState, button: .left))
            if needsUp, events.last?.type != .leftMouseUp, let up = events.last?.copy() {
                up.type = .leftMouseUp
                if let point = CGEvent(source: nil)?.location { up.location = point }
                events.append(up)
            }
            for event in events {
                if let proxy { event.tapPostEvent(proxy) }
                else { event.post(tap: .cgAnnotatedSessionEventTap) }
            }
        }
        onRelease(press.target)
        if !enabled, let tap { CGEvent.tapEnable(tap: tap, enable: false) }
    }
}
