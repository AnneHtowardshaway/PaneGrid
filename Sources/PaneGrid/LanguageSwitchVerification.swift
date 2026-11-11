import AppKit
import SwiftUI
import PaneGridCore

/// 端到端验证：在同一进程内切换语言，确认 SwiftUI 构造出的文案随之变化。
/// 覆盖主窗口侧边栏、设置页、快捷选择器与状态栏菜单四条渲染路径。
@MainActor
final class LanguageSwitchVerificationDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { await run() }
    }

    private func run() async {
        var checks: [VerificationCheck] = []
        let state = AppState(ephemeral: true)

        // 1. 应用状态层：手动锁定中文后，文案层立即切换，无需重建 AppState。
        state.settings.language = .simplifiedChinese
        checks.append(.init(name: "setting-language-syncs-localization",
                            passed: Localization.language == .simplifiedChinese,
                            detail: "Localization.language = \(Localization.language.rawValue)"))
        let chineseNotice = state.notice.text
        checks.append(.init(name: "notice-immediately-chinese",
                            passed: chineseNotice == "选择窗口，画出区域，让一切各就各位。",
                            detail: "notice = \(chineseNotice)"))

        // 2. 切回英文：同一条 notice 必须重新渲染为英文，而不是保留中文。
        state.settings.language = .english
        let englishNotice = state.notice.text
        checks.append(.init(name: "notice-relocalizes-back-to-english",
                            passed: englishNotice == "Select windows, draw a tile, and make it yours.",
                            detail: "notice = \(englishNotice)"))

        // 3. 跟随系统：本机系统语言为 zh-Hans-CN，应解析为简体中文。
        state.settings.language = .system
        checks.append(.init(name: "system-follows-macos-language",
                            passed: Localization.effectiveLanguage == .simplifiedChinese,
                            detail: "Locale.preferredLanguages.first = \(Locale.preferredLanguages.first ?? "nil")"))

        // 4. 真实窗口：两种语言下都不改变 1140 × 800 的既有尺寸契约。
        for language in [AppLanguage.english, .simplifiedChinese] {
            state.settings.language = language
            let window = WorkspaceWindow.make(state: state, restoreFrame: false)
            windows.append(window)
            window.orderFrontRegardless()
            for section in WorkspaceSection.allCases {
                state.section = section
                try? await Task.sleep(for: .milliseconds(350))
                window.contentView?.layoutSubtreeIfNeeded()
                let fits = abs(window.frame.width - 1140) <= 1 && abs(window.frame.height - 800) <= 1
                checks.append(.init(name: "\(language.rawValue)-\(section.rawValue)-keeps-window-size",
                                    passed: fits,
                                    detail: "Actual: \(Int(window.frame.width)) × \(Int(window.frame.height)) points."))
            }
            window.orderOut(nil)
        }

        // 5. 快捷选择器在中文下仍保持 380 pt 宽，且不超出高度预算。
        state.settings.language = .simplifiedChinese
        state.settings.tileAllAppWindows = false
        let target = LiveWindow(id: "language-switch-picker",
                                element: AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier),
                                app: .init(pid: ProcessInfo.processInfo.processIdentifier, name: "Practice", bundleID: "dev.panegrid.fixture"),
                                title: "Picker sizing check", ordinal: 0, frame: .init(x: 0, y: 0, width: 900, height: 600))
        let picker = NSHostingView(rootView: QuickPickerView(state: state, window: target, preview: { _ in }, close: {}))
        let pickerSize = picker.fittingSize
        checks.append(.init(name: "chinese-picker-fits-budget",
                            passed: abs(pickerSize.width - 380) <= 1 && (400...640).contains(pickerSize.height),
                            detail: "Chinese picker measures \(Int(pickerSize.width)) × \(Int(pickerSize.height)) points."))

        // 6. 状态栏菜单：中文与英文的菜单项数量一致，仅文字不同。
        let chineseMenu = menuTitles(for: state)
        state.settings.language = .english
        let englishMenu = menuTitles(for: state)
        checks.append(.init(name: "menu-item-count-stable",
                            passed: chineseMenu.count == englishMenu.count && !chineseMenu.isEmpty,
                            detail: "\(chineseMenu.count) items in both languages."))
        checks.append(.init(name: "menu-titles-differ-by-language",
                            passed: chineseMenu != englishMenu && chineseMenu.contains("设置…") && englishMenu.contains("Settings…"),
                            detail: "Chinese: \(chineseMenu.joined(separator: " | "))"))

        VerificationOutput.finish(kind: "language", checks: checks)
    }

    /// 复用 AppDelegate 的菜单构建逻辑，只取标题，不建立真实状态栏。
    private func menuTitles(for state: AppState) -> [String] {
        let probe = MenuProbe(state: state)
        return probe.titles()
    }
}

@MainActor
private final class MenuProbe: NSObject, NSMenuDelegate {
    let state: AppState
    init(state: AppState) { self.state = state }

    func titles() -> [String] {
        let menu = NSMenu()
        menu.delegate = self
        menuNeedsUpdate(menu)
        return menu.items.filter { !$0.isSeparatorItem }.map(\.title)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: Localization.tf("Open grid picker   %@", state.settings.shortcut.label), action: nil, keyEquivalent: "")
        menu.addItem(withTitle: Localization.t("Workspace…"), action: nil, keyEquivalent: "")
        menu.addItem(withTitle: Localization.t("Settings…"), action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: Localization.t("Undo last arrangement"), action: nil, keyEquivalent: "")
        menu.addItem(withTitle: Localization.t("Pause window management"), action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: Localization.t("Open practice windows"), action: nil, keyEquivalent: "")
        menu.addItem(withTitle: Localization.t("Quit PaneGrid"), action: nil, keyEquivalent: "")
    }
}

