import Foundation

/// 界面语言。`.system` 跟随 macOS 首选语言，其余为手动锁定。
public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case system
    case english
    case simplifiedChinese

    /// 未来版本写入的未知值一律回退为跟随系统，避免整份配置解码失败而丢失用户的布局。
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AppLanguage(rawValue: raw) ?? .system
    }

    /// 选择器里显示的条目名称。语言名用各自的语言书写，避免用户看不懂当前选项。
    public var label: String {
        switch self {
        case .system: return Localization.t("Follow System")
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }
}

/// 进程内文案层：英文原文即键，简体中文为译文。
///
/// 不使用 `.lproj` 资源包，是因为手动锁定语言需要在不重启进程的情况下立即生效，
/// 而 Bundle 级本地化只能按系统语言在启动时解析一次。
public enum Localization {
    private static let lock = NSLock()
    private static var stored: AppLanguage = .system

    /// 系统首选语言在进程生命周期内不会变化（改变系统语言需要重启应用），因此只解析一次。
    private static let systemPrefersChinese: Bool = {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true
    }()

    /// 用户设置的语言；写入只在主线程发生，读取可能来自窗口操作的串行队列。
    public static var language: AppLanguage {
        get {
            lock.lock(); defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock(); stored = newValue; lock.unlock()
        }
    }

    public static var effectiveLanguage: AppLanguage {
        lock.lock(); defer { lock.unlock() }
        switch stored {
        case .system: return systemPrefersChinese ? .simplifiedChinese : .english
        case .english, .simplifiedChinese: return stored
        }
    }

    public static var isChinese: Bool { effectiveLanguage == .simplifiedChinese }

    /// 纯文本翻译。英文模式下原样返回键本身。
    public static func t(_ key: String) -> String {
        guard isChinese else { return key }
        guard let value = chinese[key] else {
            // Debug 构建立刻暴露漏翻的文案；Release 构建退回英文，绝不显示空字符串。
            assertionFailure("Missing Simplified Chinese translation for: \(key)")
            return key
        }
        return value
    }

