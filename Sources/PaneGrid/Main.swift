import AppKit

@main
enum PaneGridMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate: NSApplicationDelegate
        if CommandLine.arguments.contains("--verify-interface") { delegate = InterfaceVerificationDelegate() }
        else if CommandLine.arguments.contains("--verify-native") { delegate = NativeVerificationDelegate() }
        else if CommandLine.arguments.contains("--verify-presets") { delegate = PresetTransitionVerificationDelegate() }
        else { delegate = AppDelegate() }
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
