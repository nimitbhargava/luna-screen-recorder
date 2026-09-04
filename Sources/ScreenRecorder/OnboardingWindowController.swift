import AppKit

public final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    public static let shared = OnboardingWindowController()
    
    private var card1: NSBox!
    private var card2: NSBox!
    private var autoDeleteRadio: NSButton!
    private var keepForeverRadio: NSButton!
    
    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 650),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Luna 🌙"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func show() {
        let isAutoDelete = RetentionManager.shared.isAutoDeleteEnabled
        autoDeleteRadio?.state = isAutoDelete ? .on : .off
        keepForeverRadio?.state = isAutoDelete ? .off : .on
        updateCardStyles()
        
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func setupUI() {
        guard let window = self.window else { return }
        let root = NSView(frame: window.contentView!.bounds)
        root.autoresizingMask = [.width, .height]
        
        // --- 1. HEADER: Mascot & Welcome Titles ---
        let mascotSize: CGFloat = 88
        let mascotImageView = NSImageView(frame: NSRect(x: (root.frame.width - mascotSize) / 2, y: root.frame.height - 115, width: mascotSize, height: mascotSize))
        mascotImageView.imageScaling = .scaleProportionallyUpOrDown
        if let mascotImg = loadMascotImage() {
            mascotImageView.image = mascotImg
        }
        root.addSubview(mascotImageView)
        
        let titleLabel = NSTextField(labelWithString: "Welcome to Luna")
        titleLabel.frame = NSRect(x: 20, y: root.frame.height - 150, width: root.frame.width - 40, height: 28)
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.alignment = .center
        root.addSubview(titleLabel)
        
        let subtitleLabel = NSTextField(labelWithString: "Crisp, lightweight screen recording tailored for AI coding workflows.")
        subtitleLabel.frame = NSRect(x: 30, y: root.frame.height - 176, width: root.frame.width - 60, height: 20)
        subtitleLabel.font = NSFont.systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center
        root.addSubview(subtitleLabel)
        
        // Section Header
        let prefSectionHeader = NSTextField(labelWithString: "STORAGE & RETENTION")
        prefSectionHeader.frame = NSRect(x: 38, y: root.frame.height - 212, width: root.frame.width - 76, height: 16)
        prefSectionHeader.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        prefSectionHeader.textColor = .secondaryLabelColor
        root.addSubview(prefSectionHeader)
        
        // --- 2. APPLE-STYLE SELECTION CARDS ---
        let cardWidth = root.frame.width - 72
        let cardHeight: CGFloat = 72
        
        // Card 1: 15-Day Auto-Delete (Recommended)
        card1 = NSBox(frame: NSRect(x: 36, y: root.frame.height - 296, width: cardWidth, height: cardHeight))
        card1.boxType = .custom
        card1.cornerRadius = 10
        card1.borderWidth = 1.5
        
        let card1Icon = NSImageView(frame: NSRect(x: 14, y: 24, width: 24, height: 24))
        card1Icon.image = NSImage(systemSymbolName: "trash.badge.clock", accessibilityDescription: nil)
        card1Icon.contentTintColor = .controlAccentColor
        card1.addSubview(card1Icon)
        
        let radio1 = NSButton(radioButtonWithTitle: "Enable 15-Day Auto-Delete", target: self, action: #selector(autoDeleteRadioClicked))
        radio1.frame = NSRect(x: 46, y: 40, width: 230, height: 22)
        radio1.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        card1.addSubview(radio1)
        self.autoDeleteRadio = radio1
        
        // Recommended Badge Pill
        let recBadge = NSTextField(labelWithString: " RECOMMENDED ")
        recBadge.frame = NSRect(x: 278, y: 43, width: 106, height: 16)
        recBadge.font = NSFont.systemFont(ofSize: 9, weight: .bold)
        recBadge.textColor = .controlAccentColor
        recBadge.wantsLayer = true
        recBadge.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        recBadge.layer?.cornerRadius = 4
        recBadge.layer?.masksToBounds = true
        card1.addSubview(recBadge)
        
        let card1Desc = NSTextField(labelWithString: "Automatically deletes recordings older than 15 days to keep your disk clean. Ideal for throwaway AI bug demos.")
        card1Desc.frame = NSRect(x: 48, y: 10, width: cardWidth - 62, height: 28)
        card1Desc.font = NSFont.systemFont(ofSize: 11)
        card1Desc.textColor = .secondaryLabelColor
        card1.addSubview(card1Desc)
        
        let click1 = NSClickGestureRecognizer(target: self, action: #selector(autoDeleteRadioClicked))
        card1.addGestureRecognizer(click1)
        root.addSubview(card1)
        
        // Card 2: Keep All Recordings Forever
        card2 = NSBox(frame: NSRect(x: 36, y: root.frame.height - 380, width: cardWidth, height: cardHeight))
        card2.boxType = .custom
        card2.cornerRadius = 10
        card2.borderWidth = 1.0
        
        let card2Icon = NSImageView(frame: NSRect(x: 14, y: 24, width: 24, height: 24))
        card2Icon.image = NSImage(systemSymbolName: "archivebox", accessibilityDescription: nil)
        card2Icon.contentTintColor = .secondaryLabelColor
        card2.addSubview(card2Icon)
        
        let radio2 = NSButton(radioButtonWithTitle: "Keep All Recordings Forever", target: self, action: #selector(keepForeverRadioClicked))
        radio2.frame = NSRect(x: 46, y: 40, width: 260, height: 22)
        radio2.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        card2.addSubview(radio2)
        self.keepForeverRadio = radio2
        
        let card2Desc = NSTextField(labelWithString: "Never deletes recordings automatically. You can manually prune or delete them whenever you want.")
        card2Desc.frame = NSRect(x: 48, y: 10, width: cardWidth - 62, height: 28)
        card2Desc.font = NSFont.systemFont(ofSize: 11)
        card2Desc.textColor = .secondaryLabelColor
        card2.addSubview(card2Desc)
        
        let click2 = NSClickGestureRecognizer(target: self, action: #selector(keepForeverRadioClicked))
        card2.addGestureRecognizer(click2)
        root.addSubview(card2)
        
        // --- 3. ANTIGRAVITY & AI AGENTS CALLOUT CARD ---
        let calloutBox = NSBox(frame: NSRect(x: 36, y: root.frame.height - 496, width: cardWidth, height: 100))
        calloutBox.boxType = .custom
        calloutBox.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.08)
        calloutBox.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.3)
        calloutBox.borderWidth = 1
        calloutBox.cornerRadius = 10
        
        let calloutIcon = NSImageView(frame: NSRect(x: 14, y: calloutBox.frame.height - 34, width: 20, height: 20))
        calloutIcon.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)
        calloutIcon.contentTintColor = .controlAccentColor
        calloutBox.addSubview(calloutIcon)
        
        let calloutHeader = NSTextField(labelWithString: "Default on Stop: Copy File Path (Antigravity)")
        calloutHeader.frame = NSRect(x: 40, y: calloutBox.frame.height - 32, width: calloutBox.frame.width - 50, height: 18)
        calloutHeader.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        calloutBox.addSubview(calloutHeader)
        
        let calloutBody = NSTextField(wrappingLabelWithString: "When recording stops, Luna automatically copies the local file path to your clipboard. Simply press ⌘V in Antigravity or your AI tool for instant multimodal analysis!")
        calloutBody.frame = NSRect(x: 40, y: 12, width: calloutBox.frame.width - 54, height: 50)
        calloutBody.font = NSFont.systemFont(ofSize: 11.5)
        calloutBody.textColor = .secondaryLabelColor
        calloutBox.addSubview(calloutBody)
        
        root.addSubview(calloutBox)
        
        // --- 4. SHORTCUTS SUMMARY ---
        let shortcutsLbl = NSTextField(labelWithString: "Shortcuts:  ⌘⌥1 Area Crop  •  ⌘⌥2 Window Picker  •  ⌘⌥3 Full Screen  •  ⌘⌥S Stop")
        shortcutsLbl.frame = NSRect(x: 20, y: 64, width: root.frame.width - 40, height: 18)
        shortcutsLbl.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        shortcutsLbl.textColor = .tertiaryLabelColor
        shortcutsLbl.alignment = .center
        root.addSubview(shortcutsLbl)
        
        // --- 5. GET STARTED BUTTON ---
        let getStartedBtn = NSButton(frame: NSRect(x: (root.frame.width - 220) / 2, y: 18, width: 220, height: 36))
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
        updateCardStyles()
    }
    
    private func updateCardStyles() {
        let isAutoDelete = (autoDeleteRadio.state == .on)
        if isAutoDelete {
            card1.borderColor = NSColor.controlAccentColor
            card1.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.06)
            card1.borderWidth = 1.5
            
            card2.borderColor = NSColor.separatorColor.withAlphaComponent(0.4)
            card2.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.4)
            card2.borderWidth = 1.0
        } else {
            card1.borderColor = NSColor.separatorColor.withAlphaComponent(0.4)
            card1.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.4)
            card1.borderWidth = 1.0
            
            card2.borderColor = NSColor.controlAccentColor
            card2.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.06)
            card2.borderWidth = 1.5
        }
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
    
    @objc private func autoDeleteRadioClicked() {
        autoDeleteRadio.state = .on
        keepForeverRadio.state = .off
        updateCardStyles()
    }
    
    @objc private func keepForeverRadioClicked() {
        autoDeleteRadio.state = .off
        keepForeverRadio.state = .on
        updateCardStyles()
    }
    
    @objc private func getStartedClicked() {
        let shouldAutoDelete = (autoDeleteRadio.state == .on)
        RetentionManager.shared.isAutoDeleteEnabled = shouldAutoDelete
        RetentionManager.shared.hasCompletedOnboarding = true
        
        window?.orderOut(nil)
        print("[Onboarding] Completed. Auto-delete enabled: \(shouldAutoDelete)")
    }
}