    /// 带占位符的翻译。调用方必须使用 `%ld`（整数）与 `%@`（字符串）这类明确的格式说明符。
    public static func tf(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), arguments: arguments)
    }

    /// 简体中文对照表。键必须与源码中的英文字面量逐字一致，由 `scripts/verify-localization.py` 校验。
    private static let chinese: [String: String] = [
        // MARK: 通用
        "Follow System": "跟随系统",
        "Application": "应用程序",
        "Untitled window": "未命名窗口",
        "Cancel": "取消",
        "Undo": "撤销",
        "Cut": "剪切",
        "Copy": "拷贝",
        "Paste": "粘贴",
        "Select All": "全选",
        "Edit": "编辑",
        "Workspace…": "工作区…",
        "Settings…": "设置…",
        "Workspace": "工作区",
        "Saved layouts": "已保存的布局",
        "Settings": "设置",

        // MARK: 外观
        "System": "跟随系统",
        "Dark": "深色",
        "Light": "浅色",
        "Appearance": "外观",
        "This Mac": "此 Mac",

        // MARK: 菜单栏
        "PaneGrid — window workspace": "PaneGrid — 窗口工作区",
        "Open grid picker   %@": "打开网格选择器   %@",
        "Undo last arrangement": "撤销上次排布",
        "Pause window management": "暂停窗口管理",
        "Open practice windows": "打开练习窗口",
        "Quit PaneGrid": "退出 PaneGrid",
        "PaneGrid Workspace": "PaneGrid 工作区",
        "Wait for the current arrangement or rollback to finish before quitting.": "请等待当前排布或回滚完成后再退出。",

        // MARK: 工作区外壳
        "A little more room.": "再多一点空间。",
        "QUICK PICKER": "快速选择器",
        "Or hover / hold a window’s green button.": "或悬停 / 按住窗口的绿色按钮。",
        "Paused": "已暂停",
        "Ready on this Mac": "此 Mac 上已就绪",
        "Permission needed": "需要授权",
        "LOCAL · FREE · OPEN SOURCE": "本地 · 免费 · 开源",
        "YOUR WINDOW WORKSPACE": "你的窗口工作区",
        "ROOM FOR YOUR ROUTINES": "为你的日常留出空间",
        "MAKE IT YOURS": "按你的方式设置",
        "Everything in its place.": "一切各就各位。",
        "Keep a good arrangement.": "保留一套好用的排布。",
        "Small details. Your way.": "细节之处，由你决定。",
        "Open picker": "打开选择器",
        "One permission, then you’re ready.": "一次授权，即可开始。",
        "Allow Accessibility access so PaneGrid can move and resize your windows. No screen recording is needed.": "允许辅助功能访问，PaneGrid 才能移动和调整窗口大小。无需屏幕录制权限。",
        "Enable window control": "启用窗口控制",
        "Restoring…": "正在还原…",

        // MARK: 工作区
        "Display": "显示器",
        "Draw first. Arrange when ready.": "先画区域，准备好再排布。",
        "Your grid": "你的网格",
        "COLUMNS × ROWS": "列 × 行",
        "Clear region": "清除区域",
        "Reset": "重置",
        "Click window cards to select them, then Apply to tile them together. With one window selected, drag on the grid to set its exact region.": "点击窗口卡片选择窗口，再点「应用排布」一起平铺。只选中一个窗口时，可在网格上拖拽指定它的精确区域。",
        "Name this layout…": "为此布局命名…",
        "Save layout": "保存布局",
        "Apply arrangement": "应用排布",
        "Windows": "窗口",
        "Refresh open windows": "刷新打开的窗口",
        "Refresh windows": "刷新窗口",
        "Filter apps or titles…": "筛选应用或标题…",
        "Filter windows": "筛选窗口",
        "Select listed": "选择列表中的窗口",
        "None": "全不选",
        "No matching windows": "没有匹配的窗口",
        "Windows appear after you enable access.": "启用访问权限后才会显示窗口。",
        "Auto-place selected": "自动放置已选窗口",
        "Click anywhere on a card to select or deselect it. Only selected windows are arranged.": "点击卡片任意位置即可选择或取消选择。只会排布已选窗口。",
        "Selected": "已选择",
        "Not selected": "未选择",
        "Columns": "列",
        "Rows": "行",
        "%ld cells": "%ld 个单元格",
        "%ld × %ld selected": "已选 %ld × %ld",
        "%ld assigned": "已分配 %ld 个",
        "%ld × %ld · C%ld R%ld": "%ld × %ld · 第%ld列 第%ld行",
        "Select %@, %@": "选择 %@，%@",
        "%ld columns, %ld rows": "%ld 列，%ld 行",
        "Window layout grid": "窗口布局网格",
        "Column %ld, row %ld, spans %ld columns and %ld rows": "第 %ld 列，第 %ld 行，横跨 %ld 列 %ld 行",
        "Arrow keys move the selection. Shift and arrows change its size. Return applies it.": "方向键移动选择区域。Shift + 方向键调整大小。回车应用。",
        "Column %ld, row %ld": "第 %ld 列，第 %ld 行",

        // MARK: 快捷选择器
        "Close picker": "关闭选择器",
        "Tile all windows of this app": "平铺此应用的所有窗口",
        "Applies to %@ only. Choose a preset to tile immediately; other apps stay unchanged.": "仅作用于 %@。选择预设即可立即平铺，其他应用不受影响。",
        "%@ was not applied": "%@ 未应用",
        "Try %@ instead": "改用 %@",
        "Preset: tile all · Drag: same size for all": "预设：平铺全部 · 拖拽：统一尺寸",
        "Drag to span · Release to resize": "拖拽跨格 · 松开即调整大小",
        "Tile app windows": "平铺应用窗口",
        "Fill": "铺满",
        "Center": "居中",
        "Suggest a fitting grid if needed": "需要时建议合适的网格",
        "%@ only. Presets never change automatically.": "仅作用于 %@。预设不会自动改变。",
        "Reflow my selected group (%ld)": "重排已选组合（%ld）",
        "Blank cells stay empty. Esc closes. Shift + arrows changes the span.": "空白单元格保持空白。Esc 关闭。Shift + 方向键调整跨格。",

        // MARK: 设置
        "The green-button picker": "绿色按钮选择器",
        "Show the picker when hovering a window’s green button": "悬停窗口绿色按钮时显示选择器",
        "Require the Option (⌥) key while hovering": "悬停时需要按住 Option (⌥) 键",
        "Hold a window’s green button for 0.45 seconds to open the picker, even with hover off; Option is not required. A short click keeps macOS’s normal fullscreen behavior. Press-and-hold needs a recently detected button and an available mouse event tap. Option-hover can help if the native tiling menu appears at the same time.": "即使关闭悬停，按住窗口绿色按钮 0.45 秒也能打开选择器，且无需按 Option。短按仍保留 macOS 的全屏行为。按住操作需要最近检测到该按钮，且鼠标事件监听可用（鼠标事件监听不可用时，可改用 Option + 悬停）。",
        "Hover delay": "悬停延迟",
        "Global shortcut": "全局快捷键",
        "Preview the destination before applying": "应用前预览目标位置",
        "Tile all windows of the app whose picker I open": "平铺我打开选择器之应用的全部窗口",
        "Suggest alternate grids when an app needs larger tiles": "应用需要更大区域时建议替代网格",
        "Your chosen preset always stays selected. An alternative is applied only when you explicitly choose it; slow responses are not treated as minimum sizes.": "你选择的预设始终保持选中。只有明确点击时才会应用替代方案；响应缓慢不会被当作最小尺寸。",
        "With app-wide tiling on, selecting a preset immediately fills equal-sized portions with that app’s windows. A drawn span sets the size for all of them. Other apps remain untouched; no checkboxes or one-by-one placement are needed.": "开启应用级平铺后，选择预设会立即用该应用的窗口填满等分区域。手动绘制的跨格会作为所有这些窗口的尺寸。其他应用不受影响，无需勾选或逐个放置。",
        "Reflow my selected group when I snap a window": "吸附窗口时重排已选组合",
        "Reflow packs only the windows checked in Workspace around your snapped tile. Unselected windows never join automatically.": "重排只会把工作区中已勾选的窗口围绕你吸附的区域重新打包。未选中的窗口不会被自动加入。",
        "Grid & spacing": "网格与间距",
        "Between tiles": "区域之间",
        "Display margin": "显示器边距",
        "Display edges follow the usable desktop, keeping the Dock and menu bar clear. Large grids work best with multi-cell spans when apps need more room.": "显示边界跟随可用桌面区域，自动避开 Dock 与菜单栏。网格较大时，应用需要更多空间可使用跨格。",
        "Launch PaneGrid at login": "登录时启动 PaneGrid",
        "Accessibility settings": "辅助功能设置",
        "Excluded apps (bundle identifiers, one per line)": "排除的应用（bundle 标识，每行一个）",
        "Excluded application bundle identifiers": "排除的应用 bundle 标识",
        "Example: com.apple.finder": "示例：com.apple.finder",
        "Save exclusions": "保存排除项",
        "Use at most 100 bundle identifiers, each under 256 characters.": "最多使用 100 个 bundle 标识，每个不超过 256 个字符。",
        "Excluded apps will not appear in the picker or workspace.": "排除的应用不会出现在选择器或工作区中。",
        "PaneGrid %@ · Built for your desktop, not a server. No accounts, telemetry, subscriptions, or screen recording.": "PaneGrid %@ · 为你的桌面而作，不依赖服务器。无需账户，无遥测、无订阅、无屏幕录制。",
        "Development": "开发版",
        "Language": "语言",
        "Interface language. System follows this Mac. Changes apply immediately.": "界面语言。「跟随系统」使用此 Mac 的当前语言。切换后立即生效。",

        // MARK: 已保存的布局
        "%ld layouts · empty slots are welcome": "%ld 个布局 · 允许留空位置",
        "%@ · %ld windows": "%@ · %ld 个窗口",
        "Import…": "导入…",
        "Export…": "导出…",
        "A place for every routine.": "每项日常，都有归处。",
        "Make a layout in Workspace, give it a name, and save it here. Load it later without opening apps or guessing which document belongs where.": "在工作区整理好布局，命名并保存到这里。以后载入时无需手动打开应用，也不用猜测每份文稿该放在哪里。",
        "Create a layout": "创建布局",
        "Load into editor": "载入编辑器",
        "Delete %@": "删除 %@",
        "Matching uses the app and exact window title. Missing or ambiguous matches remain empty. Imported layouts do not run code or launch apps.": "匹配依据是应用与精确的窗口标题。缺失或存在歧义的匹配会保持空白。导入的布局不会执行代码或启动应用。",
        "Delete this layout?": "删除此布局？",
        "Delete": "删除",
        "Your windows will not be moved.": "你的窗口不会被移动。",

        // MARK: 状态提示
        "Select windows, draw a tile, and make it yours.": "选择窗口，画出区域，让一切各就各位。",
        "Window control is ready. Hover a green button or press %@.": "窗口控制已就绪。悬停绿色按钮，或按下 %@。",
        "That region is occupied. Clear the region first, or choose an empty one.": "该区域已被占用。请先清除该区域，或选择空白区域。",
        "%@ assigned to %ld × %ld cells. Apply when ready.": "%@ 已分配到 %ld × %ld 个单元格。准备就绪后应用。",
        "%ld windows placed in the draft. Empty cells stay empty.": "已在草稿中放置 %ld 个窗口，空白单元格保持空白。",
        "%ld selected windows do not fit and will remain unchanged.": "%ld 个已选窗口放不下，将保持不变。",
        "%ld selected windows do not fit. Choose a grid with more cells; nothing was moved.": "%ld 个已选窗口放不下。请选择单元格更多的网格；未移动任何窗口。",
        "The target app is no longer available for tiling. Open its picker again.": "目标应用已不可用于平铺。请重新打开它的选择器。",
        "Wait for the current arrangement to finish before tiling an app.": "请等待当前排布完成后再平铺应用。",
        "Queued %@. It will run as soon as the current arrangement finishes.": "已排队 %@，当前排布完成后立即执行。",
        "The target app or display changed before the queued command could run. Nothing new was moved.": "排队命令执行前，目标应用或显示器已变更。未移动任何窗口。",
        "Tiling %@ using %@…": "正在平铺 %@（使用 %@）…",
        "The window is larger than this display. Use Fill first.": "窗口比此显示器更大。请先使用「铺满」。",
        "Arranging %ld windows…": "正在排布 %ld 个窗口…",
        "Stopping new moves and restoring changed windows…": "正在停止新的移动并还原已变更的窗口…",
        "Previous window positions restored.": "已还原之前的窗口位置。",
        "Give the layout a name (up to 100 saved layouts).": "请为布局命名（最多保存 100 个布局）。",
        "Saved “%@”. Missing windows stay blank.": "已保存「%@」。缺失的窗口保持空白。",
        "Saved “%@”. Missing windows stay blank. %ld ambiguous window(s) were omitted; give their documents unique titles to save them.": "已保存「%@」。缺失的窗口保持空白。已省略 %ld 个标题不明确的窗口；请为其文稿设置唯一标题后再保存。",
        "Loaded “%@”: %ld/%ld windows matched. Missing slots stay blank.": "已载入「%@」：匹配 %ld/%ld 个窗口。缺失的位置保持空白。",
        "Approve PaneGrid in System Settings → General → Login Items.": "请在「系统设置 → 通用 → 登录项」中允许 PaneGrid。",
        "Saved layouts contain application identifiers and window titles. Review before sharing.": "已保存的布局包含应用标识与窗口标题。分享前请先检查。",
        "Settings and layouts exported.": "设置与布局已导出。",
        "Import layouts without replacing existing settings or layouts. Up to 100 layouts total.": "导入布局且不覆盖现有设置或布局。布局总数上限为 100。",
        "Imported %ld new layouts. Your current settings were kept.": "已导入 %ld 个新布局，当前设置保持不变。",
        "Build the app bundle to include the practice windows.": "请先构建应用包以包含练习窗口。",
        "Settings could not be saved: %@": "设置无法保存：%@",
        "Settings could not be read or backed up. Saving is disabled to protect the original file.": "设置无法读取或备份。为保护原始文件，保存功能已停用。",
        "Settings could not be read. The original was preserved in Application Support; defaults are in use.": "设置无法读取。原始文件已保留在 Application Support 中，当前使用默认设置。",

        // MARK: 选择器浮层
        "PaneGrid Picker": "PaneGrid 选择器",
        "PaneGrid Preview": "PaneGrid 预览",
        "Green-button press-and-hold is unavailable because the mouse event tap could not be enabled. Hover (when enabled) and the picker shortcut still work.": "无法启用鼠标事件监听，绿色按钮按住功能不可用。悬停（若已开启）与选择器快捷键仍可使用。",
        "Enable Accessibility and resume PaneGrid before opening the picker.": "请先启用辅助功能访问并恢复 PaneGrid，再打开选择器。",
        "Focus a resizable application window first.": "请先聚焦一个可调整大小的应用窗口。",
        "This window cannot be resized. Try a normal, non-fullscreen window.": "此窗口无法调整大小。请尝试普通的非全屏窗口。",

        // MARK: 窗口访问与执行结果
        "The app’s window list could not be read. Nothing was moved. Try again when the app responds.": "无法读取该应用的窗口列表。未移动任何窗口。请等应用恢复响应后重试。",
        "This app has more than 128 windows. Nothing was moved; use a smaller selected group.": "此应用有超过 128 个窗口。未移动任何窗口；请缩小所选范围。",
        "The target window closed or is no longer resizable. Open the picker again.": "目标窗口已关闭或不再可调整大小。请重新打开选择器。",
        "Nothing to undo yet.": "暂无可撤销的操作。",
        "Enable Accessibility access to arrange windows.": "请启用辅助功能访问以排布窗口。",
        "Assign at least one window first.": "请先分配至少一个窗口。",
        "The arrangement contains too many or duplicate windows.": "该排布包含过多或重复的窗口。",
        "Arrangement stopped before moving any windows.": "排布在移动任何窗口前已停止。",
        "The same live window was assigned twice. Refresh the window list; nothing was moved.": "同一个窗口被分配了两次。请刷新窗口列表；未移动任何窗口。",
        "A window closed, became fullscreen, or cannot be resized. Refresh and try again.": "某个窗口已关闭、进入全屏或无法调整大小。请刷新后重试。",
        "%ld windows arranged. Unassigned cells stay empty.": "已排布 %ld 个窗口，未分配的单元格保持空白。",
        "%ld window arranged. Unassigned cells stay empty.": "已排布 %ld 个窗口，未分配的单元格保持空白。",
        "Previous positions restored.": "已还原之前的位置。",
        "%ld window(s) could not be restored.": "%ld 个窗口无法还原。",
        "%@ kept changing the layout after resizing. %@": "%@ 在调整大小后仍不断改变布局。%@",
        "arrangement was cancelled.": "排布已取消。",
        "arrangement exceeded its bounded response time.": "排布超出限定响应时间。",
        "kept the window at %@ pt instead of %@ pt. This portion is below the app’s observed size limit.": "让窗口保持在 %@ pt，而不是 %@ pt。该区域小于此应用可接受的最小尺寸。",
        "stopped accepting window-control requests.": "不再接受窗口控制请求。",
        "accepted the %@ pt size but did not move to (%ld, %ld). Actual position: (%ld, %ld).": "接受了 %@ pt 的尺寸，但未移动到 (%ld, %ld)。实际位置：(%ld, %ld)。",
        "did not settle at %@ pt (last size: %@).": "未能稳定在 %@ pt（最后尺寸：%@）。",
        "Previous positions restored; no replacement layout was applied. Try a larger portion if the app requires it.": "已还原之前的位置，未应用替代布局。若该应用需要更大空间，请尝试更大的区域。",
        "%ld window(s) could not be restored; inspect them before retrying.": "%ld 个窗口无法还原；重试前请先检查它们。",
        "unavailable": "不可用",
        "Tiled all %ld eligible %@ windows using %@. Other apps were untouched.": "已平铺 %ld 个 %@ 窗口（使用 %@），其他应用未受影响。",
        "%@ was not applied. %@ Your chosen grid has not been changed.": "%@ 未应用。%@ 你选择的网格未被更改。",

        // MARK: 快捷键
        "The global shortcut handler could not start (%ld).": "全局快捷键处理程序无法启动（%ld）。",
        "%@ is unavailable (%ld). Choose the other shortcut in Settings.": "%@ 不可用（%ld）。请在设置中选择另一个快捷键。",
        "Disabled": "已停用",

        // MARK: 网格校验
        "A tile is outside the grid. Choose a new region.": "区域超出网格范围。请重新选择区域。",
        "The display has no usable space for this grid.": "此显示器没有可用于该网格的空间。",
        "Two assignments overlap. Clear one of them first.": "两个分配区域重叠。请先清除其中一个。",
        "A window can only be assigned once.": "同一个窗口只能分配一次。",
        "This layout file is invalid or uses an unsupported version.": "此布局文件无效，或使用了不支持的版本。"
    ]
}
