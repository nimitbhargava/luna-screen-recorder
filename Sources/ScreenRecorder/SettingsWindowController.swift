import AppKit

public final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    public static let shared = SettingsWindowController()
    
    private var copyPathSwitch: NSSwitch!
    private var autoDeleteSwitch: NSSwitch!
    
    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 530),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Luna Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func show() {
        OnboardingWindowController.shared.window?.orderOut(nil)
        
        copyPathSwitch?.state = RetentionManager.shared.isAutoCopyPathEnabled ? .on : .off
        autoDeleteSwitch?.state = RetentionManager.shared.isAutoDeleteEnabled ? .on : .off
        
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func setupUI() {
        guard let window = self.window else { return }
        let root = NSView(frame: window.contentView!.bounds)
        root.autoresizingMask = [.width, .height]
        
        var currentY: CGFloat = root.frame.height - 20
        let leftMargin: CGFloat = 28
        let boxWidth: CGFloat = root.frame.width - (leftMargin * 2) // 504
        let innerPadding: CGFloat = 20
        
        // --- 1. AI & LLM WORKFLOW SECTION ---
        let aiHeader = NSTextField(labelWithString: "AI & LLM WORKFLOW")
        aiHeader.frame = NSRect(x: leftMargin, y: currentY - 18, width: boxWidth, height: 16)
        aiHeader.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        aiHeader.textColor = .secondaryLabelColor
        root.addSubview(aiHeader)
        currentY -= 26
        
        let aiBoxHeight: CGFloat = 96
        let aiBox = NSBox(frame: NSRect(x: leftMargin, y: currentY - aiBoxHeight, width: boxWidth, height: aiBoxHeight))
        aiBox.boxType = .custom
        aiBox.cornerRadius = 10
        aiBox.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6)
        aiBox.borderColor = NSColor.separatorColor.withAlphaComponent(0.35)
        aiBox.borderWidth = 1.0
        
        let aiIcon = NSImageView(frame: NSRect(x: innerPadding, y: 56, width: 24, height: 24))
        aiIcon.image = NSImage(systemSymbolName: "link.circle.fill", accessibilityDescription: nil)
        aiIcon.contentTintColor = .controlAccentColor
        aiBox.addSubview(aiIcon)
        
        let aiTitle = NSTextField(labelWithString: "Auto-Copy File Location on Stop")
        aiTitle.frame = NSRect(x: innerPadding + 34, y: 58, width: boxWidth - innerPadding * 2 - 80, height: 20)
        aiTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        aiBox.addSubview(aiTitle)
        
        copyPathSwitch = NSSwitch(frame: NSRect(x: boxWidth - 54 - innerPadding, y: 56, width: 54, height: 24))
        copyPathSwitch.state = RetentionManager.shared.isAutoCopyPathEnabled ? .on : .off
        copyPathSwitch.target = self
        copyPathSwitch.action = #selector(copyPathToggled)
        aiBox.addSubview(copyPathSwitch)
        
        let aiDesc = NSTextField(wrappingLabelWithString: "Copies local file path to clipboard on stop. Simply press ⌘V in Antigravity, Claude, ChatGPT, or Gemini for instant analysis.")
        aiDesc.frame = NSRect(x: innerPadding + 34, y: 10, width: boxWidth - innerPadding * 2 - 34, height: 42)
        aiDesc.font = NSFont.systemFont(ofSize: 11.5)
        aiDesc.textColor = .secondaryLabelColor
        aiBox.addSubview(aiDesc)
        
        root.addSubview(aiBox)
        currentY -= (aiBoxHeight + 18)
        
        // --- 2. STORAGE & RETENTION SECTION ---
        let storageHeader = NSTextField(labelWithString: "STORAGE & RETENTION")
        storageHeader.frame = NSRect(x: leftMargin, y: currentY - 18, width: boxWidth, height: 16)
        storageHeader.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        storageHeader.textColor = .secondaryLabelColor
        root.addSubview(storageHeader)
        currentY -= 26
        
        let storageBoxHeight: CGFloat = 140
        let storageBox = NSBox(frame: NSRect(x: leftMargin, y: currentY - storageBoxHeight, width: boxWidth, height: storageBoxHeight))
        storageBox.boxType = .custom
        storageBox.cornerRadius = 10
        storageBox.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6)
        storageBox.borderColor = NSColor.separatorColor.withAlphaComponent(0.35)
        storageBox.borderWidth = 1.0
        
        let storageIcon = NSImageView(frame: NSRect(x: innerPadding, y: 100, width: 24, height: 24))
        storageIcon.image = NSImage(systemSymbolName: "trash.circle.fill", accessibilityDescription: nil)
        storageIcon.contentTintColor = .systemOrange
        storageBox.addSubview(storageIcon)
        
        let storageTitle = NSTextField(labelWithString: "15-Day Auto-Delete Old Recordings")
        storageTitle.frame = NSRect(x: innerPadding + 34, y: 102, width: boxWidth - innerPadding * 2 - 80, height: 20)
        storageTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        storageBox.addSubview(storageTitle)
        
        autoDeleteSwitch = NSSwitch(frame: NSRect(x: boxWidth - 54 - innerPadding, y: 100, width: 54, height: 24))
        autoDeleteSwitch.state = RetentionManager.shared.isAutoDeleteEnabled ? .on : .off
        autoDeleteSwitch.target = self
        autoDeleteSwitch.action = #selector(autoDeleteToggled)
        storageBox.addSubview(autoDeleteSwitch)
        
        let storageDesc = NSTextField(wrappingLabelWithString: "Automatically deletes recordings older than 15 days to save disk space. Perfect for temporary AI bug demo recordings.")
        storageDesc.frame = NSRect(x: innerPadding + 34, y: 56, width: boxWidth - innerPadding * 2 - 34, height: 40)
        storageDesc.font = NSFont.systemFont(ofSize: 11.5)
        storageDesc.textColor = .secondaryLabelColor
        storageBox.addSubview(storageDesc)
        
        // Inner divider
        let div = NSBox(frame: NSRect(x: innerPadding, y: 46, width: boxWidth - innerPadding * 2, height: 1))
        div.boxType = .separator
        storageBox.addSubview(div)
        
        // Action Buttons Row
        let openFolderBtn = NSButton(frame: NSRect(x: innerPadding, y: 10, width: 175, height: 28))
        openFolderBtn.title = "Open Folder in Finder"
        openFolderBtn.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        openFolderBtn.imagePosition = .imageLeading
        openFolderBtn.bezelStyle = .rounded
        openFolderBtn.font = NSFont.systemFont(ofSize: 11.5)
        openFolderBtn.target = self
        openFolderBtn.action = #selector(openFolderClicked)
        storageBox.addSubview(openFolderBtn)
        
        let pruneBtn = NSButton(frame: NSRect(x: innerPadding + 184, y: 10, width: 160, height: 28))
        pruneBtn.title = "Prune Old Files Now"
        pruneBtn.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: nil)
        pruneBtn.imagePosition = .imageLeading
        pruneBtn.bezelStyle = .rounded
        pruneBtn.font = NSFont.systemFont(ofSize: 11.5)
        pruneBtn.target = self
        pruneBtn.action = #selector(pruneClicked)
        storageBox.addSubview(pruneBtn)
        
        root.addSubview(storageBox)
        currentY -= (storageBoxHeight + 18)
        
        // --- 3. KEYBOARD SHORTCUTS SECTION ---
        let hotkeyHeader = NSTextField(labelWithString: "GLOBAL KEYBOARD SHORTCUTS")
        hotkeyHeader.frame = NSRect(x: leftMargin, y: currentY - 18, width: boxWidth, height: 16)
        hotkeyHeader.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        hotkeyHeader.textColor = .secondaryLabelColor
        root.addSubview(hotkeyHeader)
        currentY -= 26
        
        let hotkeyBoxHeight: CGFloat = 116
        let hotkeyBox = NSBox(frame: NSRect(x: leftMargin, y: currentY - hotkeyBoxHeight, width: boxWidth, height: hotkeyBoxHeight))
        hotkeyBox.boxType = .custom
        hotkeyBox.cornerRadius = 10
        hotkeyBox.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6)
        hotkeyBox.borderColor = NSColor.separatorColor.withAlphaComponent(0.35)
        hotkeyBox.borderWidth = 1.0
        
        let shortcuts: [(String, String)] = [
            ("⌘⌥1", "Record Area Crop (or click screen for full display)"),
            ("⌘⌥2", "Choose Window or Display"),
            ("⌘⌥3", "Record Active Screen / Entire Display"),
            ("⌘⌥S", "Stop Recording (or click floating HUD)")
        ]
        
        for (i, item) in shortcuts.enumerated() {
            let rowY = CGFloat(86 - i * 26)
            let badge = NSTextField(labelWithString: " \(item.0) ")
            badge.frame = NSRect(x: innerPadding, y: rowY, width: 50, height: 20)
            badge.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .bold)
            badge.textColor = .labelColor
            badge.wantsLayer = true
            badge.layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.2).cgColor
            badge.layer?.cornerRadius = 4
            badge.layer?.masksToBounds = true
            hotkeyBox.addSubview(badge)
            
            let label = NSTextField(labelWithString: item.1)
            label.frame = NSRect(x: innerPadding + 58, y: rowY + 1, width: boxWidth - innerPadding * 2 - 58, height: 18)
            label.font = NSFont.systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            hotkeyBox.addSubview(label)
        }
        
        root.addSubview(hotkeyBox)
        
        window.contentView = root
    }
    
    @objc private func copyPathToggled() {
        RetentionManager.shared.isAutoCopyPathEnabled = (copyPathSwitch.state == .on)
    }
    
    @objc private func autoDeleteToggled() {
        RetentionManager.shared.isAutoDeleteEnabled = (autoDeleteSwitch.state == .on)
    }
    
    @objc private func openFolderClicked() {
        NSWorkspace.shared.open(RetentionManager.shared.recordingsDirectory)
    }
    
    @objc private func pruneClicked() {
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
}
