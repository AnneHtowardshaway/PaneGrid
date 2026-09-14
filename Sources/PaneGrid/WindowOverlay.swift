import AppKit
import SwiftUI
import PaneGridCore

final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class WindowOverlay {
    private let state: AppState
    private let panel = PickerPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let previewPanel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let toastPanel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var timer: Timer?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var lastPoint: CGPoint?
    private var pending: (target: ZoomTarget, since: TimeInterval)?
    private var zoomTarget: (target: ZoomTarget, verifiedAt: TimeInterval)?
    private var lastQueryAt: TimeInterval = 0
    private var queryInProgress = false
    private var queryGeneration = 0
    private var focusGeneration = 0
    private var anchor: CGRect?
    private var suppressedAnchor: CGRect?
    private var awaySince: TimeInterval?
    private var toastWork: DispatchWorkItem?
    private var showsFromHover = false
    private var persistentRecovery = false
    private var pressMonitor: GreenButtonPressMonitor?
    private(set) var currentTarget: LiveWindow?
    var isVisible: Bool { panel.isVisible }

    init(state: AppState) {
        self.state = state
        for window in [panel, previewPanel, toastPanel] {
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            window.isReleasedWhenClosed = false
        }
        panel.title = "PaneGrid Picker"
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.isFloatingPanel = true
        previewPanel.title = "PaneGrid Preview"
        previewPanel.level = .floating
        previewPanel.ignoresMouseEvents = true
        previewPanel.hasShadow = false
        toastPanel.level = .statusBar
        toastPanel.ignoresMouseEvents = true
        toastPanel.hasShadow = true
        let previewContent = NSHostingView(rootView:
            RoundedRectangle(cornerRadius: 10).fill(PaneStyle.accent.opacity(0.13))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(PaneStyle.accent.opacity(0.9), lineWidth: 3)).padding(2))
        previewContent.sizingOptions = []
        previewPanel.contentView = previewContent
        pressMonitor = GreenButtonPressMonitor(
            canCapture: { [weak self] in
                guard let self else { return false }
                // Only cached state here: this closure is also called by the event tap.
                return self.state.isTrusted && !self.state.isPaused && !self.state.isBusy
            },
            onCapture: { [weak self] in
                guard let self else { return }
                self.pending = nil
                self.queryGeneration += 1
                self.focusGeneration += 1
            },
            validate: { [weak self] target, point in
                await self?.validatePress(target, at: point)
            },
            open: { [weak self] target in
                guard let self else { return false }
                self.show(window: target.window, anchorAX: target.buttonFrame, fromHover: false)
                return self.panel.isVisible && self.currentTarget?.id == target.window.id
            },
            onRelease: { [weak self] target in
                guard let self else { return }
                self.pending = nil
                self.zoomTarget = nil
                self.lastPoint = nil
                self.queryGeneration += 1
                self.suppressedAnchor = GridGeometry.flip(target.buttonFrame, primaryHeight: self.state.primaryHeight).insetBy(dx: -8, dy: -8)
            },
            onUnavailable: { [weak self] in
                guard let self else { return }
                let notice = AppNotice(text: "Green-button press-and-hold is unavailable because the mouse event tap could not be enabled. Hover (when enabled) and the picker shortcut still work.", isError: true)
                self.state.notice = notice
                self.showMessage(notice)
            })
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard !GreenButtonPressMonitor.isReplay(event.cgEvent) else { return event }
            guard let self, self.panel.isVisible else { return event }
            if event.type == .keyDown && event.keyCode == 53 { self.dismiss(); return nil }
            if event.type != .keyDown && event.window != self.panel { self.dismiss() }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            // NSEvent monitor handlers run on the main thread. Do not enqueue a dismissal that
            // could arrive after a captured hold has opened its picker.
            MainActor.assumeIsolated {
                guard let self, !GreenButtonPressMonitor.isReplay(event.cgEvent) else { return }
                if self.pressMonitor?.preservesTarget(for: event.cgEvent) == true { return }
                self.dismiss()
            }
        }
        let scanTimer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer = scanTimer
        RunLoop.main.add(scanTimer, forMode: .common)
    }

    deinit {
        timer?.invalidate()
        toastWork?.cancel()
        let local = localMonitor, global = globalMonitor
        DispatchQueue.main.async {
            if let local { NSEvent.removeMonitor(local) }
            if let global { NSEvent.removeMonitor(global) }
        }
    }

    func preferencesChanged() {
        queryGeneration += 1
        focusGeneration += 1
        pending = nil
        lastPoint = nil
        zoomTarget = nil
        pressMonitor?.cancelPending()
        pressMonitor?.setEnabled(state.isTrusted && !state.isPaused && !state.isBusy)
        if state.isPaused || (!state.settings.hoverEnabled && showsFromHover) { dismiss() }
        if !state.settings.showPreview { previewPanel.orderOut(nil) }
        if let currentTarget, state.settings.excludedBundleIDs.contains(currentTarget.app.bundleID) { dismiss() }
    }

    func showFocused() {
        guard state.isTrusted, !state.isBusy, !state.isPaused else {
            state.notice = .init(text: "Enable Accessibility and resume PaneGrid before opening the picker.", isError: true)
            state.onShowWorkspace?(); return
        }
        pressMonitor?.cancelPending()
        zoomTarget = nil
        pending = nil
        queryGeneration += 1
        if panel.isVisible { dismiss(); return }
        let front = NSWorkspace.shared.frontmostApplication
        let candidate = state.appCandidates.first { $0.pid == front?.processIdentifier } ?? state.lastExternalApp
        guard let candidate, !state.settings.excludedBundleIDs.contains(candidate.bundleID) else {
            showMessage(.init(text: "Focus a resizable application window first.", isError: true)); return
        }
        focusGeneration += 1
        let generation = focusGeneration
        Task {
            let result = await state.access.focusedWindow(in: candidate)
            guard generation == focusGeneration else { return }
            guard let window = result, !state.isPaused else {
                showMessage(.init(text: "This window cannot be resized. Try a normal, non-fullscreen window.", isError: true)); return
            }
            let anchor = CGRect(x: window.frame.midX - 8, y: window.frame.minY + 28, width: 16, height: 16)
            show(window: window, anchorAX: anchor, fromHover: false)
        }
    }

    func show(window: LiveWindow, anchorAX: CGRect, fromHover: Bool, preserveDisplay: Bool = false) {
        guard state.isTrusted, !state.isPaused, !state.isBusy else { return }
        if !preserveDisplay { state.chooseDisplay(for: window) }
        guard let display = state.display else { return }
        pressMonitor?.cancelPending()
        zoomTarget = nil
        queryGeneration += 1
        focusGeneration += 1
        pending = nil
        currentTarget = window
        showsFromHover = fromHover
        persistentRecovery = state.appTileFeedback?.request.target.app.pid == window.app.pid
        anchor = GridGeometry.flip(anchorAX, primaryHeight: state.primaryHeight)
        let content = NSHostingView(rootView: QuickPickerView(state: state, window: window,
                                                             preview: { [weak self] in self?.showPreview($0) },
                                                             close: { [weak self] in self?.dismiss() }))
        let size = content.fittingSize
        content.sizingOptions = []
        panel.contentView = content
        let point = anchor?.origin ?? display.cocoaVisibleFrame.origin
        let desired = CGRect(x: point.x - 28, y: point.y - size.height - 10, width: size.width, height: size.height)
        panel.setFrame(GridGeometry.clampPanel(desired, to: display.cocoaVisibleFrame), display: true)
        panel.makeKeyAndOrderFront(nil)
        awaySince = nil
    }

    func showRecovery(for window: LiveWindow) {
        let anchor = CGRect(x: window.frame.minX + 56, y: window.frame.minY + 8, width: 16, height: 16)
        show(window: window, anchorAX: anchor, fromHover: false, preserveDisplay: true)
    }

    func dismiss() {
        pressMonitor?.cancelPending()
        zoomTarget = nil
        lastPoint = nil
        if panel.isVisible { suppressedAnchor = anchor?.insetBy(dx: -8, dy: -8) }
        panel.orderOut(nil)
        previewPanel.orderOut(nil)
        currentTarget = nil
        persistentRecovery = false
        pending = nil
        anchor = nil
        awaySince = nil
        queryGeneration += 1
        focusGeneration += 1
    }

    func showPreview(_ region: GridRegion?) {
        guard state.settings.showPreview, panel.isVisible, let region,
              let rect = try? state.destination(for: region) else { previewPanel.orderOut(nil); return }
        previewPanel.setFrame(GridGeometry.flip(rect, primaryHeight: state.primaryHeight), display: true)
        previewPanel.orderFrontRegardless()
        panel.orderFrontRegardless()
    }

    func showMessage(_ notice: AppNotice) {
        guard let screen = state.display?.cocoaVisibleFrame else { return }
        toastWork?.cancel()
        let content = NSHostingView(rootView:
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: notice.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(notice.isError ? .orange : PaneStyle.accent)
                Text(notice.text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            }.padding(16).frame(width: 370).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .preferredColorScheme(state.colorScheme))
        toastPanel.contentView = content
        let size = content.fittingSize
        toastPanel.setFrame(CGRect(x: screen.maxX - size.width - 20, y: screen.minY + 22, width: size.width, height: size.height), display: true)
        toastPanel.orderFrontRegardless()
        let work = DispatchWorkItem { [weak self] in self?.toastPanel.orderOut(nil) }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (notice.isError ? 7 : 3), execute: work)
    }

    private func validatePress(_ target: ZoomTarget, at point: CGPoint) async -> ZoomTarget? {
        let generation = focusGeneration
        guard state.isTrusted, !state.isBusy, !state.isPaused, !panel.isVisible,
              !state.settings.excludedBundleIDs.contains(target.window.app.bundleID) else { return nil }
        // Re-hit-test the current topmost external app on WindowAccess's existing serial AX queue.
        let result = await state.access.zoomTarget(at: point, apps: [target.window.app])
        guard generation == focusGeneration, state.isTrusted, !state.isBusy, !state.isPaused,
              !panel.isVisible, !state.settings.excludedBundleIDs.contains(target.window.app.bundleID),
              let result, result.window.app.pid == target.window.app.pid,
              CFEqual(result.window.element, target.window.element),
              result.window.frame == target.window.frame, result.buttonFrame == target.buttonFrame,
              result.buttonFrame.contains(point) else { return nil }
        return result
    }

    private func tick() {
        let enabled = state.isTrusted && !state.isBusy && !state.isPaused
        pressMonitor?.setEnabled(enabled)
        guard enabled else {
            if queryInProgress || zoomTarget != nil || pending != nil { queryGeneration += 1 }
            zoomTarget = nil
            pending = nil
            lastPoint = nil
            return
        }
        let point = NSEvent.mouseLocation
        let now = ProcessInfo.processInfo.systemUptime
        // Neither hover nor a second AX scan may compete with an owned physical button sequence.
        if pressMonitor?.isCapturing == true { pending = nil; return }
        if panel.isVisible {
            // A failure explanation must not disappear just because the pointer stayed near
            // the old window position during a multi-window arrangement. Esc/outside click still close it.
            if persistentRecovery { return }
            // The union forms a forgiving travel corridor between the button and its picker.
            let corridor = panel.frame.insetBy(dx: -12, dy: -12).union(anchor?.insetBy(dx: -10, dy: -10) ?? panel.frame)
            if corridor.contains(point) { awaySince = nil }
            else if let awaySince, now - awaySince > 0.7 { dismiss() }
            else if awaySince == nil { awaySince = now }
            return
        }
        if NSEvent.pressedMouseButtons != 0 ||
            (NSApp.isActive && NSApp.windows.contains(where: { $0.isVisible && $0.frame.contains(point) })) {
            pending = nil
            zoomTarget = nil
            pressMonitor?.updateTarget(nil)
            lastPoint = nil
            queryGeneration += 1
            return
        }
        if let suppressedAnchor, !suppressedAnchor.contains(point) { self.suppressedAnchor = nil }
        let hoverAllowed = state.settings.hoverEnabled &&
            (!state.settings.requireOption || NSEvent.modifierFlags.contains(.option)) && suppressedAnchor == nil
        if !hoverAllowed { pending = nil }
        if lastPoint != point {
            pending = nil
            zoomTarget = nil
            pressMonitor?.updateTarget(nil)
        }
        // The stricter cache age is only for delaying native clicks, not for existing hover.
        if hoverAllowed, let pending,
           now - pending.since >= state.settings.hoverDelay {
            show(window: pending.target.window, anchorAX: pending.target.buttonFrame, fromHover: true)
            return
        }
        // Keep a fresh cache even with hover disabled or Option absent. Deliberate holds need no modifier.
        guard !queryInProgress, lastPoint != point || now - lastQueryAt >= 0.15 else { return }
        lastPoint = point
        lastQueryAt = now
        queryGeneration += 1
        let generation = queryGeneration
        let apps = state.appCandidates
        let axPoint = CGPoint(x: point.x, y: state.primaryHeight - point.y)
        queryInProgress = true
        Task {
            let result = await state.access.zoomTarget(at: axPoint, apps: apps)
            queryInProgress = false
            guard generation == queryGeneration, !panel.isVisible, pressMonitor?.isCapturing != true,
                  state.isTrusted, !state.isPaused, !state.isBusy,
                  hypot(NSEvent.mouseLocation.x - point.x, NSEvent.mouseLocation.y - point.y) < 3 else { return }
            guard let result else {
                pending = nil
                zoomTarget = nil
                pressMonitor?.updateTarget(nil)
                return
            }
            zoomTarget = (result, now)
            pressMonitor?.updateTarget(result, verifiedAt: now)
            let canHover = state.settings.hoverEnabled &&
                (!state.settings.requireOption || NSEvent.modifierFlags.contains(.option)) && suppressedAnchor == nil
            if canHover {
                if pending?.target.buttonFrame != result.buttonFrame ||
                    pending.map({ !CFEqual($0.target.window.element, result.window.element) }) != false {
                    pending = (result, ProcessInfo.processInfo.systemUptime)
                }
            } else { pending = nil }
        }
    }
}
