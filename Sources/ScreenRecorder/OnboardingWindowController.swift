import AppKit

public final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    public static let shared = OnboardingWindowController()
    
    private var copyPathSwitch: NSSwitch!
    private var autoDeleteSwitch: NSSwitch!
    
    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 580),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Luna"
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
        
        // --- 1. HEADER: Mascot & Welcome Titles ---
        let mascotSize: CGFloat = 80
        let mascotImageView = NSImageView(frame: NSRect(x: (root.frame.width - mascotSize) / 2, y: root.frame.height - 105, width: mascotSize, height: mascotSize))
        mascotImageView.imageScaling = .scaleProportionallyUpOrDown
        if let mascotImg = loadMascotImage() {
            mascotImageView.image = mascotImg
        }
        root.addSubview(mascotImageView)
        
        let titleLabel = NSTextField(labelWithString: "Welcome to Luna")
        titleLabel.frame = NSRect(x: 20, y: root.frame.height - 140, width: root.frame.width - 40, height: 28)
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.alignment = .center
        root.addSubview(titleLabel)
        
        let subtitleLabel = NSTextField(labelWithString: "Lightweight, crisp screen recording tailored for AI coding workflows.")
        subtitleLabel.frame = NSRect(x: 30, y: root.frame.height - 166, width: root.frame.width - 60, height: 20)
        subtitleLabel.font = NSFont.systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center
        root.addSubview(subtitleLabel)
        
        // --- 2. APPLE-STYLE INSET GROUPED SETTINGS ---
        let sectionHeader = NSTextField(labelWithString: "DEFAULT WORKFLOW SETTINGS")
        sectionHeader.frame = NSRect(x: 38, y: root.frame.height - 200, width: root.frame.width - 76, height: 16)
        sectionHeader.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        sectionHeader.textColor = .secondaryLabelColor
        root.addSubview(sectionHeader)
        
        let cardWidth = root.frame.width - 72
        let groupContainer = NSBox(frame: NSRect(x: 36, y: root.frame.height - 430, width: cardWidth, height: 224))
        groupContainer.boxType = .custom
        groupContainer.cornerRadius = 12
        groupContainer.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.65)
        groupContainer.borderColor = NSColor.separatorColor.withAlphaComponent(0.35)
        groupContainer.borderWidth = 1.0
        
        // ROW 1: Auto-Copy Path for LLMs
        let row1Y: CGFloat = 120
        let icon1 = NSImageView(frame: NSRect(x: 16, y: row1Y + 54, width: 24, height: 24))
        icon1.image = NSImage(systemSymbolName: "link.circle.fill", accessibilityDescription: nil)
        icon1.contentTintColor = .controlAccentColor
        groupContainer.addSubview(icon1)
        
        let title1 = NSTextField(labelWithString: "Auto-Copy File Location on Stop")
        title1.frame = NSRect(x: 48, y: row1Y + 56, width: 220, height: 18)
        title1.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        groupContainer.addSubview(title1)
        
        let badge1 = createBadge(text: "RECOMMENDED FOR LLMs", color: .controlAccentColor)
        badge1.frame = NSRect(x: 272, y: row1Y + 57, width: 140, height: 16)
        groupContainer.addSubview(badge1)
        
        copyPathSwitch = NSSwitch(frame: NSRect(x: cardWidth - 54, y: row1Y + 52, width: 40, height: 24))
        copyPathSwitch.state = RetentionManager.shared.isAutoCopyPathEnabled ? .on : .off
        copyPathSwitch.target = self
        copyPathSwitch.action = #selector(copyPathSwitchToggled)
        groupContainer.addSubview(copyPathSwitch)
        
        let desc1 = NSTextField(wrappingLabelWithString: "Automatically copies the local file path to your clipboard when recording stops. Simply press ⌘V in Antigravity, Claude, ChatGPT, or Gemini for instant analysis.")
        desc1.frame = NSRect(x: 48, y: row1Y + 4, width: cardWidth - 105, height: 46)
        desc1.font = NSFont.systemFont(ofSize: 11.5)
        desc1.textColor = .secondaryLabelColor
        groupContainer.addSubview(desc1)
        
        // Divider
        let divider = NSBox(frame: NSRect(x: 16, y: 112, width: cardWidth - 32, height: 1))
        divider.boxType = .separator
        groupContainer.addSubview(divider)
        
        // ROW 2: 15-Day Auto-Delete
        let row2Y: CGFloat = 8
        let icon2 = NSImageView(frame: NSRect(x: 16, y: row2Y + 56, width: 24, height: 24))
        icon2.image = NSImage(systemSymbolName: "trash.circle.fill", accessibilityDescription: nil)
        icon2.contentTintColor = .systemOrange
        groupContainer.addSubview(icon2)
        
        let title2 = NSTextField(labelWithString: "15-Day Auto-Delete Old Recordings")
        title2.frame = NSRect(x: 48, y: row2Y + 58, width: 236, height: 18)
        title2.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        groupContainer.addSubview(title2)
        
        let badge2 = createBadge(text: "RECOMMENDED", color: .systemOrange)
        badge2.frame = NSRect(x: 288, y: row2Y + 59, width: 94, height: 16)
        groupContainer.addSubview(badge2)
        
        autoDeleteSwitch = NSSwitch(frame: NSRect(x: cardWidth - 54, y: row2Y + 54, width: 40, height: 24))
        autoDeleteSwitch.state = RetentionManager.shared.isAutoDeleteEnabled ? .on : .off
        autoDeleteSwitch.target = self
        autoDeleteSwitch.action = #selector(autoDeleteSwitchToggled)
        groupContainer.addSubview(autoDeleteSwitch)
        
        let desc2 = NSTextField(wrappingLabelWithString: "Automatically removes recordings older than 15 days to keep your disk clean. Perfect for temporary AI bug demos. Can be turned off anytime.")
        desc2.frame = NSRect(x: 48, y: row2Y + 6, width: cardWidth - 105, height: 46)
        desc2.font = NSFont.systemFont(ofSize: 11.5)
        desc2.textColor = .secondaryLabelColor
        groupContainer.addSubview(desc2)
        
        root.addSubview(groupContainer)
        
        // --- 3. SHORTCUTS & HINT ---
        let shortcutsLbl = NSTextField(labelWithString: "Shortcuts:   ⌘⌥1 Area Crop   •   ⌘⌥2 Window   •   ⌘⌥3 Display   •   ⌘⌥S Stop")
        shortcutsLbl.frame = NSRect(x: 20, y: 78, width: root.frame.width - 40, height: 18)
        shortcutsLbl.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        shortcutsLbl.textColor = .tertiaryLabelColor
        shortcutsLbl.alignment = .center
        root.addSubview(shortcutsLbl)
        
        let settingsHint = NSTextField(labelWithString: "You can change these anytime in Menu Bar > Settings... (⌘,)")
        settingsHint.frame = NSRect(x: 20, y: 58, width: root.frame.width - 40, height: 16)
        settingsHint.font = NSFont.systemFont(ofSize: 10.5)
        settingsHint.textColor = .tertiaryLabelColor
        settingsHint.alignment = .center
        root.addSubview(settingsHint)
        
        // --- 4. GET STARTED BUTTON ---
        let getStartedBtn = NSButton(frame: NSRect(x: (root.frame.width - 200) / 2, y: 16, width: 200, height: 34))
        getStartedBtn.title = "Get Started"
        getStartedBtn.image = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)
        getStartedBtn.imagePosition = .imageTrailing
        getStartedBtn.bezelStyle = .rounded
        getStartedBtn.bezelColor = .controlAccentColor
        getStartedBtn.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        getStartedBtn.keyEquivalent = "\r"
        getStartedBtn.target = self
        getStartedBtn.action = #selector(getStartedClicked)
        root.addSubview(getStartedBtn)
        
        window.contentView = root
    }
    
    private func createBadge(text: String, color: NSColor) -> NSTextField {
        let badge = NSTextField(labelWithString: " \(text) ")
        badge.font = NSFont.systemFont(ofSize: 9, weight: .bold)
        badge.textColor = color
        badge.wantsLayer = true
        badge.layer?.backgroundColor = color.withAlphaComponent(0.16).cgColor
        badge.layer?.cornerRadius = 4
        badge.layer?.masksToBounds = true
        badge.alignment = .center
        return badge
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
    
    @objc private func copyPathSwitchToggled() {
        RetentionManager.shared.isAutoCopyPathEnabled = (copyPathSwitch.state == .on)
    }
    
    @objc private func autoDeleteSwitchToggled() {
        RetentionManager.shared.isAutoDeleteEnabled = (autoDeleteSwitch.state == .on)
    }
    
    @objc private func getStartedClicked() {
        RetentionManager.shared.isAutoCopyPathEnabled = (copyPathSwitch.state == .on)
        RetentionManager.shared.isAutoDeleteEnabled = (autoDeleteSwitch.state == .on)
        RetentionManager.shared.hasCompletedOnboarding = true
        window?.orderOut(nil)
        print("[Onboarding] Finished. AutoCopy: \(RetentionManager.shared.isAutoCopyPathEnabled), AutoDelete: \(RetentionManager.shared.isAutoDeleteEnabled)")
    }
}
