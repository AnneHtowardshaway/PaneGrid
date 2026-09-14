import AppKit

/// Opt-in test responses at the real public frame setter used by AppKit window control.
final class VerificationFixtureWindow: NSWindow {
    enum Response { case normal, constrained, delayed, coalesced, animatedAxes }
    var response: Response = .normal
    private var pendingSize: DispatchWorkItem?
    private var pendingPosition: DispatchWorkItem?
    override func setFrame(_ requested: NSRect, display flag: Bool) {
        switch response {
        case .normal: super.setFrame(requested, display: flag)
        case .constrained:
            let width = max(1000, requested.width), height = max(320, requested.height)
            super.setFrame(NSRect(x: requested.minX, y: requested.maxY - height, width: width, height: height), display: flag)
        case .animatedAxes:
            // A real external AX window whose position and size responses each capture a
            // whole frame. Overlapping writes overwrite one another; serialized writes do not.
            let positionOnly = requested.size == frame.size
            let work = DispatchWorkItem { [weak self] in self?.finishFrame(requested) }
            if positionOnly { pendingPosition?.cancel(); pendingPosition = work }
            else { pendingSize?.cancel(); pendingSize = work }
            DispatchQueue.main.asyncAfter(deadline: .now() + (positionOnly ? 0.55 : 0.18), execute: work)
        case .delayed, .coalesced:
            // The coalesced mode reproduces a resize that takes longer only when changing
            // from a previously successful portion to a narrower one. Repeated requests
            // restart the receiving app's debounce, just as asynchronous desktop apps can.
            if response == .coalesced && requested.width >= frame.width {
                super.setFrame(requested, display: flag)
                return
            }
            guard requested.size != frame.size else { super.setFrame(requested, display: flag); return }
            pendingSize?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.finishSize(requested.size) }
            pendingSize = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (response == .coalesced ? 0.55 : 0.18), execute: work)
        }
    }
    private func finishSize(_ size: NSSize) {
        let current = frame
        super.setFrame(NSRect(x: current.minX, y: current.maxY - size.height, width: size.width, height: size.height), display: true)
    }
    private func finishFrame(_ frame: NSRect) { super.setFrame(frame, display: true) }
}

/// Real, separate-process windows for consented native integration tests. Never targets personal apps.
final class FixtureDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let constrained = CommandLine.arguments.contains("--verify-size-constraints")
        let delayed = CommandLine.arguments.contains("--verify-delayed-resize")
        let coalesced = CommandLine.arguments.contains("--verify-coalesced-resize")
        let animated = CommandLine.arguments.contains("--verify-animated-axes")
        for index in 0..<6 {
            let window = VerificationFixtureWindow(contentRect: NSRect(x: 100 + index * 48, y: 150 + index * 36, width: constrained ? 1100 : 560, height: 360),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Practice \(index + 1)"
            window.setAccessibilityIdentifier("panegrid.fixture.\(constrained ? "constraints" : animated ? "animatedAxes" : coalesced ? "coalesced" : delayed ? "delayed" : "standard")")
            window.minSize = constrained ? NSSize(width: 1000, height: 320) : NSSize(width: 100, height: 90)
            window.isReleasedWhenClosed = false
            let content = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 360))
            content.wantsLayer = true
            content.layer?.backgroundColor = NSColor(calibratedHue: CGFloat(index) / 8 + 0.42,
                                                     saturation: 0.45, brightness: 0.24, alpha: 1).cgColor
            let title = NSTextField(labelWithString: "\(index + 1)")
            title.font = .systemFont(ofSize: 48, weight: .semibold)
            title.textColor = .white
            title.alignment = .center
            title.translatesAutoresizingMaskIntoConstraints = false
            let label = NSTextField(labelWithString: "PaneGrid practice window")
            label.textColor = .white.withAlphaComponent(0.65)
            label.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(title)
            content.addSubview(label)
            NSLayoutConstraint.activate([
                title.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                title.centerYAnchor.constraint(equalTo: content.centerYAnchor, constant: -14),
                label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                label.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8)
            ])
            window.contentView = content
            window.makeKeyAndOrderFront(nil)
            window.response = constrained ? .constrained : animated ? .animatedAxes : coalesced ? .coalesced : delayed ? .delayed : .normal
            windows.append(window)
        }
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Practice Windows", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
enum FixtureMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = FixtureDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
