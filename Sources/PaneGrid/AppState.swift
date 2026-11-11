import AppKit
import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers
import PaneGridCore

struct DisplayInfo: Identifiable {
    let id: String
    let name: String
    let cocoaFrame: CGRect
    let cocoaVisibleFrame: CGRect
    let visibleFrame: CGRect
    let scale: Double
}

enum WorkspaceSection: String, CaseIterable {
    case workspace = "Workspace", layouts = "Saved layouts", settings = "Settings"
    /// 侧边栏标题。rawValue 同时充当文案层的英文键，不参与持久化。
    var title: String { Localization.t(rawValue) }
    var symbol: String {
        switch self { case .workspace: return "rectangle.split.3x3"; case .layouts: return "square.stack.3d.up"; case .settings: return "slider.horizontal.3" }
    }
}

/// 一条状态提示。以文案键构造的提示会在切换语言后重新渲染；由运行时结果拼装的文本按原样保留。
struct AppNotice {
    var text: String
    var isError: Bool = false
    private var key: String?
    private var arguments: [CVarArg] = []

    init(text: String, isError: Bool = false) {
        self.text = text
        self.isError = isError
    }

    /// 使用文案层键构造。所有参数按 `String(format:)` 规则解释，整数请用 `%ld`。
    init(key: String, _ arguments: CVarArg..., isError: Bool = false) {
        self.key = key
        self.arguments = arguments
        self.isError = isError
        text = Localization.tf(key, arguments)
    }

    /// 语言切换后调用；没有文案键的提示保持原文。
    func relocalized() -> AppNotice {
        guard let key else { return self }
        var value = self
        value.text = Localization.tf(key, arguments)
        return value
    }
}

struct AppTileRequest {
    let target: LiveWindow
    let grid: GridSize
    let columnSpan: Int
    let rowSpan: Int
    let surface: TilingSurface
    let displayID: String
    let offerAlternatives: Bool
}

struct AppTileFeedback {
    let request: AppTileRequest
    let message: String
    let suggestedGrid: GridSize?
}

@MainActor
final class AppState: ObservableObject {
    let access = WindowAccess()
    private let store = LocalStore()
    private let ephemeral: Bool
    @Published var settings: AppSettings {
        didSet {
            // 语言属于界面设置：先同步文案层，再触发重绘，切换后无需重启即可生效。
            Localization.language = settings.language
            if settings.language != oldValue.language { notice = notice.relocalized() }
            appTileFeedback = nil
            if settings.grid != oldValue.grid { assignments = [:]; region = .init(column: 0, row: 0) }
            scheduleSave()
            onPreferencesChanged?()
            if settings.excludedBundleIDs != oldValue.excludedBundleIDs { refresh() }
        }
    }
    @Published var layouts: [SavedLayout] { didSet { scheduleSave() } }
    @Published var windows: [LiveWindow] = []
    @Published var windowSearch = ""
    @Published var selectedIDs: Set<String> = []
    @Published var assignments: [String: GridRegion] = [:]
    @Published var region = GridRegion(column: 0, row: 0)
    @Published var displays: [DisplayInfo] = []
    @Published var displayID = "" { didSet { if displayID != oldValue { appTileFeedback = nil } } }
    @Published var appTileFeedback: AppTileFeedback?
    @Published var section: WorkspaceSection = .workspace
    @Published var notice = AppNotice(key: "Select windows, draw a tile, and make it yours.")
    @Published var isTrusted = WindowAccess.isTrusted
    @Published var isBusy = false
    @Published var cancelRequested = false
    @Published var isScanning = false
    @Published var isPaused = false { didSet { if isPaused { pendingAppTile = nil; cancelArrangement() }; onPreferencesChanged?() } }
    @Published var undoDepth = 0
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    var onPreferencesChanged: (() -> Void)?
    var onShowWorkspace: (() -> Void)?
    var onShowPicker: (() -> Void)?
    var onDismissPicker: (() -> Void)?
    var onPreview: ((GridRegion?) -> Void)?
    var onResult: ((AppNotice) -> Void)?
    var onAppTilingFailure: ((LiveWindow) -> Void)?
    var lastExternalApp: AppCandidate?
    private var saveWork: DispatchWorkItem?
    private var scanGeneration = 0
    private var activeAppTile: AppTileRequest?
    private var pendingAppTile: AppTileRequest?

