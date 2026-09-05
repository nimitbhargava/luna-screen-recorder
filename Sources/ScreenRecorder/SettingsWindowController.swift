import AppKit

public final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    public static let shared = SettingsWindowController()
    
    private var copyPathSwitch: NSSwitch!
    private var autoDeleteSwitch: NSSwitch!
    
    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 530),
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
        let contentWidth = root.frame.width - 56
        let leftMargin: CGFloat = 28
        
        let blueAccent = NSColor(srgbRed: 0.38, green: 0.72, blue: 1.0, alpha: 1.0)
        let orangeAccent = NSColor(srgbRed: 1.0, green: 0.65, blue: 0.3, alpha: 1.0)
        
        // --- 1. AI & LLM WORKFLOW SECTION ---
        let aiHeader = NSTextField(labelWithString: "AI & LLM WORKFLOW")
        aiHeader.frame = NSRect(x: leftMargin, y: currentY - 18, width: contentWidth, height: 16)
        aiHeader.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        aiHeader.textColor = .secondaryLabelColor
        root.addSubview(aiHeader)
        currentY -= 26
        
        let aiBox = NSBox(frame: NSRect(x: leftMargin, y: currentY - 96, width: contentWidth, height: 96))
        aiBox.boxType = .custom
        aiBox.cornerRadius = 10
        aiBox.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6)
        aiBox.borderColor = NSColor.separatorColor.withAlphaComponent(0.35)
        aiBox.borderWidth = 1.0
        
        let aiIcon = NSImageView(frame: NSRect(x: 14, y: aiBox.frame.height - 34, width: 22, height: 22))
        aiIcon.image = NSImage(systemSymbolName: "link.circle.fill", accessibilityDescription: nil)
        aiIcon.contentTintColor = .controlAccentColor
        aiBox.addSubview(aiIcon)
        
        let aiTitle = NSTextField(labelWithString: "Auto-Copy File Location on Stop")
        aiTitle.frame = NSRect(x: 44, y: aiBox.frame.height - 32, width: 220, height: 18)
        aiTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        aiBox.addSubview(aiTitle)
        
        let aiBadge = createBadge(text: "RECOMMENDED FOR LLMs", color: blueAccent)
        aiBadge.frame = NSRect(x: 268, y: aiBox.frame.height - 31, width: 142, height: 16)
        aiBox.addSubview(aiBadge)
        
        copyPathSwitch = NSSwitch(frame: NSRect(x: aiBox.frame.width - 52, y: aiBox.frame.height - 35, width: 40, height: 22))
        copyPathSwitch.state = RetentionManager.shared.isAutoCopyPathEnabled ? .on : .off
        copyPathSwitch.target = self
        copyPathSwitch.action = #selector(copyPathToggled)
        aiBox.addSubview(copyPathSwitch)
        
        let aiDesc = NSTextField(wrappingLabelWithString: "Automatically copies the local file path to clipboard on stop. Simply press ⌘V in Antigravity, Claude, ChatGPT, or Gemini for instant analysis.")
        aiDesc.frame = NSRect(x: 44, y: 10, width: aiBox.frame.width - 60, height: 48)
        aiDesc.font = NSFont.systemFont(ofSize: 11.5)
        aiDesc.textColor = .secondaryLabelColor
        aiBox.addSubview(aiDesc)
        
        root.addSubview(aiBox)
        currentY -= 112
        
        // --- 2. STORAGE & RETENTION SECTION ---
        let storageHeader = NSTextField(labelWithString: "STORAGE & RETENTION")
        storageHeader.frame = NSRect(x: leftMargin, y: currentY - 18, width: contentWidth, height: 16)
        storageHeader.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        storageHeader.textColor = .secondaryLabelColor
        root.addSubview(storageHeader)
        currentY -= 26
        
        let storageBox = NSBox(frame: NSRect(x: leftMargin, y: currentY - 138, width: contentWidth, height: 138))
        storageBox.boxType = .custom
        storageBox.cornerRadius = 10
        storageBox.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6)
        storageBox.borderColor = NSColor.separatorColor.withAlphaComponent(0.35)
        storageBox.borderWidth = 1.0
        
        let storageIcon = NSImageView(frame: NSRect(x: 14, y: storageBox.frame.height - 34, width: 22, height: 22))
        storageIcon.image = NSImage(systemSymbolName: "trash.circle.fill", accessibilityDescription: nil)
        storageIcon.contentTintColor = .systemOrange
        storageBox.addSubview(storageIcon)
        
        let storageTitle = NSTextField(labelWithString: "15-Day Auto-Delete Old Recordings")
        storageTitle.frame = NSRect(x: 44, y: storageBox.frame.height - 32, width: 236, height: 18)
        storageTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        storageBox.addSubview(storageTitle)
        
        let storageBadge = createBadge(text: "RECOMMENDED", color: orangeAccent)
        storageBadge.frame = NSRect(x: 284, y: storageBox.frame.height - 31, width: 94, height: 16)
        storageBox.addSubview(storageBadge)
        
        autoDeleteSwitch = NSSwitch(frame: NSRect(x: storageBox.frame.width - 52, y: storageBox.frame.height - 35, width: 40, height: 22))
        autoDeleteSwitch.state = RetentionManager.shared.isAutoDeleteEnabled ? .on : .off
        autoDeleteSwitch.target = self
        autoDeleteSwitch.action = #selector(autoDeleteToggled)
        storageBox.addSubview(autoDeleteSwitch)
        
        let storageDesc = NSTextField(wrappingLabelWithString: "Automatically deletes recordings older than 15 days to save disk space. Perfect for temporary AI bug demo recordings.")
        storageDesc.frame = NSRect(x: 44, y: 52, width: storageBox.frame.width - 60, height: 44)
        storageDesc.font = NSFont.systemFont(ofSize: 11.5)
        storageDesc.textColor = .secondaryLabelColor
        storageBox.addSubview(storageDesc)
        
        // Inner divider
        let div = NSBox(frame: NSRect(x: 14, y: 44, width: storageBox.frame.width - 28, height: 1))
        div.boxType = .separator
        storageBox.addSubview(div)
        
        // Action Buttons Row
        let openFolderBtn = NSButton(frame: NSRect(x: 14, y: 8, width: 175, height: 28))
        openFolderBtn.title = "Open Folder in Finder"
        openFolderBtn.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        openFolderBtn.imagePosition = .imageLeading
        openFolderBtn.bezelStyle = .rounded
        openFolderBtn.font = NSFont.systemFont(ofSize: 11.5)
        openFolderBtn.target = self
        openFolderBtn.action = #selector(openFolderClicked)
        storageBox.addSubview(openFolderBtn)
        
        let pruneBtn = NSButton(frame: NSRect(x: 198, y: 8, width: 155, height: 28))
        pruneBtn.title = "Prune Old Files Now"
        pruneBtn.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: nil)
        pruneBtn.imagePosition = .imageLeading
        pruneBtn.bezelStyle = .rounded
        pruneBtn.font = NSFont.systemFont(ofSize: 11.5)
        pruneBtn.target = self
        pruneBtn.action = #selector(pruneClicked)
        storageBox.addSubview(pruneBtn)
        
        root.addSubview(storageBox)
        currentY -= 154
        
        // --- 3. KEYBOARD SHORTCUTS SECTION ---
        let hotkeyHeader = NSTextField(labelWithString: "GLOBAL KEYBOARD SHORTCUTS")
        hotkeyHeader.frame = NSRect(x: leftMargin, y: currentY - 18, width: contentWidth, height: 16)
        hotkeyHeader.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        hotkeyHeader.textColor = .secondaryLabelColor
        root.addSubview(hotkeyHeader)
        currentY -= 26
        
        let hotkeyBox = NSBox(frame: NSRect(x: leftMargin, y: currentY - 108, width: contentWidth, height: 108))
        hotkeyBox.boxType = .custom
        hotkeyBox.cornerRadius = 10
        hotkeyBox.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6)
        hotkeyBox.borderColor = NSColor.separatorColor.withAlphaComponent(0.35)
        hotkeyBox.borderWidth = 1.0
        
        let shortcuts: [(String, String)] = [
            ("⌘⌥1", "Record Area Crop (drag to select)"),
            ("⌘⌥2", "Choose Window or Display"),
            ("⌘⌥3", "Record Entire Display"),
            ("⌘⌥S", "Stop Recording (or click floating HUD)")
        ]
        
        for (i, item) in shortcuts.enumerated() {
            let rowY = CGFloat(80 - i * 24)
            let badge = NSTextField(labelWithString: " \(item.0) ")
            badge.frame = NSRect(x: 16, y: rowY, width: 48, height: 18)
            badge.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
            badge.textColor = .labelColor
            badge.wantsLayer = true
            badge.layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.2).cgColor
            badge.layer?.cornerRadius = 4
            badge.layer?.masksToBounds = true
            hotkeyBox.addSubview(badge)
            
            let label = NSTextField(labelWithString: item.1)
            label.frame = NSRect(x: 72, y: rowY, width: hotkeyBox.frame.width - 80, height: 18)
            label.font = NSFont.systemFont(ofSize: 11.5)
            label.textColor = .secondaryLabelColor
            hotkeyBox.addSubview(label)
        }
        
        root.addSubview(hotkeyBox)
        
        window.contentView = root
    }
    
    private func createBadge(text: String, color: NSColor) -> NSTextField {
        let badge = NSTextField(labelWithString: " \(text) ")
        badge.font = NSFont.systemFont(ofSize: 8.5, weight: .bold)
        badge.textColor = color
        badge.wantsLayer = true
        badge.layer?.backgroundColor = color.withAlphaComponent(0.18).cgColor
        badge.layer?.borderColor = color.withAlphaComponent(0.35).cgColor
        badge.layer?.borderWidth = 0.5
        badge.layer?.cornerRadius = 3.5
        badge.layer?.masksToBounds = true
        badge.alignment = .center
        return badge
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
