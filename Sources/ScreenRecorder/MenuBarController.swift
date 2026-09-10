import AppKit
import ScreenCaptureKit
import UserNotifications

public final class MenuBarController: NSObject, NSMenuDelegate {
    public static let shared = MenuBarController()
    
    private var statusItem: NSStatusItem!
    private var recordingTimer: Timer?
    private var recordingSeconds = 0
    
    private var activeStatusMenuItem: NSMenuItem!
    private var stopMenuItem: NSMenuItem!
    private var pauseMenuItem: NSMenuItem!
    private var recordAreaMenuItem: NSMenuItem!
    private var visualPickerMenuItem: NSMenuItem!
    private var recordWindowMenuItem: NSMenuItem!
    private var recordScreenMenuItem: NSMenuItem!
    private var recordSpecificScreenMenuItem: NSMenuItem!
    private var screenSubmenu: NSMenu!
    private var startSectionSeparator: NSMenuItem!
    private var recordingSectionSeparator: NSMenuItem!
    private var autoDeleteToggleItem: NSMenuItem!
    private var autoCopyPathToggleItem: NSMenuItem!
    private var windowSubmenu: NSMenu!
    private var micMenuItem: NSMenuItem!
    
    public override init() {
        super.init()
    }
    
    public func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItemIcon(isRecording: false)
        
