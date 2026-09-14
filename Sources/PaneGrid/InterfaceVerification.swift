import AppKit
import SwiftUI
import ApplicationServices
import PaneGridCore

struct VerificationCheck: Codable {
    let name: String
    let passed: Bool
    let detail: String
}

enum VerificationOutput {
    static func url(for flag: String) -> URL? {
        guard let index = CommandLine.arguments.firstIndex(of: flag), CommandLine.arguments.count > index + 1 else { return nil }
        return URL(fileURLWithPath: CommandLine.arguments[index + 1])
    }

    static func finish(kind: String, checks: [VerificationCheck], blocked: String? = nil) -> Never {
        struct Report: Codable {
            var kind: String
            var date: String
            var passed: Bool
            var blocked: String?
            var checks: [VerificationCheck]
        }
        let success = blocked == nil && !checks.isEmpty && checks.allSatisfy(\.passed)
        let report = Report(kind: kind, date: ISO8601DateFormatter().string(from: Date()), passed: success, blocked: blocked, checks: checks)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            if let url = url(for: "--verify-\(kind)") { try data.write(to: url, options: .atomic) }
            FileHandle.standardOutput.write(data + Data("\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("Could not save verification report: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
        exit(blocked != nil ? 77 : success ? 0 : 1)
    }
}

@MainActor
final class InterfaceVerificationDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { await run() }
    }

    private func run() async {
        let state = AppState(ephemeral: true)
        state.isTrusted = false // Exercise the actual permission-needed UI without accessing any external windows.
        var checks: [VerificationCheck] = []

        // Reintroduce the original sizing behavior on an isolated real window. The regression oracle must reject it.
        let legacy = WorkspaceWindow.make(state: state, restoreFrame: false)
        windows.append(legacy)
        (legacy.contentView as? NSHostingView<PaneGridRootView>)?.sizingOptions = .standardBounds
        legacy.orderFrontRegardless()
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(100))
            if legacy.frame.height > 824 { break }
        }
        checks.append(.init(name: "regression-oracle-rejects-intrinsic-window-growth", passed: legacy.frame.height > 824,
                            detail: "Original sizing produced \(Int(legacy.frame.width)) × \(Int(legacy.frame.height)) points; expected 1140 × 800."))
        legacy.orderOut(nil)
        legacy.contentView = nil

        let window = WorkspaceWindow.make(state: state, restoreFrame: false)
        windows.append(window)
        window.orderFrontRegardless()
        let grids: [GridSize] = [.init(columns: 4, rows: 4), .init(columns: 4, rows: 6), .init(columns: 6, rows: 6), .init(columns: 24, rows: 24)]
        for theme in [AppTheme.dark, .light] {
            state.settings.theme = theme
            for grid in grids {
                state.settings.grid = grid
                state.section = .workspace
                try? await Task.sleep(for: .milliseconds(300))
                window.contentView?.layoutSubtreeIfNeeded()
                let fits = abs(window.frame.width - 1140) <= 1 && abs(window.frame.height - 800) <= 1
                checks.append(.init(name: "\(theme.rawValue)-workspace-\(grid.columns)x\(grid.rows)", passed: fits,
                                    detail: "Actual window: \(Int(window.frame.width)) × \(Int(window.frame.height)) points."))
            }
        }
        for section in [WorkspaceSection.layouts, .settings] {
            state.section = section
            try? await Task.sleep(for: .milliseconds(300))
            checks.append(.init(name: "\(section.rawValue)-stays-within-window", passed: window.frame.height <= 801 && window.frame.width <= 1141,
                                detail: "Actual window: \(Int(window.frame.width)) × \(Int(window.frame.height)) points."))
        }
        state.section = .workspace
        state.settings.grid = .init(columns: 4, rows: 4)
        window.setContentSize(NSSize(width: 1050, height: 740))
        try? await Task.sleep(for: .milliseconds(300))
        checks.append(.init(name: "workspace-minimum-size", passed: window.frame.width <= 1051 && window.frame.height <= 741,
                            detail: "Actual minimum-size window: \(Int(window.frame.width)) × \(Int(window.frame.height)) points."))
        // A UI-only target model. No AX reads or window operations occur in this component-size check.
        let target = LiveWindow(id: "ui-sizing-only", element: AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier),
                    app: .init(pid: ProcessInfo.processInfo.processIdentifier, name: "Practice", bundleID: "dev.panegrid.fixture"),
                    title: "Picker sizing check", ordinal: 0, frame: window.frame)
        let picker = NSHostingView(rootView: QuickPickerView(state: state, window: target, preview: { _ in }, close: {}))
        let pickerSize = picker.fittingSize
        checks.append(.init(name: "compact-picker-size-budget", passed: abs(pickerSize.width - 380) <= 1 && (400...620).contains(pickerSize.height),
                    detail: "Picker content measures \(Int(pickerSize.width)) × \(Int(pickerSize.height)) points."))
        state.settings.tileAllAppWindows = true
        let appPicker = NSHostingView(rootView: QuickPickerView(state: state, window: target, preview: { _ in }, close: {}))
        let appPickerSize = appPicker.fittingSize
        checks.append(.init(name: "app-wide-picker-size-budget", passed: abs(appPickerSize.width - 380) <= 1 && (400...620).contains(appPickerSize.height),
                    detail: "App-wide mode measures \(Int(appPickerSize.width)) × \(Int(appPickerSize.height)) points."))
        if let display = state.display {
            let request = AppTileRequest(target: target, grid: .init(columns: 4, rows: 2), columnSpan: 1, rowSpan: 1,
                                         surface: .init(visibleFrame: display.visibleFrame, gap: 8, margin: 8, scale: display.scale),
                                         displayID: display.id, offerAlternatives: true)
            state.appTileFeedback = .init(request: request,
                                         message: "4 × 2 was not applied. This window responded at a larger size. Previous positions restored. Your chosen grid has not been changed.",
                                         suggestedGrid: .init(columns: 2, rows: 4))
            let recovery = NSHostingView(rootView: QuickPickerView(state: state, window: target, preview: { _ in }, close: {}))
            let recoverySize = recovery.fittingSize
            checks.append(.init(name: "persistent-recovery-picker-size-budget", passed: abs(recoverySize.width - 380) <= 1 && recoverySize.height <= 740,
                                detail: "Explicit-alternative feedback measures \(Int(recoverySize.width)) × \(Int(recoverySize.height)) points."))
            state.appTileFeedback = nil
        }
        let ownApp = AppCandidate(pid: ProcessInfo.processInfo.processIdentifier, name: "PaneGrid", bundleID: "dev.panegrid.app")
        let ownPoint = CGPoint(x: window.frame.midX, y: state.primaryHeight - window.frame.midY)
        let hit = await state.access.zoomTarget(at: ownPoint, apps: [ownApp])
        checks.append(.init(name: "own-window-never-hit-tested-by-AX-worker", passed: hit == nil,
                    detail: "The real own-window point is refused without invoking in-process SwiftUI AX hit-testing."))
        VerificationOutput.finish(kind: "interface", checks: checks)
    }
}
