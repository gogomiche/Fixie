import Cocoa
import Carbon.HIToolbox

/// Manages global hotkey registration via Carbon. Supports multiple
/// independent hotkeys, one per `GrammarMode`.
class HotkeyManager {
    private struct Registration {
        let hotkeyRef: EventHotKeyRef
        let callback: () -> Void
    }

    private var settingsManager: SettingsManager
    private var eventHandler: EventHandlerRef?
    private var registrations: [UInt32: Registration] = [:]  // keyed by EventHotKeyID.id

    /// Carbon EventHotKeyID signature ('FIXI'). Each mode gets a distinct
    /// numeric id below.
    private let signature: OSType = OSType(0x4649_5849)

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
    }

    /// Register all current hotkeys from settings. Idempotent — calling again
    /// clears the previous registrations first.
    func registerAll() {
        unregisterAll()
        installEventHandlerIfNeeded()

        for mode in GrammarMode.allCases {
            register(hotkey: settingsManager.hotkey(for: mode), id: hotkeyID(for: mode)) { [weak self] in
                self?.onHotkeyPressed(mode: mode)
            }
        }
    }

    /// Callback invoked when one of the registered hotkeys fires.
    /// AppDelegate sets this to route to the appropriate trigger.
    var onModeHotkey: ((GrammarMode) -> Void)?

    private func onHotkeyPressed(mode: GrammarMode) {
        onModeHotkey?(mode)
    }

    private func hotkeyID(for mode: GrammarMode) -> UInt32 {
        switch mode {
        case .grammar: return 1
        case .improve: return 2
        }
    }

    private func register(hotkey: HotkeyConfig, id: UInt32, callback: @escaping () -> Void) {
        var carbonModifiers: UInt32 = 0
        if hotkey.modifiers & 0x100 != 0 { carbonModifiers |= UInt32(cmdKey) }
        if hotkey.modifiers & 0x800 != 0 { carbonModifiers |= UInt32(optionKey) }
        if hotkey.modifiers & 0x200 != 0 { carbonModifiers |= UInt32(shiftKey) }
        if hotkey.modifiers & 0x1000 != 0 { carbonModifiers |= UInt32(controlKey) }

        let hotkeyID = EventHotKeyID(signature: signature, id: id)
        var hotkeyRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            hotkey.keyCode,
            carbonModifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        guard status == noErr, let ref = hotkeyRef else {
            print("[HotkeyManager] Failed to register hotkey id=\(id): \(status)")
            return
        }

        registrations[id] = Registration(hotkeyRef: ref, callback: callback)
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let event = event,
                      let userData = userData else { return OSStatus(eventNotHandledErr) }

                var hotkeyID = EventHotKeyID()
                let getStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )
                guard getStatus == noErr else { return OSStatus(eventNotHandledErr) }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.registrations[hotkeyID.id]?.callback()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        if status != noErr {
            print("[HotkeyManager] Failed to install event handler: \(status)")
        }
    }

    func unregisterAll() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.hotkeyRef)
        }
        registrations.removeAll()
    }

    deinit {
        unregisterAll()
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
