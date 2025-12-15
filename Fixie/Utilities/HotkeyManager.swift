import Cocoa
import Carbon.HIToolbox

class HotkeyManager {
    private var settingsManager: SettingsManager
    private var eventHandler: EventHandlerRef?
    private var hotkeyID: EventHotKeyID
    private var hotkeyRef: EventHotKeyRef?

    var onHotkeyPressed: (() -> Void)?

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
        self.hotkeyID = EventHotKeyID(signature: OSType(0x4649_5849), id: 1) // "FIXI"
    }

    func register() {
        unregister()

        let hotkey = settingsManager.hotkey

        // Convert SwiftUI modifiers to Carbon modifiers
        var carbonModifiers: UInt32 = 0
        if hotkey.modifiers & 0x100 != 0 { carbonModifiers |= UInt32(cmdKey) }
        if hotkey.modifiers & 0x800 != 0 { carbonModifiers |= UInt32(optionKey) }
        if hotkey.modifiers & 0x200 != 0 { carbonModifiers |= UInt32(shiftKey) }
        if hotkey.modifiers & 0x1000 != 0 { carbonModifiers |= UInt32(controlKey) }

        // Register the hotkey
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.onHotkeyPressed?()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        guard status == noErr else {
            print("Failed to install event handler: \(status)")
            return
        }

        let registerStatus = RegisterEventHotKey(
            hotkey.keyCode,
            carbonModifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        if registerStatus != noErr {
            print("Failed to register hotkey: \(registerStatus)")
        }
    }

    func unregister() {
        if let hotkeyRef = hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
        }
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    deinit {
        unregister()
    }
}
