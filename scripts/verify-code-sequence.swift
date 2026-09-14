// Compile with WindowAccess.swift, ApplicationTiler.swift and the built PaneGridCore module.
// Launches an empty, isolated Code process. Never writes to an existing Code window.
import AppKit
import ApplicationServices
import PaneGridCore

@main
struct CodeSequenceProbe {
    @MainActor static func main() async {
        _ = NSApplication.shared
        var report: [String: Any] = ["checks": [[String: Any]](), "existingWindowWrites": 0]
        let args = CommandLine.arguments
        let reportURL = URL(fileURLWithPath: args.count > 1 ? args[1] : "/tmp/PaneGrid-code-sequence.json")
        let sandbox = URL(fileURLWithPath: "/tmp").appendingPathComponent("pg-code-\(UUID().uuidString.prefix(8))")
        let process = Process()
        var checks: [[String: Any]] = []
        func record(_ name: String, _ passed: Bool, _ detail: [String: Any]) {
            checks.append(["name": name, "passed": passed, "detail": detail])
            print("\(passed ? "PASS" : "FAIL") \(name): \(detail)")
        }
        do {
            guard AXIsProcessTrusted(), let screen = NSScreen.screens.first else { throw NSError(domain: "Prerequisite", code: 77) }
            try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let existing = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.VSCode").map(\.processIdentifier))
            let baseline = snapshotExisting(existing)
            process.executableURL = URL(fileURLWithPath: "/Applications/Visual Studio Code.app/Contents/MacOS/Code")
            let allowed = Set(["HOME", "USER", "LOGNAME", "PATH", "TMPDIR", "SHELL", "LANG", "__CF_USER_TEXT_ENCODING"])
            process.environment = ProcessInfo.processInfo.environment.filter { allowed.contains($0.key) || $0.key.hasPrefix("LC_") }
            process.currentDirectoryURL = sandbox
            process.arguments = ["--user-data-dir=\(sandbox.path)", "--extensions-dir=\(sandbox.path)/extensions", "--disable-extensions",
                                 "--disable-telemetry", "--disable-updates", "--disable-background-networking", "--skip-welcome", "--skip-release-notes",
                                 "--force-renderer-accessibility", "--new-window"]
            let launchLog = sandbox.appendingPathComponent("startup.log")
            FileManager.default.createFile(atPath: launchLog.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let launchOutput = try FileHandle(forWritingTo: launchLog)
            process.standardInput = FileHandle.nullDevice; process.standardOutput = launchOutput; process.standardError = launchOutput
            try process.run()
            let pid = process.processIdentifier
            guard !existing.contains(pid) else { throw NSError(domain: "UnsafeTarget", code: 1) }
            let app = AppCandidate(pid: pid, name: "Code test", bundleID: "com.microsoft.VSCode")
            let access = WindowAccess()
            var windows: [LiveWindow] = []
            for _ in 0..<100 {
                windows = await access.windows(in: [app])
                if windows.count == 1 { break }
                if !process.isRunning { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            if windows.count != 1 {
                let root = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(root, 0.3)
                let raw = WindowAccess.value(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
                record("startup-detail", false, ["processRunning": process.isRunning, "exit": process.isRunning ? -1 : Int(process.terminationStatus),
                                                "eligible": windows.count, "rawWindows": raw.count,
                                                "roles": raw.map { WindowAccess.value($0, kAXSubroleAttribute) as? String ?? "none" },
                                                "frames": raw.compactMap { WindowAccess.frame($0).map(components) }])
                let log = (try? String(contentsOf: launchLog, encoding: .utf8)) ?? ""
                report["startupDiagnostic"] = String(log.prefix(2500)).replacingOccurrences(of: sandbox.path, with: "[isolated-profile]")
                print("Isolated launch diagnostic: \(report["startupDiagnostic"] ?? "")")
            }
            guard let window = windows.first, windows.count == 1 else { throw NSError(domain: "NoIsolatedWindow", code: 1) }
            try? await Task.sleep(for: .milliseconds(500))
            let enhanced = WindowAccess.value(AXUIElementCreateApplication(pid), "AXEnhancedUserInterface") as? Bool ?? false
            report["enhancedUIObserved"] = enhanced
            let visible = GridGeometry.flip(screen.visibleFrame, primaryHeight: screen.frame.maxY)
            let surface = TilingSurface(visibleFrame: visible, gap: 8, margin: 8, scale: screen.backingScaleFactor)
            let steps: [(GridSize, GridRegion)] = [
                (.init(columns: 4, rows: 3), .init(column: 3, row: 1)),
                (.init(columns: 3, rows: 3), .init(column: 2, row: 1)),
                (.init(columns: 4, rows: 2), .init(column: 3, row: 1)),
                (.init(columns: 3, rows: 2), .init(column: 2, row: 1)),
                (.init(columns: 3, rows: 3), .init(column: 1, row: 1))
            ]
            for (index, step) in steps.enumerated() {
                guard process.isRunning else { throw NSError(domain: "TestProcessExited", code: 1) }
                let destination = try surface.frame(step.1, grid: step.0)
                let started = ProcessInfo.processInfo.systemUptime
                let result = await access.apply([.init(window: window, destination: destination)])
                try? await Task.sleep(for: .milliseconds(1200))
                let actual = await access.actualFrame(of: window)
                let passed = result.succeeded && actual.map { WindowAccess.close($0, destination) } == true
                record("step-\(index + 1)-\(step.0.columns)x\(step.0.rows)", passed,
                       ["requested": components(destination), "actual": actual.map(components) ?? [], "seconds": ProcessInfo.processInfo.systemUptime - started,
                        "message": result.message])
            }
            record("existing-Code-windows-untouched", snapshotExisting(existing) == baseline, ["processes": existing.count])
        } catch { record("probe-prerequisite", false, ["domain": (error as NSError).domain, "code": (error as NSError).code]) }
        if process.isRunning { process.terminate() }
        for _ in 0..<40 {
            if !process.isRunning { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        report["testProcessTerminated"] = !process.isRunning
        report["checks"] = checks
        report["passed"] = !checks.isEmpty && checks.allSatisfy { $0["passed"] as? Bool == true }
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: reportURL, options: .atomic) }
        print("Report: \(reportURL.path)")
        exit(report["passed"] as? Bool == true ? 0 : 1)
    }

    static func components(_ r: CGRect) -> [Double] { [r.minX, r.minY, r.width, r.height] }
    static func snapshotExisting(_ pids: Set<pid_t>) -> [String: [Double]] {
        // Public window geometry only. No personal titles, document contents, or identifiers are printed.
        let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var result: [String: [Double]] = [:]
        for item in info {
            guard let pid = item[kCGWindowOwnerPID as String] as? Int32, pids.contains(pid),
                  item[kCGWindowLayer as String] as? Int == 0,
                  let id = item[kCGWindowNumber as String] as? Int,
                  let raw = item[kCGWindowBounds as String] as? NSDictionary, let frame = CGRect(dictionaryRepresentation: raw) else { continue }
            result["\(pid):\(id)"] = components(frame)
        }
        return result
    }
}
