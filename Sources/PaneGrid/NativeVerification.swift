import AppKit
import ApplicationServices
import PaneGridCore

/// Runs only against the bundled practice app. Never selects or moves the user's application windows.
@MainActor
final class NativeVerificationDelegate: NSObject, NSApplicationDelegate {
    private let access = WindowAccess()
    private var checks: [VerificationCheck] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { await run() }
    }

    private func run() async {
        guard WindowAccess.isTrusted else {
            VerificationOutput.finish(kind: "native", checks: [], blocked: "Enable PaneGrid in System Settings → Privacy & Security → Accessibility, then rerun the native checks.")
        }
        guard let helper = Bundle.main.resourceURL?.appendingPathComponent("PaneGrid Practice.app"),
              FileManager.default.fileExists(atPath: helper.path) else {
            VerificationOutput.finish(kind: "native", checks: [], blocked: "Run the installed app bundle, which includes the practice app.")
        }
        let fixtureProcess = Process()
        fixtureProcess.executableURL = helper.appendingPathComponent("Contents/MacOS/PaneGridFixture")
        fixtureProcess.standardInput = FileHandle.nullDevice
        fixtureProcess.standardOutput = FileHandle.nullDevice
        fixtureProcess.standardError = FileHandle.nullDevice
        do { try fixtureProcess.run() }
        catch { VerificationOutput.finish(kind: "native", checks: [], blocked: error.localizedDescription) }
        let fixtureCandidate = AppCandidate(pid: fixtureProcess.processIdentifier, name: "PaneGrid Practice", bundleID: "dev.panegrid.fixture")
        var windows: [LiveWindow] = []
        for _ in 0..<25 {
            windows = await access.windows(in: [fixtureCandidate])
            if windows.count == 6 { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard windows.count == 6, windows.allSatisfy({ $0.app.bundleID == "dev.panegrid.fixture" }),
              let screen = NSScreen.screens.first else {
                        fixtureProcess.terminate()
                        VerificationOutput.finish(kind: "native", checks: [], blocked: "The newly launched verification fixture did not expose six windows.")
        }
        windows.sort { $0.title < $1.title }
        checks.append(.init(name: "fixture-isolation", passed: true, detail: "Exactly six windows from the bundled practice process; no personal apps targeted."))
        let visible = GridGeometry.flip(screen.visibleFrame, primaryHeight: Double(screen.frame.maxY))
        var originals: [String: CGRect] = [:]
        for window in windows { originals[window.id] = await access.actualFrame(of: window) }
        guard originals.count == 6 else {
            fixtureProcess.terminate()
            VerificationOutput.finish(kind: "native", checks: checks, blocked: "A practice window disappeared.")
        }

        do {
            for grid in [GridSize(columns: 3, rows: 2), .init(columns: 4, rows: 2), .init(columns: 4, rows: 4),
                         .init(columns: 4, rows: 6), .init(columns: 6, rows: 6)] {
                let selected = Array(windows.prefix(3))
                let plan = try LayoutPlanner.pack(windowIDs: selected.map(\.id), grid: grid)
                let moves = try plan.placements.compactMap { placement -> WindowMove? in
                    guard let window = selected.first(where: { $0.id == placement.windowID }) else { return nil }
                    let frame = try GridGeometry.frame(for: placement.region, grid: grid, visibleFrame: visible,
                                                       gap: 8, margin: 8, scale: screen.backingScaleFactor)
                    return .init(window: window, destination: frame)
                }
                let report = await access.apply(moves)
                let correct = await framesMatch(moves)
                checks.append(.init(name: "resize-\(grid.columns)x\(grid.rows)", passed: report.succeeded && correct, detail: report.message))
                checks.append(.init(name: "unselected-unchanged-\(grid.columns)x\(grid.rows)",
                                    passed: await unchanged(Array(windows.dropFirst(3)), originals: originals), detail: "Independent frame reads for the three unselected practice windows."))
                if report.succeeded {
                    let undo = await access.undo()
                    let restored = await unchanged(windows, originals: originals)
                    checks.append(.init(name: "undo-\(grid.columns)x\(grid.rows)", passed: undo.succeeded && restored, detail: "All original fixture frames restored."))
                } else { break }
            }

            let grid = GridSize(columns: 4, rows: 4)
            let plan = try LayoutPlanner.pack(windowIDs: Array(windows.prefix(3)).map(\.id), grid: grid,
                                              reserved: [.init(windowID: windows[0].id, region: .init(column: 1, row: 1, columnSpan: 2, rowSpan: 2))])
            let moves = try plan.placements.compactMap { placement -> WindowMove? in
                guard let window = windows.first(where: { $0.id == placement.windowID }) else { return nil }
                return .init(window: window, destination: try GridGeometry.frame(for: placement.region, grid: grid,
                             visibleFrame: visible, gap: 8, margin: 8, scale: screen.backingScaleFactor))
            }
            let reflow = await access.apply(moves)
            let reflowMatches = await framesMatch(moves)
            checks.append(.init(name: "span-and-selected-group-reflow", passed: reflow.succeeded && reflowMatches, detail: reflow.message))
            checks.append(.init(name: "reflow-leaves-unselected-alone", passed: await unchanged(Array(windows.dropFirst(3)), originals: originals), detail: "No extra windows entered the group."))
            if reflow.succeeded {
                let undo = await access.undo()
                let restored = await unchanged(windows, originals: originals)
                checks.append(.init(name: "undo-reflow", passed: undo.succeeded && restored, detail: "Spanned layout is undoable."))
            }

            if let first = originals[windows[0].id] {
                let reject = await access.apply([
                    .init(window: windows[0], destination: first.offsetBy(dx: 24, dy: 12)),
                    .init(window: windows[1], destination: CGRect(x: visible.minX + 10, y: visible.minY + 10, width: 24, height: 24))
                ])
                checks.append(.init(name: "minimum-size-rejection", passed: !reject.succeeded, detail: reject.message))
                checks.append(.init(name: "partial-failure-rolls-back", passed: await unchanged(windows, originals: originals), detail: "Actual frames checked after the second move was refused."))
                let undo = await access.undo()
                checks.append(.init(name: "failed-arrangement-does-not-create-undo", passed: !undo.succeeded, detail: undo.message))
            }

            if let application = NSRunningApplication(processIdentifier: windows[0].app.pid) { application.activate(options: [.activateAllWindows]) }
            try? await Task.sleep(for: .milliseconds(250))
            if let focused = await access.focusedWindow(in: windows[0].app), let button = await access.zoomButtonFrame(of: focused) {
                let hit = await access.zoomTarget(at: CGPoint(x: button.midX, y: button.midY), apps: [windows[0].app])
                checks.append(.init(name: "real-green-button-hit-test", passed: hit?.window.id == focused.id, detail: "Public AX hit-testing found the exact green button and its owning window."))
            } else {
                checks.append(.init(name: "real-green-button-hit-test", passed: false, detail: "No zoom button was exposed for the practice window."))
            }
        } catch { checks.append(.init(name: "native-execution", passed: false, detail: error.localizedDescription)) }

        // Restore the isolated practice windows even if an assertion failed.
        let restore = windows.compactMap { window -> WindowMove? in
            guard let frame = originals[window.id] else { return nil }
            return .init(window: window, destination: frame)
        }
        _ = await access.apply(restore)
        checks.append(.init(name: "fixture-cleanup", passed: await unchanged(windows, originals: originals), detail: "All practice windows returned to their starting frames."))
        await verifyAppWide(windows: windows, originals: originals, visible: visible, scale: screen.backingScaleFactor)
        await verifyConstrainedAndDelayedFixtures(helper: helper, protected: windows, originals: originals, visible: visible, scale: screen.backingScaleFactor)
        fixtureProcess.terminate()
        VerificationOutput.finish(kind: "native", checks: checks)
    }

    private func verifyAppWide(windows: [LiveWindow], originals: [String: CGRect], visible: CGRect, scale: Double) async {
        let surface = TilingSurface(visibleFrame: visible, gap: 8, margin: 8, scale: scale)
        let grid = GridSize(columns: 3, rows: 2)
        let report = await ApplicationTiler.tile(target: windows[0], access: access, grid: grid, surface: surface, autoFit: true)
        let discovered = (try? await access.applicationWindows(containing: windows[0])) ?? []
        let plan = try? EqualTilePlanner.plan(windowIDs: discovered.map(\.id), grid: grid)
        let moves = (plan ?? []).compactMap { placement -> WindowMove? in
            guard let window = discovered.first(where: { $0.id == placement.windowID }),
                  let frame = try? surface.frame(placement.region, grid: grid) else { return nil }
            return .init(window: window, destination: frame)
        }
        let matches = await framesMatch(moves)
        checks.append(.init(name: "all-app-windows-with-no-manual-selection", passed: report.report.succeeded && discovered.count == 6 && moves.count == 6 && matches,
                            detail: report.report.message))
        try? await Task.sleep(for: .milliseconds(700))
        checks.append(.init(name: "all-app-tiling-does-not-snap-back", passed: await framesMatch(moves), detail: "Independent frames still match 700ms after completion."))
        if report.report.succeeded {
            let undo = await access.undo()
            let restored = await unchanged(windows, originals: originals)
            checks.append(.init(name: "all-app-single-undo", passed: undo.succeeded && restored, detail: "One Undo restores the entire app-wide arrangement."))
        }
        let overflow = await ApplicationTiler.tile(target: windows[0], access: access, grid: .init(columns: 2, rows: 2), surface: surface, autoFit: false)
        let untouched = await unchanged(windows, originals: originals)
        checks.append(.init(name: "all-app-overflow-moves-nothing", passed: !overflow.report.succeeded && untouched, detail: overflow.report.message))
    }

    private func verifyConstrainedAndDelayedFixtures(helper: URL, protected: [LiveWindow], originals: [String: CGRect], visible: CGRect, scale: Double) async {
        for mode in ["--verify-size-constraints", "--verify-delayed-resize"] {
            let existing = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "dev.panegrid.fixture").map(\.processIdentifier))
            do {
                let process = Process()
                process.executableURL = helper.appendingPathComponent("Contents/MacOS/PaneGridFixture")
                process.arguments = [mode]
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try process.run()
                guard !existing.contains(process.processIdentifier) else {
                    checks.append(.init(name: "isolated-fixture-launch", passed: false, detail: "A distinct fixture instance was not created; no windows touched.")); continue
                }
                defer { if process.isRunning { process.terminate() } }
                let candidate = AppCandidate(pid: process.processIdentifier, name: "PaneGrid Practice", bundleID: "dev.panegrid.fixture")
                let localAccess = WindowAccess()
                var owned: [LiveWindow] = []
                for _ in 0..<30 {
                    owned = await localAccess.windows(in: [candidate])
                    if owned.count == 6 { break }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard owned.count == 6, let target = owned.first else {
                    checks.append(.init(name: "isolated-fixture-windows", passed: false, detail: "Expected six windows owned by the new process.")); continue
                }
                let expectedMode = mode == "--verify-size-constraints" ? "panegrid.fixture.constraints" : "panegrid.fixture.delayed"
                let identifier = await localAccess.identifier(of: target)
                checks.append(.init(name: "\(mode)-mode-confirmed", passed: identifier == expectedMode,
                                    detail: "Expected \(expectedMode); observed \(identifier ?? "missing"). Initial frame: \(Int(target.frame.width)) × \(Int(target.frame.height))."))
                guard identifier == expectedMode else { continue }
                let initial = Dictionary(uniqueKeysWithValues: owned.map { ($0.id, $0.frame) })
                let surface = TilingSurface(visibleFrame: visible, gap: 8, margin: 8, scale: scale)
                if mode == "--verify-size-constraints" {
                    // Display scaling can change during a session. Require a genuinely sub-1000pt tile.
                    let requested = GridSize(columns: max(3, Int((visible.width - 8) / 1008) + 1), rows: 2)
                    let requestedCell = try surface.frame(.init(column: 0, row: 0), grid: requested)
                    let result = await ApplicationTiler.tile(target: target, access: localAccess, grid: requested, surface: surface, autoFit: true)
                    var originalsRestored = true
                    for window in owned {
                        guard let actual = await localAccess.actualFrame(of: window), let original = initial[window.id] else { originalsRestored = false; continue }
                        originalsRestored = originalsRestored && same(actual, original)
                    }
                    checks.append(.init(name: "size-limit-does-not-auto-replace-requested-preset",
                                        passed: requestedCell.width < 998 && !result.report.succeeded && !result.adapted && result.usedGrid == requested && originalsRestored,
                                        detail: "Requested \(requested.label). No replacement grid may run until explicitly accepted. \(result.report.message)"))
                    let noUndo = await localAccess.undo()
                    checks.append(.init(name: "suggestion-does-not-create-undo", passed: !noUndo.succeeded, detail: noUndo.message))
                    guard let suggested = result.suggestedGrid, suggested != requested else {
                        checks.append(.init(name: "real-minimum-size-produces-explicit-alternative", passed: false, detail: "No fitting alternative was offered for the observed 1000pt width response.")); continue
                    }
                    let accepted = await ApplicationTiler.tile(target: target, access: localAccess, grid: suggested, surface: surface, autoFit: false)
                    let cells = try EqualTilePlanner.plan(windowIDs: owned.map(\.id), grid: suggested)
                    var actuals: [CGRect] = []
                    for window in owned { if let actual = await localAccess.actualFrame(of: window) { actuals.append(actual) } }
                    var expected = try cells.map { try surface.frame($0.region, grid: suggested) }
                    // Each expected position must be used once; duplicate/overlapping frames are not a pass.
                    for actual in actuals {
                        if let index = expected.firstIndex(where: { same($0, actual) }) { expected.remove(at: index) }
                    }
                    let equalCells = actuals.count == 6 && expected.isEmpty
                    checks.append(.init(name: "explicit-alternative-respects-real-minimum-width", passed: accepted.report.succeeded && accepted.usedGrid == suggested && equalCells,
                                        detail: "After explicit acceptance, used \(suggested.label). Six windows require at least 1000pt width. \(accepted.report.message)"))
                    if accepted.report.succeeded {
                        let undo = await localAccess.undo()
                        var restored = true
                        for window in owned {
                            guard let actual = await localAccess.actualFrame(of: window), let original = initial[window.id] else { restored = false; continue }
                            restored = restored && same(actual, original)
                        }
                        checks.append(.init(name: "explicit-alternative-one-undo-restores-originals", passed: undo.succeeded && restored, detail: "Only the explicitly accepted alternative creates an undo entry."))
                    }
                } else {
                    let destination = try surface.frame(.init(column: 0, row: 0), grid: .init(columns: 3, rows: 2))
                    let legacyAccepted = await legacyResizeForRegression(target, destination: destination)
                    checks.append(.init(name: "legacy-resize-rejects-real-delayed-fixture", passed: !legacyAccepted, detail: "The exact old three-pass/35ms loop was exercised on an isolated delayed AX window."))
                    try? await Task.sleep(for: .milliseconds(300))
                    _ = await localAccess.apply([.init(window: target, destination: target.frame)])
                    let result = await localAccess.apply([.init(window: target, destination: destination)])
                    try? await Task.sleep(for: .milliseconds(700))
                    let actual = await localAccess.actualFrame(of: target)
                    checks.append(.init(name: "delayed-native-resize-stays-applied", passed: result.succeeded && actual.map { same($0, destination) } == true,
                                        detail: "New settling logic must succeed and still match 700ms later. \(result.message)"))
                }
                checks.append(.init(name: "\(mode)-other-instance-untouched", passed: await unchanged(protected, originals: originals),
                                    detail: "The original six windows from the same bundle ID were excluded by exact target PID."))
            } catch { checks.append(.init(name: mode, passed: false, detail: error.localizedDescription)) }
        }
    }

    private func legacyResizeForRegression(_ target: LiveWindow, destination: CGRect) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Test-only reintroduction of the original algorithm, against an explicitly created fixture element.
                var size = destination.size, point = destination.origin
                guard let sizeValue = AXValueCreate(.cgSize, &size), let pointValue = AXValueCreate(.cgPoint, &point) else {
                    continuation.resume(returning: false); return
                }
                for attempt in 0..<3 {
                    guard AXUIElementSetAttributeValue(target.element, kAXSizeAttribute as CFString, sizeValue) == .success,
                          AXUIElementSetAttributeValue(target.element, kAXPositionAttribute as CFString, pointValue) == .success else {
                        continuation.resume(returning: false); return
                    }
                    if attempt > 0 { Thread.sleep(forTimeInterval: 0.035) }
                    if let actual = WindowAccess.frame(target.element), FrameSettler.matches(actual, destination) {
                        continuation.resume(returning: true); return
                    }
                }
                continuation.resume(returning: false)
            }
        }
    }

    private func framesMatch(_ moves: [WindowMove]) async -> Bool {
        for move in moves {
            guard let actual = await access.actualFrame(of: move.window), same(actual, move.destination) else { return false }
        }
        return true
    }

    private func unchanged(_ windows: [LiveWindow], originals: [String: CGRect]) async -> Bool {
        for window in windows {
            guard let expected = originals[window.id], let actual = await access.actualFrame(of: window), same(actual, expected) else { return false }
        }
        return true
    }

    /// Separate oracle: do not call the production frame-comparison function.
    private func same(_ a: CGRect, _ b: CGRect) -> Bool {
        zip([a.origin.x, a.origin.y, a.size.width, a.size.height], [b.origin.x, b.origin.y, b.size.width, b.size.height])
            .allSatisfy { abs($0 - $1) <= 2 }
    }
}
