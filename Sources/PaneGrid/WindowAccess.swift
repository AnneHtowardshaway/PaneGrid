import AppKit
import ApplicationServices
import PaneGridCore

struct AppCandidate: Sendable {
    let pid: pid_t
    let name: String
    let bundleID: String

    @MainActor static func running(excluding: [String]) -> [AppCandidate] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, !app.isHidden, !app.isTerminated,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  !excluding.contains(app.bundleIdentifier ?? "") else { return nil }
            return AppCandidate(pid: app.processIdentifier, name: app.localizedName ?? "Application",
                                bundleID: app.bundleIdentifier ?? "process.\(app.processIdentifier)")
        }
    }
}

struct LiveWindow: Identifiable, @unchecked Sendable {
    let id: String
    let element: AXUIElement
    let app: AppCandidate
    let title: String
    let ordinal: Int
    let frame: CGRect
    var identity: WindowIdentity { .init(bundleID: app.bundleID, title: title, ordinal: ordinal) }
    var displayTitle: String { title.isEmpty ? Localization.t("Untitled window") : title }
}

struct WindowMove: @unchecked Sendable {
    let window: LiveWindow
    let destination: CGRect
}

private final class WindowOperationControl: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    let deadline: TimeInterval

    init(windowCount: Int) {
        deadline = ProcessInfo.processInfo.systemUptime + max(10, min(30, 4 + Double(windowCount) * 1.6))
    }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    var shouldStop: Bool { isCancelled || ProcessInfo.processInfo.systemUptime >= deadline }
}

struct MoveReport: Sendable {
    let succeeded: Bool
    let message: String
    let movedCount: Int
    var failure: WindowMoveFailure? = nil
}

struct WindowMoveFailure: Sendable {
    let windowID: String
    let requested: CGRect
    let actual: CGRect?
    let constrainedMinimum: CGSize?
    let rollbackFailures: Int
}

enum WindowGroupError: Error, LocalizedError {
    case unavailable, tooMany, targetMissing
    var errorDescription: String? {
        switch self {
        case .unavailable: return Localization.t("The app’s window list could not be read. Nothing was moved. Try again when the app responds.")
        case .tooMany: return Localization.t("This app has more than 128 windows. Nothing was moved; use a smaller selected group.")
        case .targetMissing: return Localization.t("The target window closed or is no longer resizable. Open the picker again.")
        }
    }
}

struct ZoomTarget: @unchecked Sendable {
    let window: LiveWindow
    let buttonFrame: CGRect
}

