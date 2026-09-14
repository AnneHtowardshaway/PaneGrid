import Carbon
import PaneGridCore

final class HotKeyManager {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onTrigger: (() -> Void)?

    func configure(_ shortcut: PickerShortcut) -> String? {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        guard shortcut != .disabled else { return nil }
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let result = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async { manager.onTrigger?() }
                return noErr
            }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard result == noErr else { return "The global shortcut handler could not start (\(result))." }
        }
        let modifiers = UInt32(controlKey | (shortcut == .controlOptionSpace ? optionKey : shiftKey))
        let identifier = EventHotKeyID(signature: OSType(0x50475244), id: 1)
        let result = RegisterEventHotKey(UInt32(kVK_Space), modifiers, identifier, GetApplicationEventTarget(), 0, &hotKey)
        return result == noErr ? nil : "\(shortcut.label) is unavailable (\(result)). Choose the other shortcut in Settings."
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