        buildMenu()
        setupNotifications()
        setupHotKeys()
        if #available(macOS 14.0, *) {
            VisualPickerManager.shared.setup()
        }
        
        // Initial prune of old recordings on startup
        let pruned = RetentionManager.shared.pruneOldRecordings()
        if pruned > 0 {
            print("[MenuBarController] Auto-pruned \(pruned) files older than 15 days on launch")
        }
        
        // Check onboarding on startup
        if !RetentionManager.shared.hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                OnboardingWindowController.shared.show()
            }
        }
    }
    
    private func setupNotifications() {
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error = error {
                    print("[MenuBarController] Notification auth error: \(error)")
                }
            }
        }
        
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleStartRecordingNotification(_:)),
            name: NSNotification.Name("com.luna.screenrecorder.startRecording"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleStopRecordingNotification(_:)),
            name: NSNotification.Name("com.luna.screenrecorder.stopRecording"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }
    
    @objc private func handleStartRecordingNotification(_ notification: Notification) {
        print("[MenuBarController] Received startRecording notification")
        startMainScreenRecording()
    }
    
    @objc private func handleStopRecordingNotification(_ notification: Notification) {
        print("[MenuBarController] Received stopRecording notification")
        stopRecording()
    }
    
    private func setupHotKeys() {
        HotKeyManager.shared.onRecordArea = { [weak self] in
            self?.startAreaRecording()
        }
        HotKeyManager.shared.onRecordWindow = { [weak self] in
            self?.showVisualPicker()
        }
        HotKeyManager.shared.onRecordScreen = { [weak self] in
            self?.startMainScreenRecording()
        }
        HotKeyManager.shared.onStop = { [weak self] in
            self?.stopRecording()
        }
        HotKeyManager.shared.registerHotKeys()
    }
    
    private func updateStatusItemIcon(isRecording: Bool) {
        guard let button = statusItem.button else { return }
        if isRecording {
            button.image = nil
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
            button.title = "🔴 00:00"
        } else {
            button.title = ""
            if let image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Screen Recorder") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "⏺"
            }
        }
    }
    
    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        
        // Active recording controls (visible ONLY when recording)
        activeStatusMenuItem = NSMenuItem(title: "🔴 Recording in progress... 00:00", action: nil, keyEquivalent: "")
        activeStatusMenuItem.isEnabled = false
        activeStatusMenuItem.isHidden = true
        activeStatusMenuItem.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: nil)
        menu.addItem(activeStatusMenuItem)
        
        pauseMenuItem = NSMenuItem(title: "Pause / Resume Recording", action: #selector(togglePause), keyEquivalent: "p")
        pauseMenuItem.keyEquivalentModifierMask = [.command, .option]
        pauseMenuItem.target = self
        pauseMenuItem.isHidden = true
        pauseMenuItem.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: nil)
        menu.addItem(pauseMenuItem)
        
        stopMenuItem = NSMenuItem(title: "Stop Recording (⌘⌥S)", action: #selector(stopRecording), keyEquivalent: "s")
        stopMenuItem.keyEquivalentModifierMask = [.command, .option]
        stopMenuItem.target = self
        stopMenuItem.isHidden = true
        stopMenuItem.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: nil)
        menu.addItem(stopMenuItem)
        
        recordingSectionSeparator = NSMenuItem.separator()
        recordingSectionSeparator.isHidden = true
        menu.addItem(recordingSectionSeparator)
        
        // Capture triggers (visible ONLY when NOT recording)
        recordAreaMenuItem = NSMenuItem(title: "Record Area... (⌘⌥1)", action: #selector(startAreaRecording), keyEquivalent: "")
        recordAreaMenuItem.target = self
        recordAreaMenuItem.image = NSImage(systemSymbolName: "crop", accessibilityDescription: nil)
        menu.addItem(recordAreaMenuItem)
        
        recordScreenMenuItem = NSMenuItem(title: "Record Entire Screen (⌘⌥3)", action: #selector(startMainScreenRecording), keyEquivalent: "")
        recordScreenMenuItem.target = self
        recordScreenMenuItem.image = NSImage(systemSymbolName: "display", accessibilityDescription: nil)
        menu.addItem(recordScreenMenuItem)
        
        recordSpecificScreenMenuItem = NSMenuItem(title: "Record Specific Screen", action: nil, keyEquivalent: "")
        recordSpecificScreenMenuItem.image = NSImage(systemSymbolName: "display.2", accessibilityDescription: nil)
        screenSubmenu = NSMenu()
        recordSpecificScreenMenuItem.submenu = screenSubmenu
        menu.addItem(recordSpecificScreenMenuItem)
        
        recordWindowMenuItem = NSMenuItem(title: "Record Window", action: nil, keyEquivalent: "")
        recordWindowMenuItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        windowSubmenu = NSMenu()
        recordWindowMenuItem.submenu = windowSubmenu
        menu.addItem(recordWindowMenuItem)
        
        visualPickerMenuItem = NSMenuItem(title: "Choose Window / Screen... (⌘⌥2)", action: #selector(showVisualPicker), keyEquivalent: "")
        visualPickerMenuItem.target = self
        visualPickerMenuItem.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: nil)
        menu.addItem(visualPickerMenuItem)
        
        startSectionSeparator = NSMenuItem.separator()
        menu.addItem(startSectionSeparator)
        
        micMenuItem = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        micMenuItem.image = NSImage(systemSymbolName: "mic", accessibilityDescription: nil)
        menu.addItem(micMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Persistent library & preference items
        let recentRecordingsItem = NSMenuItem(title: "Recent Recordings...", action: #selector(showRecentRecordings), keyEquivalent: "r")
        recentRecordingsItem.keyEquivalentModifierMask = [.command, .option]
        recentRecordingsItem.target = self
        recentRecordingsItem.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        menu.addItem(recentRecordingsItem)
        
        let openFolderItem = NSMenuItem(title: "Open Recordings Folder", action: #selector(openRecordingsFolder), keyEquivalent: "")
        openFolderItem.target = self
        openFolderItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        menu.addItem(openFolderItem)
        
        autoDeleteToggleItem = NSMenuItem(title: "Auto-Delete Old Recordings (15 Days)", action: #selector(toggleAutoDelete), keyEquivalent: "")
        autoDeleteToggleItem.target = self
        autoDeleteToggleItem.image = NSImage(systemSymbolName: "trash.badge.clock", accessibilityDescription: nil)
        autoDeleteToggleItem.state = RetentionManager.shared.isAutoDeleteEnabled ? .on : .off
        menu.addItem(autoDeleteToggleItem)
        
        autoCopyPathToggleItem = NSMenuItem(title: "Auto-Copy File Location on Stop (for LLMs)", action: #selector(toggleAutoCopyPath), keyEquivalent: "")
        autoCopyPathToggleItem.target = self
        autoCopyPathToggleItem.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
        autoCopyPathToggleItem.state = RetentionManager.shared.isAutoCopyPathEnabled ? .on : .off
        menu.addItem(autoCopyPathToggleItem)
        
        let pruneItem = NSMenuItem(title: "Prune Old Recordings Now", action: #selector(pruneRecordings), keyEquivalent: "")
        pruneItem.target = self
        pruneItem.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: nil)
        menu.addItem(pruneItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)
        
        let welcomeItem = NSMenuItem(title: "Welcome Guide...", action: #selector(showOnboarding), keyEquivalent: "")
        welcomeItem.target = self
        welcomeItem.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        menu.addItem(welcomeItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit Luna", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    public func menuWillOpen(_ menu: NSMenu) {
        refreshDynamicMenus()
    }
    
    private func refreshDynamicMenus() {
        let isRecording = CaptureEngine.shared.isRecording
        let isPaused = CaptureEngine.shared.isPaused
        
        // Dynamic visibility based on recording state:
        // When idle: Pause and Stop are completely hidden!
        activeStatusMenuItem.isHidden = !isRecording
        pauseMenuItem.isHidden = !isRecording
        stopMenuItem.isHidden = !isRecording
        recordingSectionSeparator.isHidden = !isRecording
        
        recordAreaMenuItem.isHidden = isRecording
        recordScreenMenuItem.isHidden = isRecording
        recordSpecificScreenMenuItem.isHidden = isRecording
        recordWindowMenuItem.isHidden = isRecording
        visualPickerMenuItem.isHidden = isRecording
        startSectionSeparator.isHidden = isRecording
        
        autoDeleteToggleItem.state = RetentionManager.shared.isAutoDeleteEnabled ? .on : .off
        autoCopyPathToggleItem.state = RetentionManager.shared.isAutoCopyPathEnabled ? .on : .off
        
        let isMuted = MicrophoneManager.shared.isMuted
        let micName = MicrophoneManager.shared.currentDeviceName
        micMenuItem.title = isMuted ? "Microphone: Muted" : "Microphone: \(micName)"
        micMenuItem.image = NSImage(systemSymbolName: isMuted ? "mic.slash.fill" : "mic.fill", accessibilityDescription: nil)
        micMenuItem.submenu = MicrophoneManager.shared.buildMenu { [weak self] in
            guard let self = self else { return }
            let isMuted = MicrophoneManager.shared.isMuted
            let micName = MicrophoneManager.shared.currentDeviceName
            self.micMenuItem.title = isMuted ? "Microphone: Muted" : "Microphone: \(micName)"
            self.micMenuItem.image = NSImage(systemSymbolName: isMuted ? "mic.slash.fill" : "mic.fill", accessibilityDescription: nil)
        }
        
        if isRecording {
            let mins = recordingSeconds / 60
            let secs = recordingSeconds % 60
            let timeStr = String(format: "%02d:%02d", mins, secs)
            activeStatusMenuItem.title = isPaused ? "⏸ Recording Paused (\(timeStr))" : "🔴 Recording in progress... (\(timeStr))"
            pauseMenuItem.title = isPaused ? "Resume Recording (⌘⌥P)" : "Pause Recording (⌘⌥P)"
            pauseMenuItem.isEnabled = true
            stopMenuItem.isEnabled = true
            return
        }
        
        recordAreaMenuItem.isEnabled = true
        recordScreenMenuItem.isEnabled = true
        recordSpecificScreenMenuItem.isEnabled = true
        recordWindowMenuItem.isEnabled = true
        visualPickerMenuItem.isEnabled = true
        
        Task { @MainActor in
            do {
                let content = try await CaptureEngine.fetchShareableContent()
                
                // Helper to resolve localized display name
                func displayName(for display: SCDisplay) -> String {
                    for screen in NSScreen.screens {
                        let screenNum = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
                        if screenNum == display.displayID {
                            return screen.localizedName
                        }
                    }
                    return "Display \(display.displayID)"
                }
                
                // --- 1. Refresh Screens / Displays ---
                self.screenSubmenu.removeAllItems()
                let displays = content.displays
                let mouseLoc = NSEvent.mouseLocation
                
                // Update top "Record Entire Screen" menu title
                if displays.count == 1, let single = displays.first {
                    let name = displayName(for: single)
                    self.recordScreenMenuItem.title = "Record Entire Screen (\(name)) (⌘⌥3)"
                } else {
                    self.recordScreenMenuItem.title = "Record Entire Screen (Active Display) (⌘⌥3)"
                }
                
                for (index, display) in displays.enumerated() {
                    let name = displayName(for: display)
                    var badges: [String] = []
                    if index == 0 { badges.append("Main") }
                    
                    var isActive = false
                    for screen in NSScreen.screens {
                        let screenNum = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
                        if screenNum == display.displayID && NSMouseInRect(mouseLoc, screen.frame, false) {
                            isActive = true
                            break
                        }
                    }
                    if isActive { badges.append("Active") }
                    
                    let badgeStr = badges.isEmpty ? "" : " [\(badges.joined(separator: ", "))]"
                    let itemTitle = "\(name) (\(display.width) × \(display.height))\(badgeStr)"
                    let item = NSMenuItem(
                        title: itemTitle,
                        action: #selector(self.displaySelected(_:)),
                        keyEquivalent: ""
                    )
                    item.image = NSImage(systemSymbolName: "display", accessibilityDescription: nil)
                    item.representedObject = display
                    item.target = self
                    self.screenSubmenu.addItem(item)
                }
                
                if displays.count > 1 {
                    self.screenSubmenu.addItem(NSMenuItem.separator())
                    let activeItem = NSMenuItem(
                        title: "Record Active Screen (Under Mouse Cursor) (⌘⌥3)",
                        action: #selector(self.startMainScreenRecording),
                        keyEquivalent: ""
                    )
                    activeItem.image = NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: nil)
                    activeItem.target = self
                    self.screenSubmenu.addItem(activeItem)
                }
                
                if displays.isEmpty {
                    let emptyItem = NSMenuItem(title: "No displays detected", action: nil, keyEquivalent: "")
                    emptyItem.isEnabled = false
                    self.screenSubmenu.addItem(emptyItem)
                }
                
                // --- 2. Refresh Windows ---
                self.windowSubmenu.removeAllItems()
                let filteredWindows = content.windows.filter { window in
                    guard let app = window.owningApplication else { return false }
                    guard window.frame.width > 100 && window.frame.height > 100 else { return false }
                    guard app.applicationName != "ScreenRecorder" && app.applicationName != "Luna" else { return false }
                    guard !["Window Server", "Dock", "SystemUIServer", "Control Center"].contains(app.applicationName) else { return false }
                    return true
                }
                
                for window in filteredWindows.prefix(25) {
                    let appName = window.owningApplication?.applicationName ?? "Unknown"
                    let title = (window.title?.isEmpty ?? true) ? "Untitled Window" : (window.title ?? "")
                    let truncatedTitle = title.count > 35 ? "\(title.prefix(32))..." : title
                    
                    let item = NSMenuItem(
                        title: "\(appName): \(truncatedTitle)",
                        action: #selector(self.windowSelected(_:)),
                        keyEquivalent: ""
                    )
                    item.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
                    item.representedObject = window
                    item.target = self
                    self.windowSubmenu.addItem(item)
                }
                
                if filteredWindows.isEmpty {
                    let emptyItem = NSMenuItem(title: "No visible windows found", action: nil, keyEquivalent: "")
                    emptyItem.isEnabled = false
                    self.windowSubmenu.addItem(emptyItem)
                }
            } catch {
                print("[MenuBarController] refreshDynamicMenus content error: \(error)")
                let nsError = error as NSError
                if nsError.code == -3801 || nsError.domain.contains("ScreenCaptureKit") {
                    self.screenSubmenu.removeAllItems()
                    let permItem = NSMenuItem(
                        title: "⚠️ Screen Recording Permission Required...",
                        action: #selector(self.openPermissionSettings),
                        keyEquivalent: ""
                    )
                    permItem.target = self
                    self.screenSubmenu.addItem(permItem)
                }
            }
        }
    }
    
    @objc public func startAreaRecording() {
        guard !CaptureEngine.shared.isRecording else { return }
        OverlayWindowController.shared.startSelection { [weak self] target in
            self?.beginRecording(target: target)
        }
    }
    
    @objc private func displaySelected(_ sender: NSMenuItem) {
        guard let display = sender.representedObject as? SCDisplay else { return }
        beginRecording(target: .display(display))
    }
    
    @objc private func windowSelected(_ sender: NSMenuItem) {
        guard let window = sender.representedObject as? SCWindow else { return }
        beginRecording(target: .window(window))
    }
    
    @objc public func startMainScreenRecording() {
        print("[MenuBarController] startMainScreenRecording entered")
        Task { @MainActor in
            do {
                let content = try await CaptureEngine.fetchShareableContent()
                print("[MenuBarController] Fetched shareable content: \(content.displays.count) displays")
                guard !content.displays.isEmpty else {
                    print("[MenuBarController] No display found in shareable content")
                    self.showErrorAlert(title: "No Display Found", message: "Failed to access any display for recording.")
                    return
                }
                
                // Pick display under mouse cursor, or default to first display
                let mouseLoc = NSEvent.mouseLocation
                var targetDisplay = content.displays.first!
                for screen in NSScreen.screens {
                    if NSMouseInRect(mouseLoc, screen.frame, false) {
                        let screenNum = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
                        if let matched = content.displays.first(where: { $0.displayID == screenNum }) {
                            targetDisplay = matched
                            break
                        }
                    }
                }
                
                print("[MenuBarController] Starting recording on display: \(targetDisplay.displayID)")
                self.beginRecording(target: .display(targetDisplay))
            } catch {
                print("[MenuBarController] Failed to fetch shareable content: \(error)")
                let nsError = error as NSError
                if nsError.code == -3801 || nsError.domain.contains("ScreenCaptureKit") {
                    PermissionManager.shared.showPermissionAlert()
                } else {
                    self.showErrorAlert(title: "Display Capture Error", message: error.localizedDescription)
                }
            }
        }
    }
    
    @objc public func showVisualPicker() {
        guard !CaptureEngine.shared.isRecording else { return }
        if #available(macOS 14.0, *) {
            VisualPickerManager.shared.present { [weak self] filter in
                self?.beginRecording(filter: filter)
            }
        } else {
            showWindowMenu()
        }
    }
    
    public func showWindowMenu() {
        statusItem.button?.performClick(nil)
    }
    
    private func beginRecording(filter: SCContentFilter) {
        let outputURL = RetentionManager.shared.generateOutputFileURL()
        RecordingHUDController.shared.prepareWindow()
        Task { @MainActor in
            do {
                try await CaptureEngine.shared.startCapture(filter: filter, outputURL: outputURL)
                startTimer()
                updateStatusItemIcon(isRecording: true)
                stopMenuItem.isEnabled = true
                pauseMenuItem.isEnabled = true
                
                RecordingHUDController.shared.show(
                    onTogglePause: { [weak self] in
                        self?.togglePause()
                    },
                    onStop: { [weak self] in
                        self?.stopRecording()
                    }
                )
            } catch {
                print("[MenuBarController] Failed to start capture (filter): \(error)")
                let nsError = error as NSError
                if nsError.code == -3801 || nsError.domain.contains("ScreenCaptureKit") {
                    PermissionManager.shared.showPermissionAlert()
                } else {
                    self.showErrorAlert(title: "Failed to Start Recording", message: error.localizedDescription)
                }
            }
        }
    }
    
    private func beginRecording(target: CaptureTarget) {
        let outputURL = RetentionManager.shared.generateOutputFileURL()
        RecordingHUDController.shared.prepareWindow()
        Task { @MainActor in
            do {
                try await CaptureEngine.shared.startCapture(target: target, outputURL: outputURL)
                startTimer()
                updateStatusItemIcon(isRecording: true)
                stopMenuItem.isEnabled = true
                pauseMenuItem.isEnabled = true
                
                // Show floating translucent HUD with Pause & Stop
                RecordingHUDController.shared.show(
                    onTogglePause: { [weak self] in
                        self?.togglePause()
                    },
                    onStop: { [weak self] in
                        self?.stopRecording()
                    }
                )
            } catch {
                print("[MenuBarController] Failed to start capture (target): \(error)")
                let nsError = error as NSError
                if nsError.code == -3801 || nsError.domain.contains("ScreenCaptureKit") {
                    PermissionManager.shared.showPermissionAlert()
                } else {
                    self.showErrorAlert(title: "Failed to Start Recording", message: error.localizedDescription)
                }
            }
        }
    }
    
    @objc public func togglePause() {
        guard CaptureEngine.shared.isRecording else { return }
        if CaptureEngine.shared.isPaused {
            CaptureEngine.shared.resumeCapture()
        } else {
            CaptureEngine.shared.pauseCapture()
        }
        
        let isPaused = CaptureEngine.shared.isPaused
        RecordingHUDController.shared.updateTimer(seconds: recordingSeconds, isPaused: isPaused)
        
        let mins = recordingSeconds / 60
        let secs = recordingSeconds % 60
        let icon = isPaused ? "⏸" : "🔴"
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        statusItem.button?.title = String(format: "%@ %02d:%02d", icon, mins, secs)
    }
    
    @objc public func stopRecording() {
        guard CaptureEngine.shared.isRecording else { return }
        
        stopTimer()
        RecordingHUDController.shared.hide()
        updateStatusItemIcon(isRecording: false)
        stopMenuItem.isEnabled = false
        pauseMenuItem.isEnabled = false
        
        Task { @MainActor in
            do {
                let outputURL = try await CaptureEngine.shared.stopCapture()
                
                // Copy file path and action prompt directly to clipboard if enabled (ideal for LLMs & AI coding agents)
                if RetentionManager.shared.isAutoCopyPathEnabled {
                    PasteboardManager.shared.copyAIPromptToPasteboard(fileURL: outputURL)
                    ToastHUDController.shared.show(
                        title: "Recording + Actions Copied",
                        message: "Ready to paste (⌘V) into your LLM",
                        fileURL: outputURL
                    )
                } else {
                    ToastHUDController.shared.show(
                        title: "Recording Saved",
                        message: "Saved to your library",
                        fileURL: outputURL
                    )
                }
                
                // Prune old recordings (15 days if enabled)
                RetentionManager.shared.pruneOldRecordings()
                
                // Send system notification
                let sizeStr = RetentionManager.formattedFileSize(for: outputURL)
                showSuccessNotification(filename: outputURL.lastPathComponent, size: sizeStr)
            } catch {
                showErrorNotification(message: "Failed to save recording: \(error.localizedDescription)")
            }
        }
    }
    
    private func startTimer() {
        recordingSeconds = 0
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if !CaptureEngine.shared.isPaused {
                self.recordingSeconds += 1
            }
            let mins = self.recordingSeconds / 60
            let secs = self.recordingSeconds % 60
            let icon = CaptureEngine.shared.isPaused ? "⏸" : "🔴"
            let timeStr = String(format: "%@ %02d:%02d", icon, mins, secs)
            DispatchQueue.main.async {
                self.statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
                self.statusItem.button?.title = timeStr
                RecordingHUDController.shared.updateTimer(seconds: self.recordingSeconds, isPaused: CaptureEngine.shared.isPaused)
                if CaptureEngine.shared.isRecording {
                    self.activeStatusMenuItem.title = CaptureEngine.shared.isPaused ? "⏸ Recording Paused (\(String(format: "%02d:%02d", mins, secs)))" : "🔴 Recording in progress... (\(String(format: "%02d:%02d", mins, secs)))"
                }
            }
        }
    }
    
    private func stopTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingSeconds = 0
    }
    
    @objc private func showRecentRecordings() {
        RecordingsWindowController.shared.show()
    }
    
    @objc private func openRecordingsFolder() {
        let folder = RetentionManager.shared.recordingsDirectory
        NSWorkspace.shared.open(folder)
    }
    
    @objc private func toggleAutoDelete() {
        RetentionManager.shared.isAutoDeleteEnabled.toggle()
        autoDeleteToggleItem.state = RetentionManager.shared.isAutoDeleteEnabled ? .on : .off
    }
    
    @objc private func toggleAutoCopyPath() {
        RetentionManager.shared.isAutoCopyPathEnabled.toggle()
        autoCopyPathToggleItem.state = RetentionManager.shared.isAutoCopyPathEnabled ? .on : .off
    }
    
    @objc private func showSettings() {
        SettingsWindowController.shared.show()
    }
    
    @objc private func showOnboarding() {
        OnboardingWindowController.shared.show()
    }
    
    @objc private func pruneRecordings() {
        let count = RetentionManager.shared.pruneOldRecordings()
        let alert = NSAlert()
        alert.messageText = "Auto-Delete Maintenance"
        alert.informativeText = count > 0
            ? "Successfully cleaned up \(count) recording(s) older than 15 days."
            : "No recordings older than 15 days found."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    @objc private func quitApp() {
        if CaptureEngine.shared.isRecording {
            Task { @MainActor in
                _ = try? await CaptureEngine.shared.stopCapture()
                NSApp.terminate(nil)
            }
        } else {
            NSApp.terminate(nil)
        }
    }
    
    private func showSuccessNotification(filename: String, size: String) {
        let content = UNMutableNotificationContent()
        content.title = "Luna 🌙: Recording URL Copied!"
        content.subtitle = "\(filename) (\(size))"
        if RetentionManager.shared.isAutoCopyPathEnabled {
            content.body = "Recording URL is now in your clipboard and ready to be pasted (⌘V)."
        } else {
            content.body = "Recording saved to your library."
        }
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().add(request)
        }
    }
    
    @objc public func openPermissionSettings() {
        PermissionManager.openScreenRecordingSettings()
    }
    
    public func showErrorAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let nsStr = message as NSString
            if nsStr.contains("-3801") || nsStr.contains("declined TCC") {
                PermissionManager.shared.showPermissionAlert()
                return
            }
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
    
    private func showErrorNotification(message: String) {
        showErrorAlert(title: "Recording Error", message: message)
    }
}