/// AX messaging is synchronous and can block on another app. Keep all of it off the UI thread.
final class WindowAccess: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.panegrid.accessibility", qos: .userInitiated)
    private var known: [LiveWindow] = []
    private var undoHistory: [[WindowMove]] = []
    private let operationLock = NSLock()
    private var activeOperation: WindowOperationControl?

    static var isTrusted: Bool { AXIsProcessTrusted() }

    @MainActor static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func windows(in apps: [AppCandidate]) async -> [LiveWindow] {
        await withCheckedContinuation { continuation in
            queue.async {
                guard Self.isTrusted else { continuation.resume(returning: []); return }
                var result: [LiveWindow] = []
                for app in apps.prefix(128) {
                    let element = AXUIElementCreateApplication(app.pid)
                    AXUIElementSetMessagingTimeout(element, 0.15)
                    let windows = Self.value(element, kAXWindowsAttribute) as? [AXUIElement] ?? []
                    var ordinals: [String: Int] = [:]
                    for window in windows.prefix(128) {
                        guard Self.isEligible(window), let frame = Self.frame(window) else { continue }
                        let title = Self.value(window, kAXTitleAttribute) as? String ?? ""
                        let ordinal = ordinals[title, default: 0]
                        ordinals[title] = ordinal + 1
                        result.append(self.makeWindow(window, app: app, title: title, ordinal: ordinal, frame: frame))
                    }
                }
                self.known = result
                continuation.resume(returning: result)
            }
        }
    }

    func focusedWindow(in app: AppCandidate) async -> LiveWindow? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard Self.isTrusted else { continuation.resume(returning: nil); return }
                let application = AXUIElementCreateApplication(app.pid)
                AXUIElementSetMessagingTimeout(application, 0.15)
                guard let element = Self.element(application, kAXFocusedWindowAttribute),
                      Self.isEligible(element), let frame = Self.frame(element) else {
                    continuation.resume(returning: nil); return
                }
                let title = Self.value(element, kAXTitleAttribute) as? String ?? ""
                let window = self.makeWindow(element, app: app, title: title, ordinal: 0, frame: frame)
                if !self.known.contains(where: { $0.id == window.id }) { self.known.append(window) }
                continuation.resume(returning: window)
            }
        }
    }

    /// Enumerate only the exact target process; retain unrelated cached IDs and never fall back to title matching.
    func applicationWindows(containing target: LiveWindow) async throws -> [LiveWindow] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard Self.isTrusted else { throw WindowGroupError.unavailable }
                    let application = AXUIElementCreateApplication(target.app.pid)
                    AXUIElementSetMessagingTimeout(application, 0.2)
                    guard let elements = Self.value(application, kAXWindowsAttribute) as? [AXUIElement] else { throw WindowGroupError.unavailable }
                    guard elements.count <= 128 else { throw WindowGroupError.tooMany }
                    var result: [LiveWindow] = []
                    var ordinals: [String: Int] = [:]
                    for element in elements {
                        var pid: pid_t = 0
                        guard AXUIElementGetPid(element, &pid) == .success, pid == target.app.pid,
                              Self.isEligible(element), let frame = Self.frame(element) else { continue }
                        let title = Self.value(element, kAXTitleAttribute) as? String ?? ""
                        let ordinal = ordinals[title, default: 0]
                        ordinals[title] = ordinal + 1
                        let window = self.makeWindow(element, app: target.app, title: title, ordinal: ordinal, frame: frame)
                        // Preserve the picker identity even if a simultaneous full scan evicted its cache entry.
                        result.append(CFEqual(element, target.element)
                                      ? LiveWindow(id: target.id, element: element, app: target.app, title: title, ordinal: ordinal, frame: frame)
                                      : window)
                    }
                    guard result.contains(where: { CFEqual($0.element, target.element) }) else { throw WindowGroupError.targetMissing }
                    self.known = self.known.filter { $0.app.pid != target.app.pid } + result
                    result.sort { a, b in
                        if a.id == target.id { return b.id != target.id }
                        if b.id == target.id { return false }
                        return (a.frame.minY, a.frame.minX, a.id) < (b.frame.minY, b.frame.minX, b.id)
                    }
                    continuation.resume(returning: result)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func zoomTarget(at point: CGPoint, apps: [AppCandidate]) async -> ZoomTarget? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard Self.isTrusted else { continuation.resume(returning: nil); return }
                // A system-wide AX hit-test can call our own SwiftUI accessibility code inline on this
                // worker, deadlocking its view-graph lock against AppKit's main-thread layout lock.
                // Resolve only public window bounds/PIDs first, then hit-test an EXTERNAL app directly.
                guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
                    let top = info.first(where: { item in
                      guard (item[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                          let raw = item[kCGWindowBounds as String] as? NSDictionary,
                          let bounds = CGRect(dictionaryRepresentation: raw) else { return false }
                      return bounds.contains(point)
                    }), let owner = top[kCGWindowOwnerPID as String] as? Int32,
                    owner != ProcessInfo.processInfo.processIdentifier,
                    let app = apps.first(where: { $0.pid == owner }) else { continuation.resume(returning: nil); return }
                let application = AXUIElementCreateApplication(owner)
                AXUIElementSetMessagingTimeout(application, 0.15)
                var hit: AXUIElement?
                guard AXUIElementCopyElementAtPosition(application, Float(point.x), Float(point.y), &hit) == .success,
                      let hit else { continuation.resume(returning: nil); return }
                var pid: pid_t = 0
                AXUIElementGetPid(hit, &pid)
                guard pid == owner else { continuation.resume(returning: nil); return }
                let windowElement: AXUIElement?
                if Self.value(hit, kAXRoleAttribute) as? String == kAXWindowRole { windowElement = hit }
                else { windowElement = Self.element(hit, kAXWindowAttribute) }
                guard let element = windowElement, Self.isEligible(element),
                      let zoom = Self.element(element, kAXZoomButtonAttribute),
                      let buttonFrame = Self.frame(zoom), buttonFrame.insetBy(dx: -2, dy: -2).contains(point),
                      let frame = Self.frame(element) else { continuation.resume(returning: nil); return }
                let title = Self.value(element, kAXTitleAttribute) as? String ?? ""
                let window = self.makeWindow(element, app: app, title: title, ordinal: 0, frame: frame)
                if !self.known.contains(where: { $0.id == window.id }) { self.known.append(window) }
                continuation.resume(returning: ZoomTarget(window: window, buttonFrame: buttonFrame))
            }
        }
    }

    func apply(_ moves: [WindowMove]) async -> MoveReport {
        let control = WindowOperationControl(windowCount: moves.count)
        setActiveOperation(control)
        return await withCheckedContinuation { continuation in
            queue.async {
                let report = self.perform(moves, recordUndo: true, control: control)
                self.clearActiveOperation(control)
                continuation.resume(returning: report)
            }
        }
    }

    func undo() async -> MoveReport {
        let control = WindowOperationControl(windowCount: 20)
        setActiveOperation(control)
        return await withCheckedContinuation { continuation in
            queue.async {
                defer { self.clearActiveOperation(control) }
                guard let moves = self.undoHistory.popLast() else {
                    continuation.resume(returning: .init(succeeded: false, message: Localization.t("Nothing to undo yet."), movedCount: 0)); return
                }
                let report = self.perform(moves, recordUndo: false, control: control)
                if !report.succeeded { self.undoHistory.append(moves) }
                continuation.resume(returning: report)
            }
        }
    }

    func cancelCurrentOperation() {
        operationLock.lock()
        let operation = activeOperation
        operationLock.unlock()
        operation?.cancel()
    }

    private func setActiveOperation(_ operation: WindowOperationControl) {
        operationLock.lock(); activeOperation = operation; operationLock.unlock()
    }

    private func clearActiveOperation(_ operation: WindowOperationControl) {
        operationLock.lock()
        if activeOperation === operation { activeOperation = nil }
        operationLock.unlock()
    }

    func actualFrame(of window: LiveWindow) async -> CGRect? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: Self.frame(window.element)) }
        }
    }

    func zoomButtonFrame(of window: LiveWindow) async -> CGRect? {
        await withCheckedContinuation { continuation in
            queue.async {
                let zoom = Self.element(window.element, kAXZoomButtonAttribute)
                continuation.resume(returning: zoom.flatMap { Self.frame($0) })
            }
        }
    }

    func identifier(of window: LiveWindow) async -> String? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: Self.value(window.element, kAXIdentifierAttribute) as? String) }
        }
    }

    private func makeWindow(_ element: AXUIElement, app: AppCandidate, title: String, ordinal: Int, frame: CGRect) -> LiveWindow {
        let previous = known.first { $0.app.pid == app.pid && CFEqual($0.element, element) }
        return LiveWindow(id: previous?.id ?? UUID().uuidString, element: element, app: app,
                          title: title, ordinal: ordinal, frame: frame)
    }

    private func perform(_ moves: [WindowMove], recordUndo: Bool, control: WindowOperationControl) -> MoveReport {
        guard Self.isTrusted else { return .init(succeeded: false, message: Localization.t("Enable Accessibility access to arrange windows."), movedCount: 0) }
        guard !moves.isEmpty else { return .init(succeeded: false, message: Localization.t("Assign at least one window first."), movedCount: 0) }
        guard moves.count <= 128, Set(moves.map { $0.window.id }).count == moves.count else {
            return .init(succeeded: false, message: Localization.t("The arrangement contains too many or duplicate windows."), movedCount: 0)
        }
        var originals: [WindowMove] = []
        // Preflight the entire batch before changing anything.
        for move in moves {
            if control.shouldStop { return .init(succeeded: false, message: Localization.t("Arrangement stopped before moving any windows."), movedCount: 0) }
            guard !originals.contains(where: { $0.window.app.pid == move.window.app.pid && CFEqual($0.window.element, move.window.element) }) else {
                return .init(succeeded: false, message: Localization.t("The same live window was assigned twice. Refresh the window list; nothing was moved."), movedCount: 0)
            }
            guard Self.isEligible(move.window.element), let original = Self.frame(move.window.element),
                  Self.valid(move.destination) else {
                return .init(succeeded: false, message: Localization.t("A window closed, became fullscreen, or cannot be resized. Refresh and try again."), movedCount: 0)
            }
            originals.append(.init(window: move.window, destination: original))
        }
        for move in moves {
            let adjustment = Self.setFrame(move.destination, on: move.window.element, shouldStop: { control.shouldStop })
            if !adjustment.reachedTarget {
                return failureReport(move: move, adjustment: adjustment, originals: originals, control: control)
            }
        }
        // Sibling windows can adjust asynchronously. Allow one bounded corrective pass, then verify the whole batch.
        for pass in 0..<2 {
            Thread.sleep(forTimeInterval: 0.12)
            let mismatches = moves.filter { move in
                guard let actual = Self.frame(move.window.element) else { return true }
                return !Self.close(actual, move.destination)
            }
            for move in mismatches {
                if pass == 1 {
                    let actual = Self.frame(move.window.element)
                    let failures = rollback(originals)
                    let detail = failures == 0 ? Localization.t("Previous positions restored.")
                        : Localization.tf("%ld window(s) could not be restored.", failures)
                    let message = Localization.tf("%@ kept changing the layout after resizing. %@", move.window.app.name, detail)
                    return .init(succeeded: false, message: message, movedCount: 0,
                                 failure: .init(windowID: move.window.id, requested: move.destination, actual: actual, constrainedMinimum: nil, rollbackFailures: failures))
                }
                let adjustment = Self.setFrame(move.destination, on: move.window.element, shouldStop: { control.shouldStop })
                if !adjustment.reachedTarget { return failureReport(move: move, adjustment: adjustment, originals: originals, control: control) }
            }
        }
        if recordUndo {
            undoHistory.append(originals)
            if undoHistory.count > 20 { undoHistory.removeFirst() }
        }
        return .init(succeeded: true, message: moves.count == 1
                     ? Localization.tf("%ld window arranged. Unassigned cells stay empty.", moves.count)
                     : Localization.tf("%ld windows arranged. Unassigned cells stay empty.", moves.count), movedCount: moves.count)
    }

    private func failureReport(move: WindowMove, adjustment: FrameAdjustment, originals: [WindowMove], control: WindowOperationControl) -> MoveReport {
        let failures = rollback(originals, drainPending: control.shouldStop)
        let requested = "\(Int(move.destination.width.rounded())) × \(Int(move.destination.height.rounded()))"
        let actual = adjustment.actual.map { "\(Int($0.width.rounded())) × \(Int($0.height.rounded()))" } ?? Localization.t("unavailable")
        let cause: String
        if control.isCancelled {
            cause = Localization.t("arrangement was cancelled.")
        } else if control.shouldStop {
            cause = Localization.t("arrangement exceeded its bounded response time.")
        } else if adjustment.constrainedMinimum != nil {
            cause = Localization.tf("kept the window at %@ pt instead of %@ pt. This portion is below the app’s observed size limit.", actual, requested)
        } else if adjustment.unavailable {
            cause = Localization.t("stopped accepting window-control requests.")
        } else if let frame = adjustment.actual, FrameSettler.matchesSize(frame, move.destination) {
            cause = Localization.tf("accepted the %@ pt size but did not move to (%ld, %ld). Actual position: (%ld, %ld).",
                                    requested, Int(move.destination.minX), Int(move.destination.minY), Int(frame.minX), Int(frame.minY))
        } else {
            cause = Localization.tf("did not settle at %@ pt (last size: %@).", requested, actual)
        }
        let detail = failures == 0
            ? Localization.t("Previous positions restored; no replacement layout was applied. Try a larger portion if the app requires it.")
            : Localization.tf("%ld window(s) could not be restored; inspect them before retrying.", failures)
        return .init(succeeded: false, message: "\(move.window.app.name) \(cause) \(detail)", movedCount: 0,
                     failure: .init(windowID: move.window.id, requested: move.destination, actual: adjustment.actual,
                                    constrainedMinimum: adjustment.constrainedMinimum, rollbackFailures: failures))
    }

    private func rollback(_ originals: [WindowMove], drainPending: Bool = false) -> Int {
        // Give the last in-flight animation a settling interval, then restore only changed
        // frames. Rewriting unchanged windows starts new animations and makes recovery worse.
        Thread.sleep(forTimeInterval: drainPending ? 1.2 : 0.2)
        let deadline = ProcessInfo.processInfo.systemUptime + max(4, min(15, Double(originals.count) * 1.2 + 2))
        for original in originals.reversed() {
            guard ProcessInfo.processInfo.systemUptime < deadline else { break }
            if let actual = Self.frame(original.window.element), Self.close(actual, original.destination) { continue }
            _ = Self.setFrame(original.destination, on: original.window.element,
                              shouldStop: { ProcessInfo.processInfo.systemUptime >= deadline })
        }
        Thread.sleep(forTimeInterval: 0.16)
        return originals.reduce(0) { failures, original in
            guard let actual = Self.frame(original.window.element) else { return failures + 1 }
            return failures + (Self.close(actual, original.destination) ? 0 : 1)
        }
    }

    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self) // CF type ID checked above.
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let rawPoint = value(element, kAXPositionAttribute), CFGetTypeID(rawPoint) == AXValueGetTypeID(),
              let rawSize = value(element, kAXSizeAttribute), CFGetTypeID(rawSize) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(rawPoint, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(rawSize, to: AXValue.self), .cgSize, &size) else { return nil }
        let frame = CGRect(origin: point, size: size)
        return valid(frame) ? frame : nil
    }

    static func isEligible(_ element: AXUIElement) -> Bool {
        guard value(element, kAXRoleAttribute) as? String == kAXWindowRole,
              value(element, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
              value(element, kAXMinimizedAttribute) as? Bool != true,
              value(element, "AXFullScreen") as? Bool != true else { return false }
        var sizeSettable = DarwinBoolean(false)
        var positionSettable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &sizeSettable) == .success &&
            AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &positionSettable) == .success &&
            sizeSettable.boolValue && positionSettable.boolValue
    }

    private static func valid(_ rect: CGRect) -> Bool {
        [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite) && rect.size.width > 0 && rect.size.height > 0
    }

    static func close(_ a: CGRect, _ b: CGRect, tolerance: Double = 2) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance &&
        abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    private static func setFrame(_ rect: CGRect, on element: AXUIElement, shouldStop: () -> Bool = { false }) -> FrameAdjustment {
        AXUIElementSetMessagingTimeout(element, 0.2)
        let presentation = presentationWindow(for: element)
        func status(_ result: AXError) -> FrameWriteStatus {
            result == .success ? .accepted : result == .cannotComplete ? .retryable : .unavailable
        }
        return WindowFrameDriver.adjust(to: rect, read: {
            guard let accessibilityFrame = Self.frame(element) else { return nil }
            // Enhanced Accessibility can report the animation's logical destination before
            // the WindowServer has moved the window. Starting the next axis then uses stale
            // on-screen bounds and clips/resets the size. Geometry-only CG metadata is public
            // and requires no screenshot permission; AX remains the ONLY write target.
            if let presentation { return presentationFrame(presentation) ?? accessibilityFrame }
            return accessibilityFrame
        }, setPosition: { origin in
            var point = origin
            guard Self.isTrusted, let value = AXValueCreate(.cgPoint, &point) else { return .unavailable }
            return status(AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value))
        }, setSize: { dimensions in
            var size = dimensions
            guard Self.isTrusted, let value = AXValueCreate(.cgSize, &size) else { return .unavailable }
            return status(AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value))
        }, now: { ProcessInfo.processInfo.systemUptime }, wait: { Thread.sleep(forTimeInterval: $0) }, shouldStop: shouldStop)
    }

    private static func presentationWindow(for element: AXUIElement) -> (id: CGWindowID, pid: pid_t)? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, let frame = frame(element),
              let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let matches = list.filter { item in
            guard item[kCGWindowOwnerPID as String] as? Int32 == pid, item[kCGWindowLayer as String] as? Int == 0,
                  let raw = item[kCGWindowBounds as String] as? NSDictionary, let bounds = CGRect(dictionaryRepresentation: raw) else { return false }
            return close(bounds, frame)
        }
        // This association is for observing geometry only, never for selecting a write target.
        // Refuse ambiguous matches instead of matching personal window titles.
        guard matches.count == 1, let number = matches[0][kCGWindowNumber as String] as? UInt32 else { return nil }
        return (number, pid)
    }

    private static func presentationFrame(_ window: (id: CGWindowID, pid: pid_t)) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, window.id) as? [[String: Any]],
              let item = list.first(where: { $0[kCGWindowNumber as String] as? UInt32 == window.id && $0[kCGWindowOwnerPID as String] as? Int32 == window.pid }),
              let raw = item[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: raw), valid(bounds) else { return nil }
        return bounds
    }
}