    init(ephemeral: Bool = false) {
        self.ephemeral = ephemeral
        let (configuration, warning): (Configuration, AppNotice?) = ephemeral ? (Configuration(), nil) : store.load()
        // 必须先于任何提示渲染设定语言，否则首条提示会用错误的语言显示。
        Localization.language = configuration.settings.language
        settings = configuration.settings
        layouts = configuration.layouts
        refreshDisplays()
        if let warning { notice = warning }
        // 属性默认值在 init 体之前求值，此时语言还是 .system；这里按最终语言重新渲染一次。
        notice = notice.relocalized()
    }

    var display: DisplayInfo? { displays.first { $0.id == displayID } ?? displays.first }
    var primaryHeight: Double { Double(NSScreen.screens.first?.frame.maxY ?? CGDisplayBounds(CGMainDisplayID()).height) }
    var colorScheme: ColorScheme? { settings.theme == .system ? nil : settings.theme == .dark ? .dark : .light }
    var appCandidates: [AppCandidate] { AppCandidate.running(excluding: settings.excludedBundleIDs) }
    var canArrange: Bool { isTrusted && !isBusy && !isScanning && !isPaused && (!assignments.isEmpty || !selectedIDs.isEmpty) }

    func refreshDisplays() {
        let previous = display
        let height = primaryHeight
        displays = NSScreen.screens.map { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return DisplayInfo(id: number?.stringValue ?? screen.localizedName, name: screen.localizedName,
                               cocoaFrame: screen.frame, cocoaVisibleFrame: screen.visibleFrame,
                               visibleFrame: GridGeometry.flip(screen.visibleFrame, primaryHeight: height), scale: screen.backingScaleFactor)
        }
        if !displays.contains(where: { $0.id == displayID }) { displayID = displays.first?.id ?? "" }
        if previous?.visibleFrame != display?.visibleFrame || previous?.scale != display?.scale {
            appTileFeedback = nil
        }
    }

    func chooseDisplay(for window: LiveWindow) {
        let best = displays.max { a, b in
            let aRect = a.visibleFrame.intersection(window.frame)
            let bRect = b.visibleFrame.intersection(window.frame)
            return (aRect.isNull ? 0 : aRect.width * aRect.height) < (bRect.isNull ? 0 : bRect.width * bRect.height)
        }
        if let best { displayID = best.id }
    }

    func refresh() {
        guard !ephemeral else { return }
        isTrusted = WindowAccess.isTrusted
        guard isTrusted, !isBusy, !isScanning else { return }
        scanGeneration += 1
        let generation = scanGeneration
        let apps = appCandidates
        isScanning = true
        Task {
            let results = await access.windows(in: apps)
            guard generation == scanGeneration else { return }
            windows = results
            let live = Set(results.map(\.id))
            selectedIDs.formIntersection(live)
            assignments = assignments.filter { live.contains($0.key) }
            isScanning = false
        }
    }

    func permissionChanged() {
        let trusted = WindowAccess.isTrusted
        if trusted != isTrusted {
            isTrusted = trusted
            if trusted { notice = .init(key: "Window control is ready. Hover a green button or press %@.", settings.shortcut.label); refresh() }
            else {
                scanGeneration += 1
                pendingAppTile = nil
                appTileFeedback = nil
                isScanning = false
                onDismissPicker?(); windows = []; selectedIDs = []; assignments = [:]
            }
        }
    }

    func toggleSelection(_ window: LiveWindow) {
        if selectedIDs.contains(window.id) { selectedIDs.remove(window.id); assignments.removeValue(forKey: window.id) }
        else { selectedIDs.insert(window.id) }
    }

    func setGrid(_ grid: GridSize) { settings.grid = grid }

    func assignSelectedRegion(_ newRegion: GridRegion) {
        region = newRegion
        guard selectedIDs.count == 1, let window = windows.first(where: { selectedIDs.contains($0.id) }) else { return }
        assign(window)
    }

    func assign(_ window: LiveWindow) {
        guard region.isValid(in: settings.grid) else { return }
        guard !assignments.contains(where: { $0.key != window.id && $0.value.intersects(region) }) else {
            notice = .init(key: "That region is occupied. Clear the region first, or choose an empty one.", isError: true); return
        }
        assignments[window.id] = region
        selectedIDs.insert(window.id)
        notice = .init(key: "%@ assigned to %ld × %ld cells. Apply when ready.", window.app.name, region.columnSpan, region.rowSpan)
    }

    func clearRegion() { assignments = assignments.filter { !$0.value.intersects(region) } }

