import Foundation
import Carbon
import AppKit

public final class HotKeyManager {
    public static let shared = HotKeyManager()
    
    public var onRecordArea: (() -> Void)?
    public var onRecordWindow: (() -> Void)?
    public var onRecordScreen: (() -> Void)?
    public var onStop: (() -> Void)?
    
    private var eventHandler: EventHandlerRef?
    
    public enum HotKeyAction: UInt32 {
        case recordArea = 1
        case recordWindow = 2
        case recordScreen = 3
        case stopRecording = 4
    }
    
    private init() {}
    
    public func registerHotKeys() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, theEvent, _) -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    theEvent,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if err == noErr {
                    DispatchQueue.main.async {
                        HotKeyManager.shared.dispatch(actionId: hotKeyID.id)
                    }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )
        
        if status != noErr {
            print("[HotKeyManager] Failed to install Carbon event handler: \(status)")
            return
        }
        
        // Modifiers: Command + Option
        let modifiers = UInt32(cmdKey | optionKey)
        
        // ⌘⌥1: Record Area (Key code 18 = '1')
        registerKey(keyCode: 18, modifiers: modifiers, action: .recordArea)
        
        // ⌘⌥2: Record Window (Key code 19 = '2')
        registerKey(keyCode: 19, modifiers: modifiers, action: .recordWindow)
        
        // ⌘⌥3: Record Full Screen (Key code 20 = '3')
        registerKey(keyCode: 20, modifiers: modifiers, action: .recordScreen)
        
        // ⌘⌥S: Stop Recording (Key code 1 = 'S')
        registerKey(keyCode: 1, modifiers: modifiers, action: .stopRecording)
        
        print("[HotKeyManager] Global hotkeys registered: ⌘⌥1 (Area), ⌘⌥2 (Window), ⌘⌥3 (Screen), ⌘⌥S (Stop)")
    }
    
    private func registerKey(keyCode: UInt32, modifiers: UInt32, action: HotKeyAction) {
        let hotKeyID = EventHotKeyID(
            signature: OSType(0x53524543), // 'SREC'
            id: action.rawValue
        )
        var hotKeyRef: EventHotKeyRef?
        let result = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if result != noErr {
            print("[HotKeyManager] Could not register hotkey for action \(action): \(result)")
        }
    }
    
    private func dispatch(actionId: UInt32) {
        guard let action = HotKeyAction(rawValue: actionId) else { return }
        switch action {
        case .recordArea:
            onRecordArea?()
        case .recordWindow:
            onRecordWindow?()
        case .recordScreen:
            onRecordScreen?()
        case .stopRecording:
            onStop?()
        }
    }
}
