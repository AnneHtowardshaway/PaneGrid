import AppKit
import SwiftUI
import PaneGridCore

@MainActor
enum WorkspaceWindow {
    static func make(state: AppState, restoreFrame: Bool = true) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1140, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "PaneGrid"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 1050, height: 740)
        window.isReleasedWhenClosed = false
        let content = NSHostingView(rootView: PaneGridRootView(state: state))
        // AppKit owns the window size. A flexible SwiftUI grid must not feed intrinsic sizes back into it.
        content.sizingOptions = []
        content.autoresizingMask = [.width, .height]
        content.frame = NSRect(x: 0, y: 0, width: 1140, height: 800)
        window.contentView = content
        if restoreFrame { window.setFrameAutosaveName("PaneGrid.Workspace") }
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            window.setFrame(GridGeometry.clampPanel(window.frame, to: screen.visibleFrame), display: false)
        }
        window.center()
        return window
    }
}