    func autoPlace() {
        do {
            let selected = windows.filter { selectedIDs.contains($0.id) }.map(\.id)
            let reserved = assignments.map { Placement(windowID: $0.key, region: $0.value) }
            let plan = try LayoutPlanner.pack(windowIDs: selected, grid: settings.grid, reserved: reserved)
            assignments = Dictionary(uniqueKeysWithValues: plan.placements.map { ($0.windowID, $0.region) })
            notice = plan.overflow.isEmpty ? .init(key: "%ld windows placed in the draft. Empty cells stay empty.", assignments.count)
                           : .init(key: "%ld selected windows do not fit and will remain unchanged.", plan.overflow.count, isError: true)
        } catch { show(error) }
    }

    func destination(for region: GridRegion) throws -> CGRect {
        guard let display else { throw GridError.invalidScreen }
        return try GridGeometry.frame(for: region, grid: settings.grid, visibleFrame: display.visibleFrame,
                                      gap: settings.gap, margin: settings.margin, scale: display.scale)
    }

    func applyDraft() {
        guard canArrange else { return }
        do {
            // A card selection is enough. Fill available cells automatically; no separate Place step.
            let plan = try LayoutPlanner.pack(windowIDs: windows.filter { selectedIDs.contains($0.id) }.map(\.id), grid: settings.grid,
                                              reserved: assignments.map { Placement(windowID: $0.key, region: $0.value) })
            guard plan.overflow.isEmpty else {
                notice = .init(key: "%ld selected windows do not fit. Choose a grid with more cells; nothing was moved.", plan.overflow.count, isError: true)
                return
            }
            let entries = plan.placements
            assignments = Dictionary(uniqueKeysWithValues: entries.map { ($0.windowID, $0.region) })
            let moves = try entries.sorted { ($0.region.row, $0.region.column) < ($1.region.row, $1.region.column) }.map { entry -> WindowMove in
                guard let window = windows.first(where: { $0.id == entry.windowID }) else { throw GridError.invalidConfiguration }
                return WindowMove(window: window, destination: try destination(for: entry.region))
            }
            run(moves)
        } catch { show(error) }
    }

    func snap(_ window: LiveWindow, to region: GridRegion) {
        if settings.tileAllAppWindows {
            tileApplication(window, columnSpan: region.columnSpan, rowSpan: region.rowSpan)
            return
        }
        guard isTrusted, !isBusy, !isScanning, !isPaused else { return }
        do {
            let others = settings.reflowSelection ? windows.filter { selectedIDs.contains($0.id) && $0.id != window.id } : []
            let plan = try LayoutPlanner.pack(windowIDs: others.map(\.id), grid: settings.grid,
                                              reserved: [.init(windowID: window.id, region: region)])
            let moves = try plan.placements.compactMap { placement -> WindowMove? in
                guard let target = ([window] + others).first(where: { $0.id == placement.windowID }) else { return nil }
                return .init(window: target, destination: try destination(for: placement.region))
            }
            onDismissPicker?()
            run(moves, suffix: plan.overflow.isEmpty ? "" : " \(plan.overflow.count) extra selected windows were left unchanged.")
        } catch { show(error) }
    }

    /// The explicit all-app mode is independent of the old manually checked reflow group.
    func tileApplication(_ window: LiveWindow, requestedGrid: GridSize? = nil, columnSpan: Int = 1, rowSpan: Int = 1) {
        guard isTrusted, !isPaused, let display,
              appCandidates.contains(where: { $0.pid == window.app.pid && $0.bundleID == window.app.bundleID }) else {
            notice = .init(key: "The target app is no longer available for tiling. Open its picker again.", isError: true)
            onResult?(notice)
            return
        }
        let grid = requestedGrid ?? settings.grid
        let surface = TilingSurface(visibleFrame: display.visibleFrame, gap: settings.gap, margin: settings.margin, scale: display.scale)
        let request = AppTileRequest(target: window, grid: grid, columnSpan: columnSpan, rowSpan: rowSpan,
                                     surface: surface, displayID: displayID, offerAlternatives: settings.autoFitAppWindows)
        if isBusy {
            guard activeAppTile != nil else {
                notice = .init(key: "Wait for the current arrangement to finish before tiling an app.", isError: true)
                onResult?(notice)
                return
            }
            // Finish or roll back the active transaction first. Only the newest queued command runs next.
            // An old completion must never resize on top of a newer transaction or overwrite its preset.
            pendingAppTile = request
            settings.grid = grid
            notice = .init(key: "Queued %@. It will run as soon as the current arrangement finishes.", grid.label)
            return
        }
        settings.grid = grid
        beginAppTile(request)
    }

