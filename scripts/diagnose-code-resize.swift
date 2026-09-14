// Compile with Sources/PaneGridCore/Grid.swift to use the real, scale-aware geometry.
// Only a fresh empty profile and its exact directly launched PID may receive AX writes.
// Existing Code AX identities/frames are read only for the safety audit; never read titles.
import AppKit
import ApplicationServices

private final class LaunchOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = 0
    private var sample = Data()
    func append(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        bytes += data.count
        sample.append(data.prefix(max(0, 262_144 - sample.count)))
    }
    func summary() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        let text = String(decoding: sample, as: UTF8.self)
        let markers = ["ELECTRON_RUN_AS_NODE", "bad option", "Unknown option", "already running",
                       "Another instance", "EACCES", "EPERM", "ENOENT", "FATAL", "Error", "crashpad"]
        return ["bytes": bytes, "knownMarkers": markers.filter { text.contains($0) },
                "rawOutputOmittedForPrivacy": true]
    }
}

@main
struct CodeResizeDiagnostic {
    enum Stop: String, Error { case noTrust, noDisplay, unsafeTarget, noTestWindow, restoreFailed, baselineChanged }
    enum Order: String { case production, sizePosition, positionSize, settled }
    struct Baseline {
        let pid: pid_t
        let element: AXUIElement
        let original: CGRect?
    }
    static let queue = DispatchQueue(label: "dev.panegrid.code-resize-diagnostic")
    static func onAX<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try work() }) }
        }
    }
    static var now: Double { ProcessInfo.processInfo.systemUptime }
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
    }
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let rawPoint = value(element, kAXPositionAttribute), CFGetTypeID(rawPoint) == AXValueGetTypeID(),
              let rawSize = value(element, kAXSizeAttribute), CFGetTypeID(rawSize) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(rawPoint, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(rawSize, to: AXValue.self), .cgSize, &size) else { return nil }
        guard [point.x, point.y, size.width, size.height].allSatisfy(\.isFinite),
              size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: point, size: size)
    }
    static func components(_ rect: CGRect) -> [Double] { [rect.minX, rect.minY, rect.width, rect.height] }
    static func matches(_ a: CGRect, _ b: CGRect) -> Bool { zip(components(a), components(b)).allSatisfy { abs($0 - $1) <= 2 } }
    static func windows(_ pid: pid_t) throws -> [AXUIElement] {
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.15) // Same timeout as WindowAccess.windows.
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &raw) == .success,
              let result = raw as? [AXUIElement] else { throw Stop.noTestWindow }
        return result
    }
    static func owned(_ element: AXUIElement, pid: pid_t, baseline: [Baseline]) throws {
        var owner: pid_t = 0
        var sizeSettable = DarwinBoolean(false), positionSettable = DarwinBoolean(false)
        guard AXUIElementGetPid(element, &owner) == .success, owner == pid,
              !baseline.contains(where: { $0.pid == pid || CFEqual($0.element, element) }),
              try windows(pid).contains(where: { CFEqual($0, element) }),
              value(element, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
              value(element, kAXMinimizedAttribute) as? Bool != true,
              value(element, "AXFullScreen") as? Bool != true,
              AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &sizeSettable) == .success,
              AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &positionSettable) == .success,
              sizeSettable.boolValue, positionSettable.boolValue else { throw Stop.unsafeTarget }
    }
    static func audit(_ baseline: [Baseline], pids: [pid_t]) -> [String: Any] {
        var missing = 0, changed = 0, unreadable = 0, additions = 0
        for pid in pids {
            guard let current = try? windows(pid) else { unreadable += 1; continue }
            let previous = baseline.filter { $0.pid == pid }
            additions += current.filter { item in !previous.contains { CFEqual($0.element, item) } }.count
            for item in previous {
                guard current.contains(where: { CFEqual($0, item.element) }) else { missing += 1; continue }
                if frame(item.element) != item.original { changed += 1 }
            }
        }
        return ["originalWindowCount": baseline.count, "missingIdentities": missing,
                "changedOriginalFrames": changed, "unreadableOriginalProcesses": unreadable,
                "newWindowsInOriginalProcesses": additions,
                "allUnchanged": missing == 0 && changed == 0 && unreadable == 0 && additions == 0]
    }

    // No getter or extra wait is inserted between production's setters. In particular,
    // a failed AXSize prevents AXPosition, and any setter error returns immediately.
    static func apply(_ rect: CGRect, to element: AXUIElement, order: Order,
                      start: Double, events: inout [[String: Any]]) -> (Bool, String) {
        var size = rect.size
        var point = rect.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size), let pointValue = AXValueCreate(.cgPoint, &point) else {
            return (false, "AXValue creation")
        }
        let attributes = order == .positionSize ? [kAXPositionAttribute, kAXSizeAttribute] : [kAXSizeAttribute, kAXPositionAttribute]
        for attempt in 0..<(order == .production ? 3 : 1) {
            for attribute in attributes {
                let before = now
                let code = AXUIElementSetAttributeValue(element, attribute as CFString,
                                                       attribute == kAXSizeAttribute ? sizeValue : pointValue)
                events.append(["kind": "setter", "attempt": attempt, "attribute": attribute, "code": code.rawValue,
                               "startMS": (before - start) * 1000, "endMS": (now - start) * 1000])
                if order == .production && code != .success { return (false, "\(attribute) returned \(code.rawValue)") }
            }
            if order == .production && attempt > 0 { Thread.sleep(forTimeInterval: 0.035) }
            let actual = frame(element)
            events.append(["kind": "frame", "stage": "attempt-\(attempt)", "atMS": (now - start) * 1000,
                           "frame": actual.map(components) as Any? ?? NSNull()])
            if let actual, matches(actual, rect) { return (true, "frame matched") }
        }
        return (false, "frame mismatch after attempts")
    }
    static func observe(_ rect: CGRect, element: AXUIElement, order: Order) -> [String: Any] {
        let before = frame(element)
        let wallClock = ISO8601DateFormatter().string(from: Date())
        let start = now
        var events: [[String: Any]] = []
        let accepted: Bool
        let reason: String
        if order == .settled {
            let adjustment = FrameSettler.adjust(to: rect, read: {
                let actual = frame(element)
                events.append(["kind": "frame", "atMS": (now - start) * 1000, "frame": actual.map(components) as Any? ?? NSNull()])
                return actual
            }, write: {
                var size = rect.size, point = rect.origin
                guard let s = AXValueCreate(.cgSize, &size), let p = AXValueCreate(.cgPoint, &point) else { return .unavailable }
                let sr = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, s)
                let pr = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, p)
                events.append(["kind": "setter", "atMS": (now - start) * 1000, "sizeCode": sr.rawValue, "positionCode": pr.rawValue])
                guard [.success, .cannotComplete].contains(sr), [.success, .cannotComplete].contains(pr) else { return .unavailable }
                return sr == .success && pr == .success ? .accepted : .retryable
            }, now: { now }, wait: { Thread.sleep(forTimeInterval: $0) })
            accepted = adjustment.reachedTarget
            reason = "Current FrameSettler: writes=\(adjustment.writes), unavailable=\(adjustment.unavailable)"
        } else {
            (accepted, reason) = apply(rect, to: element, order: order, start: start, events: &events)
        }
        let returned = now
        var actual = frame(element)
        events.append(["kind": "frame", "stage": "returned", "atMS": (now - start) * 1000,
                       "frame": actual.map(components) as Any? ?? NSNull()])
        // At most 650ms of additional settling; two 150ms AX getters keep the
        // intended observation bound below one second, even on a slow target.
        while now < returned + 0.65 {
            Thread.sleep(forTimeInterval: min(0.1, max(0, returned + 0.65 - now)))
            actual = frame(element)
            events.append(["kind": "frame", "stage": "settle-no-writes", "atMS": (now - start) * 1000,
                           "frame": actual.map(components) as Any? ?? NSNull()])
        }
        let codes = events.compactMap { $0["code"] as? Int32 }
        let sizeError = events.contains { ($0["attribute"] as? String) == kAXSizeAttribute && ($0["code"] as? Int32) != 0 }
        let sizeMatches = actual.map { abs($0.width - rect.width) <= 2 && abs($0.height - rect.height) <= 2 } ?? false
        let settledMatches = actual.map { matches($0, rect) } ?? false
        return ["order": order.rawValue, "wallClockUTC": wallClock, "startUptimeSeconds": start,
                "before": before.map(components) as Any? ?? NSNull(), "requested": components(rect),
                "acceptedAtReturn": accepted, "returnReason": reason, "returnMS": (returned - start) * 1000,
                "settleElapsedMS": (now - returned) * 1000, "settleWaitBudgetMS": 650,
                "settled": actual.map(components) as Any? ?? NSNull(), "settledMatches": settledMatches,
                "setterErrorWithMatchingFrame": codes.contains(where: { $0 != 0 }) && settledMatches,
                "sizeSetterErrorWithMatchingSize": sizeError && sizeMatches, "events": events]
    }
    static func runCase(_ name: String, destination: CGRect, order: Order, target: AXUIElement,
                        pid: pid_t, original: CGRect, baseline: [Baseline]) throws -> [String: Any] {
        try owned(target, pid: pid, baseline: baseline)
        guard let current = frame(target), matches(current, original) else { throw Stop.restoreFailed }
        var result = observe(destination, element: target, order: order)
        result["name"] = name
        result["productionWouldRollback"] = order == .production && result["acceptedAtReturn"] as? Bool == false
        try owned(target, pid: pid, baseline: baseline)
        result["restore"] = observe(original, element: target, order: .sizePosition)
        result["restored"] = frame(target).map { matches($0, original) } ?? false
        return result
    }

    @MainActor static func main() async {
        do { try await run() }
        catch { print("Diagnostic stopped; sanitized error code: \((error as NSError).code)"); exit(1) }
    }
    @MainActor static func run() async throws {
        _ = NSApplication.shared
        let sandbox = URL(fileURLWithPath: "/tmp/PaneGrid-code-resize-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let output = sandbox.appendingPathComponent("resize-observations.json")
        let process = Process(), pipe = Pipe(), launchOutput = LaunchOutput()
        let pids = NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.VSCode")
            .filter { !$0.isTerminated }.map(\.processIdentifier)
        var baseline: [Baseline] = [], runs: [[String: Any]] = []
        var selected: AXUIElement?, original: CGRect?, launched = false
        var report: [String: Any] = ["target": "fresh empty Code process", "gap": 8, "margin": 8,
            "titlesRead": false, "existingWindowWriteCount": 0, "systemSettingsChanged": false,
            "AXTimeoutSeconds": 0.15, "tolerancePoints": 2,
            "rollbackObservation": "Production decision is measured exactly; rollback is deferred only for bounded read-only settling."]
        do {
            guard AXIsProcessTrusted() else { throw Stop.noTrust }
            baseline = try await onAX {
                try pids.flatMap { pid in try windows(pid).map { Baseline(pid: pid, element: $0, original: frame($0)) } }
            }
            report["baselineCapturedBeforeLaunch"] = true
            let inherited = ProcessInfo.processInfo.environment
            let allowed = Set(["HOME", "USER", "LOGNAME", "PATH", "TMPDIR", "SHELL", "LANG", "__CF_USER_TEXT_ENCODING"])
            process.environment = inherited.filter { allowed.contains($0.key) || $0.key.hasPrefix("LC_") }
            report["inheritedElectronNodeModePresent"] = inherited["ELECTRON_RUN_AS_NODE"] != nil
            report["removedElectronVSCodeNodeKeys"] = inherited.keys.filter {
                $0.hasPrefix("ELECTRON_") || $0.hasPrefix("VSCODE_") || $0.hasPrefix("NODE_")
            }.sorted()
            process.executableURL = URL(fileURLWithPath: "/Applications/Visual Studio Code.app/Contents/MacOS/Code")
            process.currentDirectoryURL = sandbox
            process.arguments = ["--user-data-dir=\(sandbox.path)", "--extensions-dir=\(sandbox.appendingPathComponent("extensions").path)",
                                 "--disable-extensions", "--disable-telemetry", "--disable-updates", "--disable-background-networking",
                                 "--skip-welcome", "--skip-release-notes", "--new-window"]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = pipe; process.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { launchOutput.append($0.availableData) }
            try process.run(); launched = true
            let pid = process.processIdentifier
            report["testPID"] = Int(pid)
            guard !pids.contains(pid) else { throw Stop.unsafeTarget }
            let launchStart = now
            for _ in 0..<160 {
                if !process.isRunning { break }
                selected = try await onAX {
                    let candidates = (try? windows(pid))?.filter {
                        value($0, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole && frame($0) != nil
                    } ?? []
                    return candidates.count == 1 ? candidates[0] : nil
                }
                if selected != nil { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            report["startupMS"] = (now - launchStart) * 1000
            guard let target = selected,
                  NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.microsoft.VSCode" else {
                let root = AXUIElementCreateApplication(pid)
                report["startupAXWindowsCode"] = try await onAX {
                    var raw: CFTypeRef?
                    return AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &raw).rawValue
                }
                throw Stop.noTestWindow
            }
            try await Task.sleep(for: .milliseconds(900))
            let capturedBaseline = baseline
            original = try await onAX {
                try owned(target, pid: pid, baseline: capturedBaseline)
                guard (value(target, kAXDocumentAttribute) as? String ?? "").isEmpty else { throw Stop.unsafeTarget }
                return frame(target)
            }
            guard let original, let primary = NSScreen.screens.first else { throw Stop.noDisplay }
            let screen = NSScreen.screens.max { a, b in
                let first = GridGeometry.flip(a.visibleFrame, primaryHeight: primary.frame.maxY).intersection(original)
                let second = GridGeometry.flip(b.visibleFrame, primaryHeight: primary.frame.maxY).intersection(original)
                return (first.isNull ? 0 : first.width * first.height) < (second.isNull ? 0 : second.width * second.height)
            } ?? primary
            let visible = GridGeometry.flip(screen.visibleFrame, primaryHeight: primary.frame.maxY)
            report["display"] = ["count": NSScreen.screens.count, "visibleAXFrame": components(visible), "scale": screen.backingScaleFactor]
            report["original"] = components(original)
            let auditBefore = try await onAX { audit(capturedBaseline, pids: pids) }
            report["auditBeforeResize"] = auditBefore
            guard auditBefore["allUnchanged"] as? Bool == true else { throw Stop.baselineChanged }
            var destinations = try [(3, 2), (4, 4)].map { columns, rows in
                ("\(columns)x\(rows)", try GridGeometry.frame(for: .init(column: 0, row: 0),
                    grid: .init(columns: columns, rows: rows), visibleFrame: visible, gap: 8, margin: 8, scale: screen.backingScaleFactor))
            }
            let positionProbe = CommandLine.arguments.contains("--positions")
            if positionProbe {
                destinations = try [(0, 0), (1, 0), (2, 0), (2, 1), (2, 2), (0, 2)].map { column, row in
                    ("3x3-cell-\(column)-\(row)", try GridGeometry.frame(for: .init(column: column, row: row),
                        grid: .init(columns: 3, rows: 3), visibleFrame: visible, gap: 8, margin: 8, scale: screen.backingScaleFactor))
                }
            }
            for order in positionProbe ? [Order.settled] : [Order.production, .sizePosition, .positionSize] {
                for (name, destination) in destinations {
                    let result = try await onAX {
                        try runCase(name, destination: destination, order: order, target: target,
                                    pid: pid, original: original, baseline: capturedBaseline)
                    }
                    runs.append(result)
                    print("\(name): matched=\(result["settledMatches"] ?? false) requested=\(result["requested"] ?? []) actual=\(result["settled"] ?? [])")
                    guard result["restored"] as? Bool == true else { throw Stop.restoreFailed }
                }
            }
            report["completed"] = true
        } catch {
            report["completed"] = false
            report["stopReason"] = (error as? Stop)?.rawValue ?? "launch-or-system-error"
            report["errorCode"] = (error as NSError).code
        }
        if launched {
            let pid = process.processIdentifier, capturedBaseline = baseline
            if process.isRunning, let target = selected, let original {
                report["finalRestore"] = try? await onAX {
                    try owned(target, pid: pid, baseline: capturedBaseline)
                    return observe(original, element: target, order: .sizePosition)
                }
            }
            if process.isRunning {
                if let app = NSRunningApplication(processIdentifier: pid) { report["terminateAccepted"] = app.terminate() }
                else { process.terminate() }
                for _ in 0..<40 {
                    if !process.isRunning { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
            }
            if process.isRunning {
                // NSRunningApplication may accept a quit request without exiting.
                // Process is the retained, directly launched child, never a PID lookup
                // of the user's Code instance. SIGTERM is restricted to this child.
                report["sentSIGTERMToOwnedProcess"] = true
                process.terminate()
                for _ in 0..<30 {
                    if !process.isRunning { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
            }
            report["testProcessTerminated"] = !process.isRunning
            report["testWindowClosedWithProcess"] = !process.isRunning
            if !process.isRunning { report["exitStatus"] = process.terminationStatus; report["terminationReason"] = process.terminationReason.rawValue }
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        report["launchOutput"] = launchOutput.summary()
        let capturedBaseline = baseline
        report["auditAfterCleanup"] = try await onAX { audit(capturedBaseline, pids: pids) }
        report["runs"] = runs
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
        print("Private diagnostic: \(output.path)")
        print("Completed: \(report["completed"] as? Bool ?? false); measured cases: \(runs.count); test process terminated: \(report["testProcessTerminated"] as? Bool ?? false)")
    }
}
