import AppKit
import CoreGraphics

public final class PermissionManager {
    public static let shared = PermissionManager()
    
    private init() {}
    
    /// Check whether macOS Screen Recording permission has been granted
    public static func hasScreenRecordingPermission() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }
    
    /// Trigger macOS native screen capture authorization dialog
    @discardableResult
    public static func requestScreenRecordingPermission() -> Bool {
        return CGRequestScreenCaptureAccess()
    }
    
    /// Directly open macOS System Settings to the Screen Recording privacy pane
    public static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Preflight permission and present a helpful modal dialog with a button to System Settings if not granted
    @MainActor
    public func checkAndPromptScreenRecording(completion: @escaping (Bool) -> Void) {
        if PermissionManager.hasScreenRecordingPermission() {
            completion(true)
            return
        }
        
        // Trigger system request
        PermissionManager.requestScreenRecordingPermission()
        
        showPermissionAlert {
            completion(false)
        }
    }
    
    /// Present native modal alert informing user that Screen Recording permission is required
    @MainActor
    public func showPermissionAlert(onDismiss: (() -> Void)? = nil) {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "Luna requires Screen Recording permission to record your display, specific screens, or windows.\n\nPlease enable Luna in System Settings > Privacy & Security > Screen & System Audio Recording, then restart Luna."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        
        if let mascot = loadMascotImage() {
            alert.icon = mascot
        }
        
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            PermissionManager.openScreenRecordingSettings()
        }
        onDismiss?()
    }
    
    private func loadMascotImage() -> NSImage? {
        if let bundlePath = Bundle.main.path(forResource: "luna_mascot", ofType: "png"),
           let img = NSImage(contentsOfFile: bundlePath) {
            return img
        }
        let devPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("assets/luna_mascot.png").path
        if FileManager.default.fileExists(atPath: devPath) {
            return NSImage(contentsOfFile: devPath)
        }
        return NSApp.applicationIconImage
    }
}
