import AppKit
import CoreGraphics

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup menu bar item, hotkeys, and visual picker
        MenuBarController.shared.setup()
        print("[Luna] Luna Screen Recorder running.")
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in menu bar and dock even when window is closed
        return false
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Clicking the Luna icon in the Dock opens the recordings manager
        RecordingsWindowController.shared.show()
        return true
    }
    
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let areaItem = NSMenuItem(title: "Record Area (⌘⌥1)", action: #selector(dockRecordArea), keyEquivalent: "")
        areaItem.target = self
        menu.addItem(areaItem)
        
        let visualItem = NSMenuItem(title: "Choose Window / Screen (⌘⌥2)", action: #selector(dockRecordVisual), keyEquivalent: "")
        visualItem.target = self
        menu.addItem(visualItem)
        
        let screenItem = NSMenuItem(title: "Record Full Screen (⌘⌥3)", action: #selector(dockRecordScreen), keyEquivalent: "")
        screenItem.target = self
        menu.addItem(screenItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let recentsItem = NSMenuItem(title: "Recent Recordings (⌘⌥R)", action: #selector(dockOpenRecents), keyEquivalent: "")
        recentsItem.target = self
        menu.addItem(recentsItem)
        
        let onboardingItem = NSMenuItem(title: "Welcome & Settings...", action: #selector(dockOpenOnboarding), keyEquivalent: "")
        onboardingItem.target = self
        menu.addItem(onboardingItem)
        
        return menu
    }
    
    @objc private func dockRecordArea() {
        MenuBarController.shared.startAreaRecording()
    }
    
    @objc private func dockRecordVisual() {
        MenuBarController.shared.showVisualPicker()
    }
    
    @objc private func dockRecordScreen() {
        MenuBarController.shared.startMainScreenRecording()
    }
    
    @objc private func dockOpenRecents() {
        RecordingsWindowController.shared.show()
    }
    
    @objc private func dockOpenOnboarding() {
        OnboardingWindowController.shared.show()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Regular mode: Shows Luna in the macOS Dock and the Menu Bar
app.setActivationPolicy(.regular)
app.run()