    private func beginAppTile(_ request: AppTileRequest) {
        guard isTrusted, !isPaused,
              appCandidates.contains(where: { $0.pid == request.target.app.pid && $0.bundleID == request.target.app.bundleID }),
              displays.contains(where: { $0.id == request.displayID && $0.visibleFrame == request.surface.visibleFrame && $0.scale == request.surface.scale }) else {
            activeAppTile = nil
            isBusy = false
            notice = .init(key: "The target app or display changed before the queued command could run. Nothing new was moved.", isError: true)
            onResult?(notice)
            return
        }
        // A stale global scan must not replace the new batch's identities or remove a user's manual selection.
        scanGeneration += 1
        isScanning = false
        onDismissPicker?()
        appTileFeedback = nil
        activeAppTile = request
        cancelRequested = false
        isBusy = true
        onPreferencesChanged?()
        notice = .init(key: "Tiling %@ using %@…", request.target.app.name, request.grid.label)
        Task {
            let result = await ApplicationTiler.tile(target: request.target, access: access, grid: request.grid,
                                                     columnSpan: request.columnSpan, rowSpan: request.rowSpan,
                                                     surface: request.surface, autoFit: request.offerAlternatives)
            if let failures = result.report.failure?.rollbackFailures, failures > 0 {
                pendingAppTile = nil // Do not start a new arrangement on top of an incomplete rollback.
            }
            if let next = pendingAppTile {
                pendingAppTile = nil
                if result.report.succeeded { undoDepth = min(20, undoDepth + 1) }
                beginAppTile(next)
                return
            }
            activeAppTile = nil
            let current = settings.grid == request.grid && displayID == request.displayID &&
                settings.gap == request.surface.gap && settings.margin == request.surface.margin &&
                display?.visibleFrame == request.surface.visibleFrame && display?.scale == request.surface.scale
            if !result.report.succeeded && current {
                appTileFeedback = .init(request: request, message: result.report.message, suggestedGrid: result.suggestedGrid)
            }
            finish(result.report)
            if appTileFeedback != nil, isTrusted, !isPaused { onAppTilingFailure?(request.target) }
        }
    }

    func useSuggestedGrid(for window: LiveWindow) {
        guard !isBusy, let feedback = appTileFeedback, let grid = feedback.suggestedGrid,
              feedback.request.target.id == window.id,
              feedback.request.target.app.pid == window.app.pid,
              settings.grid == feedback.request.grid, displayID == feedback.request.displayID,
              settings.gap == feedback.request.surface.gap, settings.margin == feedback.request.surface.margin,
              display?.visibleFrame == feedback.request.surface.visibleFrame,
              display?.scale == feedback.request.surface.scale else { return }
        tileApplication(feedback.request.target, requestedGrid: grid)
    }

    func center(_ window: LiveWindow) {
        guard !isBusy, isTrusted, !isPaused, let display else { return }
        onDismissPicker?()
        isBusy = true
        Task {
            guard let current = await access.actualFrame(of: window) else { isBusy = false; return }
            let area = display.visibleFrame.insetBy(dx: settings.margin, dy: settings.margin)
            let destination = CGRect(x: area.midX - current.width / 2, y: area.midY - current.height / 2,
                                     width: current.width, height: current.height)
            guard area.contains(destination) else {
                isBusy = false; notice = .init(key: "The window is larger than this display. Use Fill first.", isError: true); return
            }
            let report = await access.apply([.init(window: window, destination: destination)])
            finish(report)
        }
    }

    private func run(_ moves: [WindowMove], suffix: String = "") {
        guard !isBusy else { return }
        scanGeneration += 1
        isScanning = false
        appTileFeedback = nil
        cancelRequested = false
        onDismissPicker?()
        isBusy = true
        onPreferencesChanged?()
        notice = .init(key: "Arranging %ld windows…", moves.count)
        Task { let report = await access.apply(moves); finish(report, suffix: suffix) }
    }

