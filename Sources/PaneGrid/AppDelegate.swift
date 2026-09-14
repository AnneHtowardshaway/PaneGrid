import AppKit
import SwiftUI
import PaneGridCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let state = AppState()
    private var workspace: NSWindow?
    private var statusItem: NSStatusItem?
    private var overlay: WindowOverlay?
    private let hotKey = HotKeyManager()
    private var permissionTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastShortcut: PickerShortcut?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        rememberFrontmost()
        overlay = WindowOverlay(state: state)
        state.onPreferencesChanged = { [weak self] in self?.preferencesChanged() }
        state.onShowWorkspace = { [weak self] in self?.showWorkspace() }
        state.onShowPicker = { [weak self] in self?.overlay?.showFocused() }
        state.onDismissPicker = { [weak self] in self?.overlay?.dismiss() }
        state.onAppTilingFailure = { [weak self] in self?.overlay?.showRecovery(for: $0) }
        state.onResult = { [weak self] notice in
            guard let self, notice.isError || self.workspace?.isVisible != true else { return }
            self.overlay?.showMessage(notice)
        }
        hotKey.onTrigger = { [weak self] in self?.overlay?.showFocused() }
        preferencesChanged()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "rectangle.split.3x3", accessibilityDescription: "PaneGrid")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = "PaneGrid — window workspace"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let previous = self.state.isTrusted
                self.state.permissionChanged()
                if previous != self.state.isTrusted { self.writeUIReportIfRequested() }
            }
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.rememberFrontmost() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.overlay?.dismiss(); self?.state.refreshDisplays() }
        })
        if CommandLine.arguments.contains("--practice") { state.windowSearch = "PaneGrid" }
        showWorkspace()
    }

    private func rememberFrontmost() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier, app.activationPolicy == .regular else { return }
        state.lastExternalApp = AppCandidate(pid: app.processIdentifier, name: app.localizedName ?? "Application", bundleID: app.bundleIdentifier ?? "process.\(app.processIdentifier)")
    }

    private func preferencesChanged() {
        overlay?.preferencesChanged()
        if lastShortcut != state.settings.shortcut {
            lastShortcut = state.settings.shortcut
            if let error = hotKey.configure(state.settings.shortcut) { state.notice = .init(text: error, isError: true) }
        }
    }

    @objc func showWorkspace() {
        overlay?.dismiss()
        if workspace == nil {
            let window = WorkspaceWindow.make(state: state)
            window.delegate = self
            workspace = window
        }
        NSApp.setActivationPolicy(.regular)
        workspace?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        state.refreshDisplays()
        state.refresh()
        writeUIReportIfRequested()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        state.flush()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWorkspace(); return true }

    func windowDidResize(_ notification: Notification) { writeUIReportIfRequested() }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !state.isBusy else {
            state.notice = .init(text: "Wait for the current arrangement or rollback to finish before quitting.", isError: true)
            showWorkspace()
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) { state.flush() }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        add("Open grid picker   \(state.settings.shortcut.label)", action: #selector(pickerAction), to: menu, enabled: state.isTrusted && !state.isPaused)
        add("Workspace…", action: #selector(showWorkspace), to: menu)
        add("Settings…", action: #selector(settingsAction), to: menu)
        menu.addItem(.separator())
        add("Undo last arrangement", action: #selector(undoAction), to: menu, enabled: state.undoDepth > 0 && !state.isBusy)
        let pause = add("Pause window management", action: #selector(pauseAction), to: menu)
        pause.state = state.isPaused ? .on : .off
        if !state.layouts.isEmpty {
            menu.addItem(.separator())
            let layouts = NSMenuItem(title: "Saved layouts", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for layout in state.layouts {
                let item = add(layout.name, action: #selector(loadAction(_:)), to: submenu, enabled: !state.isBusy && !state.isScanning)
                item.representedObject = layout.id.uuidString
            }
            layouts.submenu = submenu
            menu.addItem(layouts)
        }
        menu.addItem(.separator())
        add("Open practice windows", action: #selector(practiceAction), to: menu)
        add("Quit PaneGrid", action: #selector(quitAction), to: menu)
    }

    @discardableResult private func add(_ title: String, action: Selector, to menu: NSMenu, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        menu.autoenablesItems = false
        menu.addItem(item)
        return item
    }

    @objc private func pickerAction() { overlay?.showFocused() }
    @objc private func settingsAction() { state.section = .settings; showWorkspace() }
    @objc private func undoAction() { state.undo() }
    @objc private func pauseAction() { state.isPaused.toggle() }
    @objc private func quitAction() { NSApp.terminate(nil) }
    @objc private func practiceAction() { state.openPracticeWindows() }
    @objc private func loadAction(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let layout = state.layouts.first(where: { $0.id.uuidString == id }) else { return }
        state.loadLayout(layout)
        showWorkspace()
    }

    private func installMainMenu() {
        let menu = NSMenu()
        let app = NSMenuItem()
        let appMenu = NSMenu()
        add("PaneGrid Workspace", action: #selector(showWorkspace), to: appMenu)
        let settings = add("Settings…", action: #selector(settingsAction), to: appMenu)
        settings.keyEquivalent = ","
        appMenu.addItem(.separator())
        let quit = add("Quit PaneGrid", action: #selector(quitAction), to: appMenu)
        quit.keyEquivalent = "q"
        app.submenu = appMenu
        menu.addItem(app)
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        edit.submenu = editMenu
        menu.addItem(edit)
        NSApp.mainMenu = menu
    }

    private func writeUIReportIfRequested() {
        guard let index = CommandLine.arguments.firstIndex(of: "--ui-report"), CommandLine.arguments.count > index + 1,
              let workspace else { return }
        let info: [String: Any] = ["application": "PaneGrid", "windowID": workspace.windowNumber,
                                   "accessibilityTrusted": WindowAccess.isTrusted,
                                   "width": workspace.frame.width, "height": workspace.frame.height,
                                   "screenCount": NSScreen.screens.count]
        do {
            try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]), options: .atomic)
        } catch { NSLog("PaneGrid UI report could not be written: %@", error.localizedDescription) }
    }
}
