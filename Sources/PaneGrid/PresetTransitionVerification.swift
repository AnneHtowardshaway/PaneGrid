import AppKit
import PaneGridCore

/// Exercises successive commands on the SAME real windows. No Undo/reset between preset changes.
/// The child process and every target AX element are owned by this verifier, never by personal apps.
@MainActor
final class PresetTransitionVerificationDelegate: NSObject, NSApplicationDelegate {
    private var checks: [VerificationCheck] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { await run() }
    }

    private func run() async {
        guard WindowAccess.isTrusted else {
            VerificationOutput.finish(kind: "presets", checks: [], blocked: "Approve the signed PaneGrid app in macOS Accessibility before running the preset transition checks.")
        }
        guard let helper = Bundle.main.resourceURL?.appendingPathComponent("PaneGrid Practice.app/Contents/MacOS/PaneGridFixture"),
              let screen = NSScreen.screens.first else {
            VerificationOutput.finish(kind: "presets", checks: [], blocked: "Run a built app bundle in a logged-in desktop session.")
        }
        let visible = GridGeometry.flip(screen.visibleFrame, primaryHeight: screen.frame.maxY)
        let surface = TilingSurface(visibleFrame: visible, gap: 8, margin: 8, scale: screen.backingScaleFactor)
        for mode in ["standard", "coalesced", "animatedAxes"] {
            let process = Process()
            process.executableURL = helper
            process.arguments = mode == "animatedAxes" ? ["--verify-animated-axes"] : mode == "coalesced" ? ["--verify-coalesced-resize"] : []
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                defer { if process.isRunning { process.terminate() } }
                let access = WindowAccess()
                let app = AppCandidate(pid: process.processIdentifier, name: "PaneGrid Practice", bundleID: "dev.panegrid.fixture")
                var windows: [LiveWindow] = []
                for _ in 0..<30 {
                    windows = await access.windows(in: [app])
                    if windows.count == 6 { break }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard windows.count == 6, let target = windows.first else {
                    checks.append(.init(name: "\(mode)-six-isolated-windows", passed: false, detail: "Fixture did not expose six eligible windows.")); continue
                }
                let identifier = await access.identifier(of: target)
                let modeConfirmed = identifier == "panegrid.fixture.\(mode)"
                checks.append(.init(name: "\(mode)-response-mode", passed: modeConfirmed, detail: "Verified the actual window's test-mode identifier."))
                guard modeConfirmed else { continue }
                let grids: [GridSize] = [.init(columns: 3, rows: 2), .init(columns: 4, rows: 2),
                                         .init(columns: 3, rows: 2), .init(columns: 4, rows: 2)]
                for (index, grid) in grids.enumerated() {
                    let result = await ApplicationTiler.tile(target: target, access: access, grid: grid, surface: surface, autoFit: false)
                    let expected = try EqualTilePlanner.plan(windowIDs: windows.map(\.id), grid: grid)
                        .map { try surface.frame($0.region, grid: grid) }
                    let correctNow = await matchesExactlyOneEach(windows: windows, expected: expected, access: access)
                    // Longer than both the receiver's debounce and the old setter's retry interval.
                    try? await Task.sleep(for: .milliseconds(1800))
                    let correctLater = await matchesExactlyOneEach(windows: windows, expected: expected, access: access)
                    checks.append(.init(name: "\(mode)-command-\(index + 1)-\(grid.columns)x\(grid.rows)",
                                        passed: result.report.succeeded && result.usedGrid == grid && !result.adapted && correctNow && correctLater,
                                        detail: "Requested \(grid.label); used \(result.usedGrid.label). Immediate fit: \(correctNow); fit after 1.8s: \(correctLater). \(result.report.message)"))
                }
                // Exercise the real main-actor command controller, not just the native service.
                // Its middle pending request must be superseded; the final eighths command must win.
                let state = AppState(ephemeral: true)
                state.settings.tileAllAppWindows = true
                state.settings.autoFitAppWindows = true
                let sixths = GridSize(columns: 3, rows: 2)
                let eighths = GridSize(columns: 4, rows: 2)
                state.tileApplication(target, requestedGrid: sixths)
                state.tileApplication(target, requestedGrid: .init(columns: 6, rows: 2))
                state.tileApplication(target, requestedGrid: eighths)
                let completed = await waitUntilIdle(state)
                let expectedEighths = try EqualTilePlanner.plan(windowIDs: windows.map(\.id), grid: eighths)
                    .map { try surface.frame($0.region, grid: eighths) }
                let finalMatches = await matchesExactlyOneEach(windows: windows, expected: expectedEighths, access: access)
                checks.append(.init(name: "\(mode)-latest-queued-preset-wins", passed: completed && finalMatches && state.settings.grid == eighths,
                                    detail: "Submitted sixths → twelfths → eighths without awaiting completion. Latest grid: \(state.settings.grid.label). \(state.notice.text)"))
                checks.append(.init(name: "\(mode)-superseded-command-does-not-run", passed: completed && state.undoDepth == 2,
                                    detail: "Only the active sixths and newest queued eighths transactions should create undo entries; observed \(state.undoDepth)."))
                state.undo()
                let undone = await waitUntilIdle(state)
                let expectedSixths = try EqualTilePlanner.plan(windowIDs: windows.map(\.id), grid: sixths)
                    .map { try surface.frame($0.region, grid: sixths) }
                let priorMatches = await matchesExactlyOneEach(windows: windows, expected: expectedSixths, access: access)
                checks.append(.init(name: "\(mode)-transition-undo-restores-only-prior-command", passed: undone && priorMatches && state.undoDepth == 1,
                                    detail: "One explicit Undo restores sixths, not the skipped pending preset."))

                // The reported failure starts specifically after using Workspace, not just presets.
                state.windows = windows
                state.selectedIDs = Set(windows.map(\.id))
                for (index, grid) in [GridSize(columns: 3, rows: 3), eighths, GridSize(columns: 3, rows: 3)].enumerated() {
                    state.setGrid(grid)
                    if index == 1 { state.tileApplication(target, requestedGrid: grid) }
                    else { state.applyDraft() }
                    let idle = await waitUntilIdle(state)
                    let expected = try EqualTilePlanner.plan(windowIDs: windows.map(\.id), grid: grid).map { try surface.frame($0.region, grid: grid) }
                    try? await Task.sleep(for: .milliseconds(1100))
                    let correct = await matchesExactlyOneEach(windows: windows, expected: expected, access: access)
                    checks.append(.init(name: "\(mode)-mixed-entry-\(index + 1)-\(grid.columns)x\(grid.rows)",
                                        passed: idle && !state.notice.isError && correct && state.settings.grid == grid,
                                        detail: "Workspace → app-wide picker → Workspace, without Undo/reset. \(state.notice.text)"))
                }
                if mode == "animatedAxes" {
                    state.setGrid(sixths)
                    state.applyDraft()
                    try? await Task.sleep(for: .milliseconds(150))
                    state.cancelArrangement()
                    let idle = await waitUntilIdle(state)
                    try? await Task.sleep(for: .milliseconds(700))
                    let beforeCancel = try EqualTilePlanner.plan(windowIDs: windows.map(\.id), grid: .init(columns: 3, rows: 3))
                        .map { try surface.frame($0.region, grid: .init(columns: 3, rows: 3)) }
                    let cancelledFramesRestored = await matchesExactlyOneEach(windows: windows, expected: beforeCancel, access: access)
                    checks.append(.init(name: "cancel-releases-busy-state", passed: idle && !state.cancelRequested,
                                        detail: "Cancel completes bounded rollback; controls become usable again. \(state.notice.text)"))
                    checks.append(.init(name: "cancel-drains-pending-animation-before-restore", passed: idle && cancelledFramesRestored,
                                        detail: "The pre-cancel full layout still matches after a further 700ms; no latent axis write may reappear."))
                    state.tileApplication(target, requestedGrid: eighths)
                    let recovered = await waitUntilIdle(state)
                    let correct = await matchesExactlyOneEach(windows: windows, expected: expectedEighths, access: access)
                    checks.append(.init(name: "arrange-after-cancel-is-not-poisoned", passed: recovered && correct && !state.notice.isError,
                                        detail: "A cancelled Workspace arrangement does not poison the next app-wide command."))
                }
            } catch { checks.append(.init(name: "\(mode)-execution", passed: false, detail: error.localizedDescription)) }
        }
        VerificationOutput.finish(kind: "presets", checks: checks)
    }

    private func waitUntilIdle(_ state: AppState) async -> Bool {
        for _ in 0..<500 {
            if !state.isBusy { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return !state.isBusy
    }

    private func matchesExactlyOneEach(windows: [LiveWindow], expected: [CGRect], access: WindowAccess) async -> Bool {
        var remaining = expected
        for window in windows {
            guard let actual = await access.actualFrame(of: window), let match = remaining.firstIndex(where: { expected in
                zip([actual.origin.x, actual.origin.y, actual.size.width, actual.size.height],
                    [expected.origin.x, expected.origin.y, expected.size.width, expected.size.height])
                    .allSatisfy { abs($0 - $1) <= 2 }
            }) else { return false }
            remaining.remove(at: match)
        }
        return remaining.isEmpty && windows.count == expected.count
    }
}
