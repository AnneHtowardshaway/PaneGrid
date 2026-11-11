# PaneGrid

[English](#english) · [简体中文](#简体中文)

---

## English

**An original, free, open-source window workspace for macOS.**

Draw a tile. Give it a window. Leave the rest open.

PaneGrid is a native SwiftUI/AppKit menu-bar utility for arranging your own desktop. It runs locally, without accounts, network services, analytics, subscriptions, or third-party package dependencies.

![The native PaneGrid workspace with six practice windows and empty cells](docs/pr-assets/first-release/workspace-practice-20260913.png)

*Historical 1.0 native-window capture; current versions use full-card selection, dimension-labelled presets, and no Place button. Cropped to omit display-identifying information.*

### What it does

- **A picker beside the green button.** Hover or hold the actual macOS zoom button for about half a second, or press **Control–Option–Space**. Ordinary short clicks keep their normal fullscreen behavior.
- **Any grid from 1 × 1 to 24 × 24.** Presets are labelled consistently: **2 × 1, 2 × 2, 3 × 1, 3 × 2, 3 × 3, 4 × 2, 4 × 3, 4 × 4**, and larger. Dimensions are always **columns × rows**, not unexplained fractions. Presets wrap into visible rows instead of hiding in a horizontal scroller.
- **Multi-cell tiles.** Drag across adjacent cells to make any rectangular span. Release in the quick picker to resize that window.
- **Full-card selection.** Click anywhere on a window card to select or deselect it—there is no separate **Place** button. Choose a grid and **Apply arrangement** to tile the selected windows together. With exactly one window selected, drag a grid region to assign its custom span before applying.
- **Equal-cell auto-placement.** Fill unused cells with only the windows you checked. Existing assigned spans are respected; unused cells remain empty.
- **One-click app-wide tiling.** Enable **Tile all windows of this app** in the picker, then choose a preset to tile every eligible window in that exact app process. No manual group selection is needed. A drawn span gives them all that size.
- **Exact preset commands.** Switching from 3 × 2 to 4 × 2 keeps the 4 × 2 request. Movement and resizing settle separately against actual screen geometry; a logical Accessibility destination alone is not treated as a completed animation. If an app refuses a size, the picker explains the failure and leaves your chosen grid selected.
- **Optional fitting suggestions.** **Suggest a fitting grid if needed** offers an alternative after a measured size response, but never applies a replacement automatically. Choose **Try … instead** explicitly if you want it. The old `autoFitAppWindows` setting is preserved and now controls suggestions only.
- **Optional selected-group reflow.** A snapped window keeps its chosen span; your checked group is packed into the remaining cells. No unselected windows are added.
- **Saved layouts.** Name arrangements, load them into the editor, and export/import validated JSON. Missing and ambiguously titled windows remain blank instead of being guessed or launched.
- **Multiple displays.** Choose a destination display, including displays above or to the left of the primary screen. The usable desktop keeps the menu bar and Dock clear.
- **Undo and fit checks.** Up to 20 successful arrangements can be undone. Actual window frames are checked. A failed batch attempts to restore its previous positions and reports any restoration failures.
- **Bounded recovery.** Workspace has a **Cancel** button while arranging. Cancellation stops new moves, lets in-flight work drain, and restores changed windows before enabling another command. Failed operations do not continuously retry untouched windows.
- **Your preferences.** Grid dimensions, gaps, margins, hover delay, Option-only hover, previews, reflow, shortcut alternatives, app exclusions, appearance, pause, and optional launch at login.
- **English and Simplified Chinese.** The interface follows your macOS language, or you can lock either language in Settings. The switch applies immediately without restarting.
- **Practice safely.** A bundled practice app opens six ordinary windows so you can learn without rearranging your work.

### Requirements

- macOS **14 Sonoma or newer**.
- For building: Xcode/Command Line Tools with **Swift 6.0+**.
- Accessibility permission for the installed PaneGrid app. **No Screen Recording or Input Monitoring permission is required for window management.**

The workspace editor is designed for at least 1050 × 740 points of desktop space. The small picker can be used without leaving the full editor open.

### Build and install

From the repository root:

```sh
swift test
/bin/zsh scripts/build-app.sh
/bin/zsh scripts/install-app.sh
```

This creates `build/PaneGrid.app`, installs it in the shared `/Applications` folder, and opens it. Each macOS user grants their own permission and has separate settings. If that folder is not writable, the installer stops rather than asking for an administrator password in a script; an administrator can copy the app with Finder.

In VS Code, **Run Build Task → PaneGrid: Build app** builds the app. No editor extensions are necessary.

#### Local signing and updates

The build script defaults to **ad-hoc local signing**. If you already have a signing identity, you can keep a stable identity across rebuilds:

```sh
PANEGRID_SIGN_IDENTITY="Apple Development" /bin/zsh scripts/build-app.sh
/bin/zsh scripts/install-app.sh
```

The variable is optional; no `.env`, API keys, or online account is needed to build. Do not commit certificates or private keys. Ad-hoc rebuilds may need Accessibility approval again. When upgrading, the installer asks the existing app to quit, verifies the staged bundle, and refuses to replace a still-running instance. It retains the previous bundle in its temporary staging directory for recovery.

**Local signing is not notarization.** A downloadable binary for other Macs requires your own Developer ID signing/notarization workflow. Publishing the source does not require that. Do not instruct people to disable Gatekeeper, SIP, or macOS privacy protections.

### First use

1. Open **PaneGrid** from Applications.
2. Choose **Enable window control**. In **System Settings → Privacy & Security → Accessibility**, enable **PaneGrid**. Authenticate directly in macOS if asked. If it is missing from the list, use **+** to add `/Applications/PaneGrid.app`.
3. Return to PaneGrid. Permission is detected automatically; no restart should be needed.
4. Open **practice windows** from the menu bar or Settings if you want a harmless first try.
5. Hover or hold a green window button, or focus a normal window and press **⌃⌥ Space**.
6. Pick a grid and drag a tile. A destination outline previews the position; release to resize.

For several windows, open **Workspace**, click the cards you want, choose a grid, and select **Apply arrangement**. Auto-placement happens as part of Apply; **Auto-place selected** is optional if you want to preview it first. With one window selected, dragging on the grid assigns its custom span. Nothing moves until Apply. A 6 × 6 grid does not require 36 windows: one window can occupy several cells and everything else can stay empty.

To tile one entire app without checking windows individually, open that app's picker, enable **Tile all windows of this app**, and click **3 × 2**, **4 × 2**, **3 × 3**, or another preset. For custom row/column values, choose **Tile app windows**. Only that app's eligible windows are moved. Unused portions stay empty. When an app-wide request is already running, commands are serialized and only the newest pending request is kept; an older completion cannot restore an earlier preset on top of it.

Press-and-hold uses a mouse event tap after the green button has been verified. A quick click is replayed normally; unrelated clicks are not intercepted. Holding works even if ordinary hover is disabled. If the event tap cannot be enabled, PaneGrid reports that and retains the hover/shortcut entry points.

#### Keyboard controls

| Control | Action |
| --- | --- |
| ⌃⌥ Space | Open the quick picker for the last external focused window |
| ⌃⇧ Space | Alternative shortcut, selectable in Settings |
| Arrow keys (grid focused) | Move the selected region |
| Shift + arrows | Grow/shrink its span |
| Return (quick-picker grid focused) | Apply the region |
| Escape | Close the picker |

Close the editor window to keep PaneGrid in the menu bar. Use **Quit PaneGrid** to stop window management completely. Launch at login is opt-in.

### Important macOS limits

- Public APIs do **not** let third-party apps insert items into the system's green-button menu. PaneGrid provides a separate nearby panel; it does not patch macOS or globally disable native tiling. If the native menu gets in the way, use the shortcut or enable **Require Option while hovering**.
- Apps control their minimum/maximum window sizes. A tiny single cell in a dense grid may not fit an editor or browser. Select a larger span; PaneGrid does not bypass the app's limits.
- Standard, resizable Accessibility windows are supported. Fullscreen, minimized, hidden-app, dialog, and non-resizable windows are excluded. Apps with incomplete Accessibility support may not expose a zoom button; try the shortcut, and expect a clear failure if sizing is unsupported.
- Window lists are app-provided and can include windows on other Spaces. PaneGrid does not switch Spaces or promise that all applications expose inactive-Space windows. It moves only explicitly assigned/selected windows.
- Saved layouts use an exact app identifier and unique window title, not a persistent document ID. Renamed, missing, or duplicate-title windows must be assigned again. Duplicate titles are deliberately omitted when saving; empty regions are preserved.
- Resizing several apps is sequential, not an OS-level atomic transaction. Rollback is best effort: if an app closes or stops responding, restoration can also fail, and PaneGrid reports that rather than claiming success.

### Privacy and local data

Settings and saved layouts live in:

`~/Library/Application Support/PaneGrid/configuration.json`

Writes are atomic, the directory is private to your account, and malformed/unsupported files are preserved before falling back to defaults. Exported layouts contain **application identifiers and window titles**: review them before publishing or sharing. Window contents, keystrokes, and screenshots are not collected or transmitted. See [PRIVACY.md](PRIVACY.md).

### Verification

```sh
swift test
.build/debug/PaneGrid --verify-interface /tmp/PaneGrid-interface.json
/bin/zsh scripts/verify-native.sh
/Applications/PaneGrid.app/Contents/MacOS/PaneGrid --verify-presets /tmp/PaneGrid-presets.json
.build/debug/PaneGrid --verify-language /tmp/PaneGrid-language.json
python3 scripts/verify-localization.py
```

- Core tests cover every 1–24 dimension pair, fractional geometry, spans, monitor transforms, invalid input, packing, and serialization.
- The interface probe uses actual AppKit windows, light/dark themes, large grids, and minimum sizing. It also reinstates the original intrinsic-size bug on an isolated test window to prove the regression check is meaningful. Its settings are ephemeral and it never accesses other apps.
- Native verification runs the installed app against its bundled practice process only. It checks sixths/eighths/dense grids, unselected-window isolation, spans, reflow, undo, rollback after minimum-size refusal, and the real green-button hit-test. **Exit 77 means permission/setup is blocked, not that tests passed.** It restores practice-window frames afterward.
- Preset verification runs 3 × 2 → 4 × 2 on the **same** six windows without resetting between commands. It includes delayed/coalesced and independently animated axes, Workspace → picker → Workspace transitions, cancellation, post-cancellation commands, and undo. It creates and closes only its own practice instances.
- Language verification switches the interface between English and Simplified Chinese inside one running process and measures the same window and picker budgets in both. `scripts/verify-localization.py` checks the translation table for missing, unused, or empty entries and for placeholder-order mismatches.

Build outputs, test artifacts, and local settings are ignored by Git. Review [docs/QA.md](docs/QA.md) for the actual verification status and the manual UI checklist.

### Screenshots

Actual macOS application captures, using only the bundled practice windows:

| Quick-picker controls | Settings |
| --- | --- |
| ![Compact picker with grid presets and selected-group reflow](docs/pr-assets/first-release/picker-controls-20260913.png) | ![Native settings for hover, keyboard shortcuts, reflow, and spacing](docs/pr-assets/first-release/settings-20260913.png) |

The picker image omits its header/display selector for privacy. See [the QA report](docs/QA.md#native-screenshots) for capture provenance and the drag-selection screenshot.

### Publish and contribute

This repository contains the original source, build/install scripts, a macOS CI workflow, and an MIT license. You can publish it to your own GitHub repository. No remote repository or public release is created by the installer.

Use the normal GitHub “new repository” flow, then add that remote to this local repository. Review the diff before publishing: do not add `build/`, `.build/`, signing files, personal layout exports, or screenshots containing your own window titles. See [CONTRIBUTING.md](CONTRIBUTING.md).

### Uninstall

Disable **Launch PaneGrid at login** if enabled, choose **Quit PaneGrid**, and move `/Applications/PaneGrid.app` to Trash. You may remove its Accessibility entry in System Settings. Keep the Application Support directory to preserve layouts, or remove that exact directory to reset all preferences. The app does not install privileged helpers or system services.

### License

[MIT](LICENSE). Free to use, modify, and publish.

---

## 简体中文

**一款原创、免费、开源的 macOS 窗口工作区工具。**

画一格。交给一个窗口。其余保持敞开。

PaneGrid 是一款原生的 SwiftUI/AppKit 菜单栏工具，用来整理你自己的桌面。它完全在本机运行，不需要账户、网络服务、统计分析或订阅，也不依赖任何第三方包。

![包含六个练习窗口与空白单元格的原生 PaneGrid 工作区](docs/pr-assets/first-release/workspace-practice-20260913.png)

*1.0 时期的历史原生窗口截图；当前版本已改为整卡选择、带尺寸标注的预设，并取消了「放置」按钮。为隐去显示器识别信息，截图经过裁剪。*

### 功能

- **绿色按钮旁的选择器。** 悬停或按住 macOS 真实的缩放按钮约半秒，或按 **Control–Option–Space**。普通的短按仍保留原本的全屏行为。
- **1 × 1 到 24 × 24 的任意网格。** 预设命名始终一致：**2 × 1、2 × 2、3 × 1、3 × 2、3 × 3、4 × 2、4 × 3、4 × 4** 以及更大尺寸。尺寸一律是**列 × 行**，不使用难以理解的分数。预设会自动换行显示，不会藏进横向滚动区。
- **跨多格的区域。** 在相邻单元格上拖拽，即可构成任意矩形跨度。在快捷选择器中松开鼠标，即调整该窗口大小。
- **整卡选择。** 点击窗口卡片任意位置即可选中或取消选中——没有单独的**放置**按钮。选择网格并点**应用排布**，即可把已选窗口一起平铺。只选中一个窗口时，可在应用前于网格上拖拽，指定它的自定义跨度。
- **等格自动放置。** 只用你勾选的窗口去填充空格。已分配的跨度会被保留；未使用的单元格保持空白。
- **一键平铺整个应用。** 在选择器中启用**平铺此应用的所有窗口**，再选一个预设，即可平铺该应用进程内所有符合条件的窗口。无需手动分组。手绘的跨度会成为它们统一的尺寸。
- **预设即精确指令。** 从 3 × 2 切到 4 × 2，就按 4 × 2 执行。移动与缩放会分别依据真实屏幕几何确认到位；仅有一个逻辑上的辅助功能目标位置，不会被当作动画已完成。若某个应用拒绝某个尺寸，选择器会说明失败原因，并保持你选中的网格不变。
- **可选的适配建议。** **需要时建议合适的网格**会在测得实际尺寸响应后给出替代方案，但绝不会自动替换。若确实想用，请显式点击**改用 …**。原有的 `autoFitAppWindows` 设置被保留，现在只用于控制建议。
- **可选的已选组合重排。** 被吸附的窗口保留其选定的跨度；你勾选的组合会被打包进剩余单元格。未选中的窗口不会被加入。
- **已保存的布局。** 为排布命名、载入编辑器，并导出/导入经过校验的 JSON。缺失或标题有歧义的窗口会保持空白，而不是被猜测或启动。
- **多显示器。** 可选择目标显示器，包括位于主屏幕上方或左侧的显示器。可用桌面区域会避开菜单栏与 Dock。
- **撤销与适配检查。** 最多可撤销 20 次成功的排布。会校验真实的窗口边框。失败的批次会尝试还原此前位置，并报告任何还原失败。
- **有界恢复。** 排布过程中，工作区会显示**取消**按钮。取消会停止新的移动、等待在途操作结束，并在允许下一条命令前还原已变更的窗口。失败的操作不会对未触碰的窗口反复重试。
- **你的偏好设置。** 网格尺寸、间距、边距、悬停延迟、仅 Option 悬停、预览、重排、快捷键备选、应用排除、外观、暂停，以及可选的登录时启动。
- **英文与简体中文。** 界面跟随你的 macOS 语言，也可以在设置中锁定其中任意一种。切换立即生效，无需重启。
- **安全练手。** 内置练习应用会打开六个普通窗口，让你在不打乱正经工作的前提下熟悉操作。

### 系统要求

- macOS **14 Sonoma 或更新版本**。
- 构建需要：安装 **Swift 6.0+** 的 Xcode 或 Command Line Tools。
- 已安装的 PaneGrid 需要辅助功能权限。**窗口管理不需要屏幕录制或输入监听权限。**

工作区编辑器按至少 1050 × 740 点的桌面空间设计。小巧的选择器无需打开完整编辑器也能使用。

### 构建与安装

在仓库根目录执行：

```sh
swift test
/bin/zsh scripts/build-app.sh
/bin/zsh scripts/install-app.sh
```

这会生成 `build/PaneGrid.app`，安装到共享的 `/Applications` 目录并打开。每个 macOS 用户各自授权，设置也各自独立。若该目录不可写，安装脚本会直接停止，而不会在脚本里索要管理员密码；可由管理员用 Finder 手动拷贝。

在 VS Code 中，**Run Build Task → PaneGrid: Build app** 即可构建应用。无需任何编辑器扩展。

#### 本地签名与更新

构建脚本默认使用 **ad-hoc 本地签名**。若你已有签名身份，可让它在多次重新构建之间保持稳定：

```sh
PANEGRID_SIGN_IDENTITY="Apple Development" /bin/zsh scripts/build-app.sh
/bin/zsh scripts/install-app.sh
```

该变量是可选的；构建不需要 `.env`、API 密钥或在线账户。请勿提交证书或私钥。ad-hoc 重新构建后，可能需要重新授予辅助功能权限。升级时，安装脚本会请求现有应用退出、校验暂存的 bundle，并拒绝替换仍在运行的实例。它会把旧 bundle 保留在临时暂存目录中以便恢复。

**本地签名不等于公证。** 若要为其他 Mac 提供可下载的二进制包，需要你自己完成 Developer ID 签名与公证流程。发布源码则不需要。请勿指示他人关闭 Gatekeeper、SIP 或 macOS 的隐私保护。

### 首次使用

1. 从「应用程序」中打开 **PaneGrid**。
2. 点击**启用窗口控制**。在**系统设置 → 隐私与安全性 → 辅助功能**中启用 **PaneGrid**。若系统要求验证，请直接在 macOS 中完成。若列表中找不到它，用 **+** 添加 `/Applications/PaneGrid.app`。
3. 回到 PaneGrid。权限会被自动检测，通常无需重启。
4. 若想先无害地试一下，可从菜单栏或设置中打开**练习窗口**。
5. 悬停或按住窗口的绿色按钮，或先聚焦一个普通窗口，再按 **⌃⌥ Space**。
6. 选择网格并拖拽出一个区域。目标位置会以轮廓预览；松开即调整大小。

若要处理多个窗口，打开**工作区**，点击想要的卡片，选择网格，然后点**应用排布**。自动放置是「应用」过程的一部分；若想先预览，可单独使用**自动放置已选窗口**。只选中一个窗口时，在网格上拖拽即可指定它的自定义跨度。在点「应用」之前，什么都不会移动。6 × 6 的网格并不需要 36 个窗口：一个窗口可以占据多个单元格，其余都可以空着。

若要一次性平铺整个应用而不必逐个勾选窗口，打开该应用的选择器，启用**平铺此应用的所有窗口**，然后点击 **3 × 2**、**4 × 2**、**3 × 3** 或其他预设。若要用自定义的行/列值，选择**平铺应用窗口**。只有该应用中符合条件的窗口会被移动，未使用的部分保持空白。当应用级请求正在执行时，命令会被串行化，只保留最新的待处理请求；较早的完成结果无法覆盖其上恢复旧预设。

按住操作会在绿色按钮通过校验后使用鼠标事件监听。快速点击会被正常重放；无关的点击不会被拦截。即使关闭了普通悬停，按住操作仍然有效。若鼠标事件监听无法启用，PaneGrid 会说明情况，并保留悬停与快捷键两个入口。

#### 键盘操作

| 操作 | 行为 |
| --- | --- |
| ⌃⌥ Space | 为最近聚焦的外部窗口打开快捷选择器 |
| ⌃⇧ Space | 备选快捷键，可在设置中选择 |
| 方向键（网格聚焦时） | 移动选中区域 |
| Shift + 方向键 | 放大或缩小其跨度 |
| Return（快捷选择器网格聚焦时） | 应用该区域 |
| Escape | 关闭选择器 |

关闭编辑器窗口后，PaneGrid 会留在菜单栏。使用**退出 PaneGrid** 可完全停止窗口管理。登录时启动需手动开启。

### macOS 的重要限制

- 公开 API **不允许**第三方应用向系统的绿色按钮菜单插入条目。PaneGrid 提供一个附近的独立面板；它不会修改 macOS，也不会全局关闭原生平铺。若原生菜单碍事，可使用快捷键，或启用**悬停时需要按住 Option**。
- 窗口的最小/最大尺寸由各应用控制。密集网格中的单个小格可能放不下编辑器或浏览器。请选择更大的跨度；PaneGrid 不会绕过应用自身的限制。
- 支持标准的、可调整大小的辅助功能窗口。全屏、最小化、隐藏应用、对话框以及不可调整大小的窗口会被排除。辅助功能支持不完整的应用可能不暴露缩放按钮；可改用快捷键，若确实不支持调整尺寸，会得到明确的失败提示。
- 窗口列表由各应用提供，可能包含其他「空间」中的窗口。PaneGrid 不会切换空间，也不保证所有应用都会暴露非活动空间中的窗口。它只移动被明确分配或选中的窗口。
- 已保存的布局使用精确的应用标识与唯一的窗口标题，而非持久化的文稿 ID。标题被改动、窗口缺失或标题重复的窗口需要重新分配。保存时会刻意跳过标题重复的窗口；空白区域会被保留。
- 多个应用的调整是串行执行的，并非操作系统级的原子事务。回滚是尽力而为：若某个应用关闭或停止响应，还原也可能失败，此时 PaneGrid 会如实报告，而不会谎称成功。

### 隐私与本地数据

设置与已保存的布局存放在：

`~/Library/Application Support/PaneGrid/configuration.json`

写入是原子的，该目录仅你的账户可访问；格式错误或不受支持的文件会先被保留，然后才回退到默认设置。导出的布局包含**应用标识与窗口标题**：发布或分享前请先检查。窗口内容、按键与截图不会被收集或传输。详见 [PRIVACY.md](PRIVACY.md)。

### 验证

```sh
swift test
.build/debug/PaneGrid --verify-interface /tmp/PaneGrid-interface.json
/bin/zsh scripts/verify-native.sh
/Applications/PaneGrid.app/Contents/MacOS/PaneGrid --verify-presets /tmp/PaneGrid-presets.json
.build/debug/PaneGrid --verify-language /tmp/PaneGrid-language.json
python3 scripts/verify-localization.py
```

- 核心测试覆盖 1–24 的每一个尺寸组合、分数几何、跨度、显示器坐标变换、非法输入、打包与序列化。
- 界面探测使用真实的 AppKit 窗口、浅色/深色主题、大网格与最小尺寸。它还会在一个隔离的测试窗口上重现最初的内建尺寸缺陷，以证明该回归检查确实有效。其设置为临时数据，且从不访问其他应用。
- 原生验证只让已安装的应用针对其内置的练习进程运行。它检查 6 分、8 分与密集网格，未选中窗口的隔离，跨度，重排，撤销，最小尺寸被拒后的回滚，以及真实绿色按钮的命中测试。**退出码 77 表示权限或环境被阻塞，并不意味着测试通过。** 验证结束后会还原练习窗口的边框。
- 预设验证在**同一批**六个窗口上执行 3 × 2 → 4 × 2，命令之间不重置。它涵盖延迟与合并、各轴独立动画、工作区 → 选择器 → 工作区的切换、取消、取消后的命令，以及撤销。它只创建并关闭自己的练习实例。
- 语言验证在同一个运行中的进程内切换英文与简体中文，并在两种语言下测量相同的窗口与选择器尺寸预算。`scripts/verify-localization.py` 会检查翻译表是否存在缺失、冗余或空译文，以及键与译文的占位符顺序是否错位。

构建产物、测试工件与本地设置会被 Git 忽略。实际的验证状态与手动 UI 检查清单见 [docs/QA.md](docs/QA.md)。

### 截图

真实的 macOS 应用截图，仅使用内置的练习窗口：

| 快捷选择器控件 | 设置 |
| --- | --- |
| ![带网格预设与已选组合重排的紧凑选择器](docs/pr-assets/first-release/picker-controls-20260913.png) | ![悬停、快捷键、重排与间距的原生设置界面](docs/pr-assets/first-release/settings-20260913.png) |

为保护隐私，选择器截图省略了它的头部与显示器选择器。截图来源与拖拽选择截图见 [QA 报告](docs/QA.md#native-screenshots)。

### 发布与贡献

本仓库包含原始源码、构建/安装脚本、一个 macOS CI 工作流，以及 MIT 许可证。你可以把它发布到你自己的 GitHub 仓库。安装脚本不会创建远程仓库或公开发布。

使用 GitHub 常规的「新建仓库」流程，然后把该远程仓库添加到本地的这个仓库。发布前请检查 diff：不要提交 `build/`、`.build/`、签名文件、个人布局导出，或包含你自己窗口标题的截图。详见 [CONTRIBUTING.md](CONTRIBUTING.md)。

### 卸载

若已启用**登录时启动 PaneGrid**，请先关闭它；选择**退出 PaneGrid**，然后把 `/Applications/PaneGrid.app` 移到废纸篓。你也可以在系统设置中移除它的辅助功能条目。保留 Application Support 目录即可保留布局；删除该目录会重置全部偏好设置。本应用不会安装特权辅助程序或系统服务。

### 许可证

[MIT](LICENSE)。可自由使用、修改与发布。