    func cancelArrangement() {
        guard isBusy, !cancelRequested else { return }
        pendingAppTile = nil
        cancelRequested = true
        notice = .init(key: "Stopping new moves and restoring changed windows…")
        access.cancelCurrentOperation()
        // Covers cancellation immediately after a command was queued but before its AX token exists.
        Task {
            for _ in 0..<40 {
                guard isBusy, cancelRequested else { return }
                access.cancelCurrentOperation()
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func finish(_ report: MoveReport, suffix: String = "") {
        isBusy = false
        cancelRequested = false
        onPreferencesChanged?()
        if report.succeeded { undoDepth = min(20, undoDepth + 1) }
        notice = .init(text: report.message + suffix, isError: !report.succeeded)
        onResult?(notice)
        refresh()
    }

    func undo() {
        guard !isBusy, undoDepth > 0, isTrusted else { return }
        scanGeneration += 1
        isScanning = false
        cancelRequested = false
        onDismissPicker?()
        isBusy = true
        onPreferencesChanged?()
        Task {
            let report = await access.undo()
            isBusy = false
            cancelRequested = false
            onPreferencesChanged?()
            if report.succeeded { undoDepth = max(0, undoDepth - 1) }
            notice = report.succeeded ? .init(key: "Previous window positions restored.") : .init(text: report.message, isError: true)
            onResult?(notice)
            refresh()
        }
    }

    func saveLayout(named name: String) {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !name.isEmpty, layouts.count < 100 else {
            notice = .init(key: "Give the layout a name (up to 100 saved layouts).", isError: true); return
        }
        let slots = windows.compactMap { window -> SavedSlot? in
            guard let region = assignments[window.id],
                  windows.filter({ $0.app.bundleID == window.app.bundleID && $0.title == window.title }).count == 1 else { return nil }
            return .init(region: region, window: window.identity)
        }
        let layout = SavedLayout(name: name, grid: settings.grid, slots: slots)
        do {
            try layout.validate(); layouts.append(layout)
            let skipped = assignments.count - slots.count
            notice = skipped > 0
                ? .init(key: "Saved “%@”. Missing windows stay blank. %ld ambiguous window(s) were omitted; give their documents unique titles to save them.", name, skipped)
                : .init(key: "Saved “%@”. Missing windows stay blank.", name)
        }
        catch { show(error) }
    }

    func loadLayout(_ layout: SavedLayout, applyImmediately: Bool = false) {
        guard !isBusy else { return }
        Task {
            isScanning = true
            scanGeneration += 1
            let generation = scanGeneration
            let results = await access.windows(in: appCandidates)
            guard generation == scanGeneration else { return }
            windows = results
            settings.grid = layout.grid
            assignments = [:]
            var used = Set<String>()
            for slot in layout.slots {
                if let id = SavedWindowMatcher.match(slot.window, candidates: results.map { ($0.id, $0.identity) }, excluding: used) {
                    assignments[id] = slot.region; used.insert(id)
                }
            }
            selectedIDs = used
            isScanning = false
            section = .workspace
            notice = .init(key: "Loaded “%@”: %ld/%ld windows matched. Missing slots stay blank.", layout.name, used.count, layout.slots.count)
            if applyImmediately { applyDraft() }
        }
    }

    func setLoginEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval {
                notice = .init(key: "Approve PaneGrid in System Settings → General → Login Items.", isError: true)
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch { loginEnabled = SMAppService.mainApp.status == .enabled; show(error) }
    }

    func exportConfiguration() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "PaneGrid-layouts.json"
        panel.message = Localization.t("Saved layouts contain application identifiers and window titles. Review before sharing.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try configuration.encoded().write(to: url, options: .atomic); notice = .init(key: "Settings and layouts exported.") }
        catch { show(error) }
    }

    func importConfiguration() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = Localization.t("Import layouts without replacing existing settings or layouts. Up to 100 layouts total.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try Configuration.decode(store.readBounded(url))
            let existing = Set(layouts.map(\.id))
            let additions = imported.layouts.filter { !existing.contains($0.id) }
            guard layouts.count + additions.count <= 100 else { throw GridError.invalidConfiguration }
            layouts.append(contentsOf: additions)
            notice = .init(key: "Imported %ld new layouts. Your current settings were kept.", additions.count)
        } catch { show(error) }
    }

    func openPracticeWindows() {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("PaneGrid Practice.app"),
              FileManager.default.fileExists(atPath: url.path) else {
            notice = .init(key: "Build the app bundle to include the practice windows.", isError: true); return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { [weak self] _, error in
            Task { @MainActor in
                if let error { self?.show(error) }
                else {
                    try? await Task.sleep(for: .milliseconds(500))
                    self?.refresh()
                }
            }
        }
    }

    private var configuration: Configuration {
        var value = Configuration(); value.settings = settings; value.layouts = layouts; return value
    }

    private func scheduleSave() {
        guard !ephemeral else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func flush() {
        guard !ephemeral else { return }
        saveWork?.cancel()
        do { try store.save(configuration) }
        catch { notice = .init(key: "Settings could not be saved: %@", error.localizedDescription, isError: true) }
    }

    func show(_ error: Error) {
        notice = .init(text: error.localizedDescription, isError: true)
        onResult?(notice)
    }
}
