import AppKit
import AVFoundation
import AVKit

// MARK: - Video Thumbnail Provider
final class VideoThumbnailProvider {
    static let shared = VideoThumbnailProvider()
    private let cache = NSCache<NSURL, NSImage>()
    
    func thumbnail(for url: URL, completion: @escaping (NSImage?) -> Void) {
        let key = url as NSURL
        if let cached = cache.object(forKey: key) {
            completion(cached)
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 140, height: 90)
            
            let time = CMTime(seconds: 0.5, preferredTimescale: 600)
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                let img = NSImage(cgImage: cgImage, size: NSSize(width: 58, height: 38))
                self?.cache.setObject(img, forKey: key)
                DispatchQueue.main.async {
                    completion(img)
                }
            } else {
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
}

// MARK: - Window Floating Toast HUD
final class WindowToastHUDView: NSVisualEffectView {
    private let iconImageView = NSImageView()
    private let messageLabel = NSTextField(labelWithString: "")
    private var dismissTimer: Timer?
    
    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        
        shadow = NSShadow()
        shadow?.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow?.shadowOffset = NSSize(width: 0, height: -2)
        shadow?.shadowBlurRadius = 8
        
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        iconImageView.setContentHuggingPriority(.required, for: .horizontal)
        
        messageLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        messageLabel.textColor = .white
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        stack.addArrangedSubview(iconImageView)
        stack.addArrangedSubview(messageLabel)
        
        alphaValue = 0
        isHidden = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show(message: String, iconName: String = "checkmark.circle.fill", iconColor: NSColor = .systemGreen, duration: TimeInterval = 2.4) {
        dismissTimer?.invalidate()
        dismissTimer = nil
        
        messageLabel.stringValue = message
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        iconImageView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        iconImageView.contentTintColor = iconColor
        
        guard let superview = self.superview else { return }
        
        // Calculate dynamic width based on message
        messageLabel.sizeToFit()
        let contentWidth = messageLabel.frame.width + 48
        let targetWidth = min(max(contentWidth, 180), superview.frame.width - 40)
        let targetHeight: CGFloat = 36
        let targetX = (superview.frame.width - targetWidth) / 2
        let targetY: CGFloat = 84
        
        self.frame = NSRect(x: targetX, y: targetY - 6, width: targetWidth, height: targetHeight)
        self.isHidden = false
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().frame = NSRect(x: targetX, y: targetY, width: targetWidth, height: targetHeight)
            self.animator().alphaValue = 1.0
        }
        
        dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }
    
    func hide() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            if self?.alphaValue == 0 {
                self?.isHidden = true
            }
        })
    }
}

// MARK: - RecordingsWindowController
public final class RecordingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSplitViewDelegate, NSWindowDelegate, NSMenuDelegate {
    public static let shared = RecordingsWindowController()
    
    private var recordings: [URL] = []
    private var selectedRecordingURL: URL?
    private var durationCache: [URL: String] = [:]
    
    private var splitView: NSSplitView!
    private var sidebarView: NSView!
    private var detailView: NSView!
    
    private var tableView: SidebarTableView!
    private var countLabel: NSTextField!
    private var retentionFooterButton: NSButton!
    private var storageStatusIcon: NSImageView!
    
    private var titleLabel: NSTextField!
    private var subtitleLabel: NSTextField!
    private var playerView: AVPlayerView!
    private var playerTimeObserver: Any?
    
    // Voice Transcript Card
    private var transcriptCard: NSView!
    private var transcriptTextView: NSTextView!
    private var transcriptStatusLabel: NSTextField!
    private var transcriptCopyButton: NSButton!
    private var currentTranscriptText: String?
    
    // Multi-Select Container
    private var multiSelectContainer: NSView!
    private var multiSelectTitleLabel: NSTextField!
    private var multiSelectSubtitleLabel: NSTextField!
    
    // Action Bar Buttons
    private var copyPathBtn: NSButton!
    private var copyMp4Btn: NSButton!
    private var copyGifBtn: NSButton!
    private var revealBtn: NSButton!
    private var deleteBtn: NSButton!
    private var tipLabel: NSTextField!
    
    // Context Menu Items
    private var contextCopyPathItem: NSMenuItem!
    private var contextCopyMp4Item: NSMenuItem!
    private var contextCopyGifItem: NSMenuItem!
    private var contextRevealItem: NSMenuItem!
    private var contextDeleteItem: NSMenuItem!
    
    // Modern Floating Toast HUD
    private var toastHUD: WindowToastHUDView!
    
    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Screen Recordings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 840, height: 530)
        window.isReleasedWhenClosed = false
        
        super.init(window: window)
        window.delegate = self
        
        setupUI()
        updateRetentionUI()
        
        NotificationCenter.default.addObserver(self, selector: #selector(autoDeletePreferenceChanged), name: RetentionManager.autoDeleteDidChangeNotification, object: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func show(with latestRecordingURL: URL? = nil) {
        updateRetentionUI()
        refreshRecordingsList()
        
        if let latest = latestRecordingURL, let index = recordings.firstIndex(of: latest) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            tableView.scrollRowToVisible(index)
            selectedRecordingURL = latest
            if RetentionManager.shared.isAutoCopyPathEnabled {
                showToast(message: "✓ File path copied for your LLM (⌘V)", iconName: "link", iconColor: .controlAccentColor)
            }
        } else if !recordings.isEmpty {
            let index = 0
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            selectedRecordingURL = recordings.first
        } else {
            selectedRecordingURL = nil
        }
        
        updateSelectionState()
        
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func autoDeletePreferenceChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.updateRetentionUI()
        }
    }
    
    private func updateRetentionUI() {
        let isAutoDelete = RetentionManager.shared.isAutoDeleteEnabled
        let days = RetentionManager.shared.retentionDays
        if isAutoDelete {
            retentionFooterButton?.title = "\(days)-Day Auto-Delete"
            retentionFooterButton?.toolTip = "Click to inspect storage usage and auto-delete settings."
            storageStatusIcon?.contentTintColor = .controlAccentColor
        } else {
            retentionFooterButton?.title = "Auto-Delete Disabled"
            retentionFooterButton?.toolTip = "Click to configure automatic storage cleanup."
            storageStatusIcon?.contentTintColor = .secondaryLabelColor
        }
    }
    
    public func windowWillClose(_ notification: Notification) {
        if let observer = playerTimeObserver {
            playerView.player?.removeTimeObserver(observer)
            playerTimeObserver = nil
        }
        playerView.player?.pause()
    }
    
    private func refreshRecordingsList() {
        let folder = RetentionManager.shared.recordingsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        ) else {
            self.recordings = []
            tableView?.reloadData()
            countLabel?.stringValue = "0 recordings"
            return
        }
        
        // Filter valid MP4 recordings (exclude 0-byte and temp sandbox files)
        self.recordings = files
            .filter { url in
                guard url.pathExtension.lowercased() == "mp4" else { return false }
                guard !url.lastPathComponent.contains(".sb-") else { return false }
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                return size > 0
            }
            .sorted { (u1, u2) -> Bool in
                let d1 = (try? u1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                let d2 = (try? u2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                return d1 > d2
            }
        
        countLabel?.stringValue = "\(recordings.count) recording\(recordings.count == 1 ? "" : "s")"
        tableView?.reloadData()
    }
    
    // MARK: - UI Construction
    private func setupUI() {
        guard let window = self.window else { return }
        let root = NSView(frame: window.contentView!.bounds)
        root.autoresizingMask = [.width, .height]
        
        splitView = NSSplitView(frame: root.bounds)
        splitView.autoresizingMask = [.width, .height]
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        
        setupSidebar()
        setupDetailView()
        
        splitView.addSubview(sidebarView)
        splitView.addSubview(detailView)
        
        root.addSubview(splitView)
        window.contentView = root
    }
    
    private func setupSidebar() {
        let sidebar = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 280, height: 620))
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active
        self.sidebarView = sidebar
        
        // Header (leaving space for window traffic lights at top-left)
        let headerBox = NSView(frame: NSRect(x: 16, y: sidebar.frame.height - 72, width: sidebar.frame.width - 32, height: 36))
        headerBox.autoresizingMask = [.width, .minYMargin]
        
        let titleLbl = NSTextField(labelWithString: "Recordings")
        titleLbl.frame = NSRect(x: 0, y: 12, width: 140, height: 24)
        titleLbl.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        headerBox.addSubview(titleLbl)
        
        let countLbl = NSTextField(labelWithString: "0 recordings")
        countLbl.frame = NSRect(x: 0, y: 0, width: 180, height: 14)
        countLbl.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        countLbl.textColor = .secondaryLabelColor
        headerBox.addSubview(countLbl)
        self.countLabel = countLbl
        
        sidebar.addSubview(headerBox)
        
        // Sidebar Table View
        let scrollY: CGFloat = 44
        let scrollHeight = sidebar.frame.height - 76 - scrollY
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: scrollY, width: sidebar.frame.width, height: scrollHeight))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        
        let tbl = SidebarTableView(frame: scrollView.bounds)
        tbl.style = .sourceList
        tbl.headerView = nil
        tbl.rowHeight = 54
        tbl.backgroundColor = .clear
        tbl.allowsMultipleSelection = true
        
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SidebarColumn"))
        col.resizingMask = .autoresizingMask
        col.width = scrollView.contentSize.width
        tbl.addTableColumn(col)
        tbl.sizeLastColumnToFit()
        
        tbl.dataSource = self
        tbl.delegate = self
        tbl.target = self
        tbl.doubleAction = #selector(tableDoubleClicked)
        
        // Context Menu for desktop right-click experience
        let menu = NSMenu()
        menu.delegate = self
        
        contextCopyPathItem = NSMenuItem(title: "Copy Path for LLMs", action: #selector(contextCopyPath), keyEquivalent: "")
        contextCopyPathItem.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
        contextCopyPathItem.target = self
        menu.addItem(contextCopyPathItem)
        
        contextCopyMp4Item = NSMenuItem(title: "Copy MP4", action: #selector(contextCopyMp4), keyEquivalent: "")
        contextCopyMp4Item.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        contextCopyMp4Item.target = self
        menu.addItem(contextCopyMp4Item)
        
        contextCopyGifItem = NSMenuItem(title: "Copy GIF", action: #selector(contextCopyGif), keyEquivalent: "")
        contextCopyGifItem.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        contextCopyGifItem.target = self
        menu.addItem(contextCopyGifItem)
        
        contextRevealItem = NSMenuItem(title: "Reveal in Finder", action: #selector(contextReveal), keyEquivalent: "")
        contextRevealItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        contextRevealItem.target = self
        menu.addItem(contextRevealItem)
        
        menu.addItem(NSMenuItem.separator())
        
        contextDeleteItem = NSMenuItem(title: "Delete Recording...", action: #selector(contextDelete), keyEquivalent: "")
        contextDeleteItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        contextDeleteItem.target = self
        menu.addItem(contextDeleteItem)
        
        tbl.menu = menu
        
        scrollView.documentView = tbl
        sidebar.addSubview(scrollView)
        self.tableView = tbl
        
        // Footer Bar: Interactive Retention Button & Open Folder in Finder
        let footerBar = NSView(frame: NSRect(x: 0, y: 0, width: sidebar.frame.width, height: 44))
        footerBar.autoresizingMask = [.width, .maxYMargin]
        
        let divider = NSBox(frame: NSRect(x: 0, y: 43, width: footerBar.frame.width, height: 1))
        divider.boxType = .separator
        divider.autoresizingMask = [.width]
        footerBar.addSubview(divider)
        
        let statusIcon = NSImageView(frame: NSRect(x: 14, y: 14, width: 16, height: 16))
        statusIcon.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        statusIcon.contentTintColor = .controlAccentColor
        footerBar.addSubview(statusIcon)
        self.storageStatusIcon = statusIcon
        
        let retBtn = NSButton(frame: NSRect(x: 34, y: 8, width: 170, height: 28))
        retBtn.title = "15-Day Auto-Delete"
        retBtn.bezelStyle = .inline
        retBtn.isBordered = false
        retBtn.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        retBtn.contentTintColor = .secondaryLabelColor
        retBtn.alignment = .left
        retBtn.target = self
        retBtn.action = #selector(retentionFooterClicked)
        footerBar.addSubview(retBtn)
        self.retentionFooterButton = retBtn
        
        let finderBtn = NSButton(frame: NSRect(x: footerBar.frame.width - 38, y: 8, width: 28, height: 28))
        finderBtn.bezelStyle = .regularSquare
        finderBtn.isBordered = false
        finderBtn.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Open in Finder")
        finderBtn.contentTintColor = .secondaryLabelColor
        finderBtn.target = self
        finderBtn.action = #selector(openFolderClicked)
        finderBtn.autoresizingMask = [.minXMargin]
        footerBar.addSubview(finderBtn)
        
        sidebar.addSubview(footerBar)
    }
    
    private func setupDetailView() {
        let detail = NSView(frame: NSRect(x: 280, y: 0, width: 660, height: 620))
        detail.autoresizingMask = [.width, .height]
        detail.wantsLayer = true
        detail.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        self.detailView = detail
        
        // Header View: Formatted title and subtitle (Full width, no cramped pill)
        let headerView = NSView(frame: NSRect(x: 28, y: detail.frame.height - 76, width: detail.frame.width - 56, height: 50))
        headerView.autoresizingMask = [.width, .minYMargin]
        headerView.wantsLayer = true
        
        let mainTitle = NSTextField(labelWithString: "Select a Recording")
        mainTitle.frame = NSRect(x: 0, y: 22, width: headerView.frame.width, height: 24)
        mainTitle.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        mainTitle.lineBreakMode = .byTruncatingTail
        mainTitle.autoresizingMask = [.width]
        mainTitle.wantsLayer = true
        headerView.addSubview(mainTitle)
        self.titleLabel = mainTitle
        
        let subTitle = NSTextField(labelWithString: "")
        subTitle.frame = NSRect(x: 0, y: 2, width: headerView.frame.width, height: 18)
        subTitle.font = NSFont.systemFont(ofSize: 12)
        subTitle.textColor = .secondaryLabelColor
        subTitle.lineBreakMode = .byTruncatingMiddle
        subTitle.autoresizingMask = [.width]
        subTitle.wantsLayer = true
        headerView.addSubview(subTitle)
        self.subtitleLabel = subTitle
        
        detail.addSubview(headerView)
        
        // Action Bar (Bottom with clean layout and primary CTA)
        let actionBar = NSView(frame: NSRect(x: 28, y: 14, width: detail.frame.width - 56, height: 60))
        actionBar.autoresizingMask = [.width, .maxYMargin]
        actionBar.wantsLayer = true
        
        // Primary CTA: Copy Path for LLMs
        copyPathBtn = NSButton(frame: NSRect(x: 0, y: 0, width: 175, height: 30))
        copyPathBtn.bezelStyle = .rounded
        copyPathBtn.bezelColor = .controlAccentColor
        let symbolConfig = NSImage.SymbolConfiguration(paletteColors: [.white])
        copyPathBtn.image = NSImage(systemSymbolName: "link", accessibilityDescription: "Copy Path")?.withSymbolConfiguration(symbolConfig)
        copyPathBtn.imagePosition = .imageLeading
        copyPathBtn.contentTintColor = .white
        copyPathBtn.attributedTitle = NSAttributedString(string: "Copy Path for LLMs", attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        ])
        copyPathBtn.keyEquivalent = "\r"
        copyPathBtn.target = self
        copyPathBtn.action = #selector(copyPathClicked)
        
        // Secondary Actions
        copyMp4Btn = NSButton(frame: NSRect(x: 0, y: 0, width: 105, height: 30))
        copyMp4Btn.title = "Copy MP4"
        copyMp4Btn.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy MP4")
        copyMp4Btn.imagePosition = .imageLeading
        copyMp4Btn.bezelStyle = .rounded
        copyMp4Btn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        copyMp4Btn.target = self
        copyMp4Btn.action = #selector(copyMp4Clicked)
        
        copyGifBtn = NSButton(frame: NSRect(x: 0, y: 0, width: 95, height: 30))
        copyGifBtn.title = "Copy GIF"
        copyGifBtn.image = NSImage(systemSymbolName: "photo", accessibilityDescription: "Copy GIF")
        copyGifBtn.imagePosition = .imageLeading
        copyGifBtn.bezelStyle = .rounded
        copyGifBtn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        copyGifBtn.target = self
        copyGifBtn.action = #selector(copyGifClicked)
        
        revealBtn = NSButton(frame: NSRect(x: 0, y: 0, width: 95, height: 30))
        revealBtn.title = "In Finder"
        revealBtn.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "In Finder")
        revealBtn.imagePosition = .imageLeading
        revealBtn.bezelStyle = .rounded
        revealBtn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        revealBtn.target = self
        revealBtn.action = #selector(revealClicked)
        
        deleteBtn = NSButton(frame: NSRect(x: 0, y: 0, width: 85, height: 30))
        deleteBtn.title = "Delete"
        deleteBtn.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")
        deleteBtn.imagePosition = .imageLeading
        deleteBtn.bezelStyle = .rounded
        deleteBtn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        deleteBtn.contentTintColor = .systemRed
        deleteBtn.target = self
        deleteBtn.action = #selector(deleteClicked)
        
        let buttonStack = NSStackView()
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8
        buttonStack.alignment = .centerY
        buttonStack.frame = NSRect(x: 0, y: 24, width: actionBar.frame.width, height: 32)
        buttonStack.autoresizingMask = [.width]
        
        buttonStack.addView(copyPathBtn, in: .leading)
        buttonStack.addView(copyMp4Btn, in: .leading)
        buttonStack.addView(copyGifBtn, in: .leading)
        buttonStack.addView(revealBtn, in: .leading)
        buttonStack.addView(deleteBtn, in: .trailing)
        actionBar.addSubview(buttonStack)
        
        tipLabel = NSTextField(labelWithString: "Ready for Antigravity. Simply press ⌘V in your prompt to inspect recording.")
        tipLabel.frame = NSRect(x: 2, y: 2, width: actionBar.frame.width - 4, height: 14)
        tipLabel.font = NSFont.systemFont(ofSize: 11)
        tipLabel.textColor = .tertiaryLabelColor
        tipLabel.wantsLayer = true
        actionBar.addSubview(tipLabel)
        
        detail.addSubview(actionBar)
        
        // Native Widescreen Video Player (AVPlayerView)
        // Positioned leaving room for the Voice Transcript Card below
        let playerY: CGFloat = 180
        let playerHeight = detail.frame.height - 76 - playerY - 12
        let pView = AVPlayerView(frame: NSRect(x: 28, y: playerY, width: detail.frame.width - 56, height: playerHeight))
        pView.controlsStyle = .inline
        pView.showsFullScreenToggleButton = true
        pView.autoresizingMask = [.width, .height]
        pView.wantsLayer = true
        pView.layer?.cornerRadius = 10
        pView.layer?.masksToBounds = true
        pView.layer?.backgroundColor = NSColor.black.cgColor
        pView.layer?.borderWidth = 0.5
        pView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        detail.addSubview(pView)
        self.playerView = pView
        
        // Voice Transcript Card (Between Player and Action Bar)
        setupTranscriptCard(detailView: detail)
        
        // Multi-Selection Overlay Container (Occupies Player & Transcript Space when multiple items selected)
        setupMultiSelectContainer(detailView: detail)
        
        // Floating Translucent Toast HUD
        toastHUD = WindowToastHUDView()
        detail.addSubview(toastHUD)
    }
    
    private func setupTranscriptCard(detailView: NSView) {
        let card = NSView(frame: NSRect(x: 28, y: 80, width: detailView.frame.width - 56, height: 90))
        card.autoresizingMask = [.width, .maxYMargin]
        card.wantsLayer = true
        card.layer?.cornerRadius = 8
        card.layer?.masksToBounds = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.65).cgColor
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        
        // Header Row: Icon + Title + Status + Copy Button
        let micIcon = NSImageView(frame: NSRect(x: 10, y: 64, width: 16, height: 16))
        micIcon.image = NSImage(systemSymbolName: "waveform.and.mic", accessibilityDescription: "Voice Transcript")
        micIcon.contentTintColor = .controlAccentColor
        card.addSubview(micIcon)
        
        let titleLbl = NSTextField(labelWithString: "Voice Transcript")
        titleLbl.frame = NSRect(x: 32, y: 64, width: 110, height: 16)
        titleLbl.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        card.addSubview(titleLbl)
        
        let statusLbl = NSTextField(labelWithString: "Apple Speech")
        statusLbl.frame = NSRect(x: 146, y: 64, width: 220, height: 15)
        statusLbl.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        statusLbl.textColor = .secondaryLabelColor
        card.addSubview(statusLbl)
        self.transcriptStatusLabel = statusLbl
        
        let copyBtn = NSButton(frame: NSRect(x: card.frame.width - 92, y: 60, width: 84, height: 22))
        copyBtn.title = "Copy Text"
        copyBtn.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy Transcript")
        copyBtn.imagePosition = .imageLeading
        copyBtn.bezelStyle = .inline
        copyBtn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        copyBtn.target = self
        copyBtn.action = #selector(copyTranscriptClicked)
        copyBtn.autoresizingMask = [.minXMargin]
        card.addSubview(copyBtn)
        self.transcriptCopyButton = copyBtn
        
        // Scrollable transcript text
        let scroll = NSScrollView(frame: NSRect(x: 10, y: 8, width: card.frame.width - 20, height: 50))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        
        let textView = NSTextView(frame: scroll.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: 11.5)
        textView.textColor = .labelColor
        textView.string = "No speech detected in this recording."
        scroll.documentView = textView
        card.addSubview(scroll)
        self.transcriptTextView = textView
        
        detailView.addSubview(card)
        self.transcriptCard = card
    }
    
    private func setupMultiSelectContainer(detailView: NSView) {
        let container = NSView(frame: NSRect(x: 28, y: 80, width: detailView.frame.width - 56, height: detailView.frame.height - 168))
        container.autoresizingMask = [.width, .height]
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.4).cgColor
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        container.isHidden = true
        
        let centerStack = NSStackView()
        centerStack.orientation = .vertical
        centerStack.spacing = 10
        centerStack.alignment = .centerX
        centerStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(centerStack)
        
        NSLayoutConstraint.activate([
            centerStack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            centerStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            centerStack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            centerStack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24)
        ])
        
        let iconView = NSImageView()
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 42, weight: .regular)
        iconView.image = NSImage(systemSymbolName: "film.stack.fill", accessibilityDescription: "Multiple Recordings")?.withSymbolConfiguration(iconConfig)
        iconView.contentTintColor = .controlAccentColor
        centerStack.addArrangedSubview(iconView)
        
        let titleLbl = NSTextField(labelWithString: "Multiple Recordings Selected")
        titleLbl.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        titleLbl.alignment = .center
        centerStack.addArrangedSubview(titleLbl)
        self.multiSelectTitleLabel = titleLbl
        
        let subLbl = NSTextField(labelWithString: "Choose an action below to batch process your selection.")
        subLbl.font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
        subLbl.textColor = .secondaryLabelColor
        subLbl.alignment = .center
        centerStack.addArrangedSubview(subLbl)
        self.multiSelectSubtitleLabel = subLbl
        
        detailView.addSubview(container)
        self.multiSelectContainer = container
    }
    
    // MARK: - NSSplitViewDelegate
    public func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return 230
    }
    
    public func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return 340
    }
    
    public func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        return false
    }
    
    public func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
        let dividerThickness = splitView.dividerThickness
        let sidebarWidth = min(max(sidebarView.frame.width, 230), 340)
        let totalWidth = splitView.bounds.width
        let detailWidth = max(totalWidth - sidebarWidth - dividerThickness, 400)
        
        sidebarView.frame = NSRect(x: 0, y: 0, width: sidebarWidth, height: splitView.bounds.height)
        detailView.frame = NSRect(x: sidebarWidth + dividerThickness, y: 0, width: detailWidth, height: splitView.bounds.height)
    }
    
    // MARK: - Modern Toast HUD
    private func showToast(message: String, iconName: String = "checkmark.circle.fill", iconColor: NSColor = .systemGreen, duration: TimeInterval = 2.4) {
        toastHUD.show(message: message, iconName: iconName, iconColor: iconColor, duration: duration)
    }
    
    // MARK: - Selection State Handling
    private func updateSelectionState() {
        let selectedIndexes = tableView.selectedRowIndexes
        let count = selectedIndexes.count
        
        if count == 0 {
            // Empty state
            selectedRecordingURL = nil
            playerView.player?.pause()
            playerView.player = nil
            playerView.isHidden = false
            transcriptCard.isHidden = true
            multiSelectContainer.isHidden = true
            
            titleLabel.stringValue = "No Recording Selected"
            subtitleLabel.stringValue = "Take a recording using ⌘⌥1, ⌘⌥2, or ⌘⌥3"
            
            copyPathBtn.isEnabled = false
            copyMp4Btn.isEnabled = false
            copyGifBtn.isEnabled = false
            revealBtn.isEnabled = false
            deleteBtn.isEnabled = false
            
            copyPathBtn.attributedTitle = NSAttributedString(string: "Copy Path for LLMs", attributes: [
                .foregroundColor: NSColor.disabledControlTextColor,
                .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold)
            ])
            copyMp4Btn.title = "Copy MP4"
            deleteBtn.title = "Delete"
            return
        }
        
        copyPathBtn.isEnabled = true
        copyMp4Btn.isEnabled = true
        revealBtn.isEnabled = true
        deleteBtn.isEnabled = true
        
        if count == 1 {
            // Single selection mode
            multiSelectContainer.isHidden = true
            playerView.isHidden = false
            transcriptCard.isHidden = false
            copyGifBtn.isEnabled = true
            copyGifBtn.isHidden = false
            
            let row = selectedIndexes.first!
            guard row < recordings.count else { return }
            let url = recordings[row]
            selectedRecordingURL = url
            
            copyPathBtn.attributedTitle = NSAttributedString(string: "Copy Path for LLMs", attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold)
            ])
            copyMp4Btn.title = "Copy MP4"
            deleteBtn.title = "Delete"
            tipLabel.stringValue = "Ready for Antigravity. Simply press ⌘V in your prompt to inspect recording."
            
            updateSingleRecordingDetails(for: url)
        } else {
            // Multi-selection mode!
            playerView.player?.pause()
            playerView.isHidden = true
            transcriptCard.isHidden = true
            multiSelectContainer.isHidden = false
            copyGifBtn.isEnabled = false
            copyGifBtn.isHidden = true
            
            let selectedURLs = selectedIndexes.compactMap { $0 < recordings.count ? recordings[$0] : nil }
            let totalBytes = selectedURLs.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }
            let sizeStr = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            
            titleLabel.stringValue = "\(count) Recordings Selected"
            subtitleLabel.stringValue = "Total Size: \(sizeStr)  •  Shift or ⌘-click in sidebar to adjust selection"
            
            multiSelectTitleLabel.stringValue = "\(count) Recordings Selected"
            multiSelectSubtitleLabel.stringValue = "Total Size: \(sizeStr)\nBatch actions are ready below for copying or deleting."
            
            copyPathBtn.attributedTitle = NSAttributedString(string: "Copy \(count) Paths for LLMs", attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold)
            ])
            copyMp4Btn.title = "Copy \(count) MP4s"
            deleteBtn.title = "Delete \(count)"
            tipLabel.stringValue = "Ready for Antigravity. Simply press ⌘V to inspect all \(count) selected recordings."
        }
    }
    
    private func updateSingleRecordingDetails(for url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            titleLabel.stringValue = "Recording Not Found"
            subtitleLabel.stringValue = url.lastPathComponent
            playerView.player = nil
            return
        }
        
        let friendlyTitle = formattedDateTitle(for: url)
        titleLabel.stringValue = friendlyTitle
        
        let sizeStr = RetentionManager.formattedFileSize(for: url)
        subtitleLabel.stringValue = "\(url.lastPathComponent)  •  \(sizeStr)"
        
        let asset = AVURLAsset(url: url)
        Task {
            let duration = (try? await asset.load(.duration)) ?? .zero
            let totalSecs = Int(CMTimeGetSeconds(duration))
            let durStr = String(format: "%02d:%02d", totalSecs / 60, totalSecs % 60)
            
            await MainActor.run {
                self.durationCache[url] = durStr
                if self.selectedRecordingURL == url && self.tableView.selectedRowIndexes.count == 1 {
                    self.subtitleLabel.stringValue = "\(url.lastPathComponent)  •  \(durStr)  •  \(sizeStr)"
                }
            }
        }
        
        if let observer = playerTimeObserver {
            playerView.player?.removeTimeObserver(observer)
            playerTimeObserver = nil
        }
        
        let player = AVPlayer(url: url)
        self.playerView.player = player
        
        playerTimeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 2), queue: .main) { [weak self] time in
            guard let self = self, self.selectedRecordingURL == url, self.tableView.selectedRowIndexes.count == 1 else { return }
            let curSecs = Int(CMTimeGetSeconds(time))
            let curStr = String(format: "%02d:%02d", curSecs / 60, curSecs % 60)
            let totalSecs = Int(CMTimeGetSeconds(player.currentItem?.duration ?? .zero))
            let totalStr = totalSecs > 0 ? String(format: "%02d:%02d", totalSecs / 60, totalSecs % 60) : "--:--"
            self.subtitleLabel.stringValue = "\(url.lastPathComponent)  •  ⏱ \(curStr) / \(totalStr)  •  \(sizeStr)"
        }
        
        player.play()
        
        // Load or ensure voice transcript
        loadVoiceTranscript(for: url)
    }
    
    private func loadVoiceTranscript(for url: URL) {
        // Fast path: read already saved transcript from prompt.md
        if let existing = AudioTranscriber.shared.extractSavedTranscript(for: url), !existing.isEmpty {
            self.currentTranscriptText = existing
            self.transcriptTextView.string = existing
            self.transcriptTextView.textColor = .labelColor
            self.transcriptStatusLabel.stringValue = "Apple Speech (Transcribed)"
            self.transcriptStatusLabel.textColor = .secondaryLabelColor
            self.transcriptCopyButton.isEnabled = true
            return
        }
        
        // Asynchronous background extraction or on-device transcription
        self.currentTranscriptText = nil
        self.transcriptTextView.string = "Transcribing voice narration..."
        self.transcriptTextView.textColor = .secondaryLabelColor
        self.transcriptStatusLabel.stringValue = "Processing audio..."
        self.transcriptStatusLabel.textColor = .controlAccentColor
        self.transcriptCopyButton.isEnabled = false
        
        Task {
            let transcript = await AudioTranscriber.shared.ensureTranscript(for: url)
            await MainActor.run {
                guard self.selectedRecordingURL == url else { return }
                if let t = transcript, !t.isEmpty {
                    self.currentTranscriptText = t
                    self.transcriptTextView.string = t
                    self.transcriptTextView.textColor = .labelColor
                    self.transcriptStatusLabel.stringValue = "Apple Speech"
                    self.transcriptStatusLabel.textColor = .secondaryLabelColor
                    self.transcriptCopyButton.isEnabled = true
                } else {
                    self.currentTranscriptText = nil
                    self.transcriptTextView.string = "No speech detected in this recording."
                    self.transcriptTextView.textColor = .tertiaryLabelColor
                    self.transcriptStatusLabel.stringValue = "No Audio"
                    self.transcriptStatusLabel.textColor = .secondaryLabelColor
                    self.transcriptCopyButton.isEnabled = false
                }
            }
        }
    }
    
    private func formattedDateTitle(for url: URL) -> String {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        
        if calendar.isDateInToday(date) {
            return "Today at \(timeFormatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday at \(timeFormatter.string(from: date))"
        } else {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            return df.string(from: date)
        }
    }
    
    private func formattedSidebarDate(for url: URL) -> String {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        
        if calendar.isDateInToday(date) {
            return "Today, \(timeFormatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday, \(timeFormatter.string(from: date))"
        } else {
            let df = DateFormatter()
            df.dateFormat = "MMM d, h:mm a"
            return df.string(from: date)
        }
    }
    
    // MARK: - Actions
    @objc private func copyTranscriptClicked() {
        guard let text = currentTranscriptText, !text.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        showToast(message: "✓ Copied transcript to clipboard", iconName: "doc.on.doc", iconColor: .controlAccentColor)
    }
    
    public func copyPath(at row: Int) {
        guard row >= 0 && row < recordings.count else { return }
        let url = recordings[row]
        if selectedRecordingURL != url || tableView.selectedRowIndexes.count != 1 {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            selectedRecordingURL = url
            updateSelectionState()
        }
        PasteboardManager.shared.copyAIPromptToPasteboard(fileURL: url)
        showToast(message: "✓ Copied path & prompt for LLMs (⌘V)", iconName: "link", iconColor: .controlAccentColor)
    }
    
    @objc private func copyPathClicked() {
        let selectedIndexes = tableView.selectedRowIndexes
        if selectedIndexes.count > 1 {
            let urls = selectedIndexes.compactMap { $0 < recordings.count ? recordings[$0] : nil }
            PasteboardManager.shared.copyMultipleAIPromptsToPasteboard(fileURLs: urls)
            showToast(message: "✓ Copied \(urls.count) paths & prompts for LLMs (⌘V)", iconName: "link", iconColor: .controlAccentColor)
        } else if let url = selectedRecordingURL, let row = recordings.firstIndex(of: url) {
            copyPath(at: row)
        } else if tableView.selectedRow >= 0 {
            copyPath(at: tableView.selectedRow)
        }
    }
    
    @objc private func copyMp4Clicked() {
        let selectedIndexes = tableView.selectedRowIndexes
        if selectedIndexes.count > 1 {
            let urls = selectedIndexes.compactMap { $0 < recordings.count ? recordings[$0] : nil }
            PasteboardManager.shared.copyMultipleFilesToPasteboard(fileURLs: urls)
            showToast(message: "✓ Copied \(urls.count) MP4 files to clipboard", iconName: "doc.on.doc", iconColor: .controlAccentColor)
        } else if let url = selectedRecordingURL {
            PasteboardManager.shared.copyFileToPasteboard(fileURL: url)
            showToast(message: "✓ Copied MP4 file to clipboard", iconName: "doc.on.doc", iconColor: .controlAccentColor)
        }
    }
    
    @objc private func copyGifClicked() {
        guard let url = selectedRecordingURL else { return }
        showToast(message: "⏳ Converting to GIF...", iconName: "hourglass", iconColor: .systemOrange, duration: 8.0)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if let gifURL = MediaPostProcessor.shared.generateGIF(from: url) {
                PasteboardManager.shared.copyGIFToPasteboard(gifURL: gifURL)
                DispatchQueue.main.async {
                    self?.showToast(message: "✓ Copied GIF to clipboard", iconName: "photo", iconColor: .controlAccentColor)
                }
            } else {
                DispatchQueue.main.async {
                    self?.showToast(message: "❌ GIF conversion failed", iconName: "exclamationmark.triangle", iconColor: .systemRed)
                }
            }
        }
    }
    
    @objc private func revealClicked() {
        let selectedIndexes = tableView.selectedRowIndexes
        if selectedIndexes.count > 1 {
            let urls = selectedIndexes.compactMap { $0 < recordings.count ? recordings[$0] : nil }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        } else if let url = selectedRecordingURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
    
    public func deleteRecording(at row: Int) {
        guard row >= 0 && row < recordings.count else { return }
        let url = recordings[row]
        let alert = NSAlert()
        alert.messageText = "Delete Recording?"
        alert.informativeText = "Are you sure you want to delete \"\(formattedDateTitle(for: url))\" and its prompts?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            let wasSelected = (selectedRecordingURL == url)
            if wasSelected {
                playerView.player?.pause()
                playerView.player = nil
                selectedRecordingURL = nil
            }
            
            RetentionManager.shared.deleteRecordingAndAuxiliaries(for: url)
            refreshRecordingsList()
            
            if !recordings.isEmpty {
                let newIndex = min(row, recordings.count - 1)
                tableView.selectRowIndexes(IndexSet(integer: newIndex), byExtendingSelection: false)
                selectedRecordingURL = recordings[newIndex]
            } else {
                selectedRecordingURL = nil
            }
            
            updateSelectionState()
            showToast(message: "Deleted recording", iconName: "trash.fill", iconColor: .systemRed)
        }
    }
    
    public func deleteSelected() {
        let selectedIndexes = tableView.selectedRowIndexes
        if selectedIndexes.count > 1 {
            let urls = selectedIndexes.compactMap { $0 < recordings.count ? recordings[$0] : nil }
            let totalBytes = urls.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }
            let sizeStr = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            
            let alert = NSAlert()
            alert.messageText = "Delete \(urls.count) Recordings?"
            alert.informativeText = "Are you sure you want to permanently delete \(urls.count) recordings (\(sizeStr)) and all associated prompts and transcripts?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Delete All")
            alert.addButton(withTitle: "Cancel")
            
            if alert.runModal() == .alertFirstButtonReturn {
                playerView.player?.pause()
                playerView.player = nil
                selectedRecordingURL = nil
                
                for url in urls {
                    RetentionManager.shared.deleteRecordingAndAuxiliaries(for: url)
                }
                
                refreshRecordingsList()
                
                if !recordings.isEmpty {
                    tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                    selectedRecordingURL = recordings.first
                }
                
                updateSelectionState()
                showToast(message: "Deleted \(urls.count) recordings", iconName: "trash.fill", iconColor: .systemRed)
            }
        } else if tableView.selectedRow >= 0 {
            deleteRecording(at: tableView.selectedRow)
        }
    }
    
    @objc private func deleteClicked() {
        deleteSelected()
    }
    
    @objc private func openFolderClicked() {
        NSWorkspace.shared.open(RetentionManager.shared.recordingsDirectory)
    }
    
    @objc private func tableDoubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0 && row < recordings.count else { return }
        NSWorkspace.shared.open(recordings[row])
    }
    
    // MARK: - Interactive Storage & Auto-Retention Sheet
    @objc private func retentionFooterClicked() {
        showStorageRetentionSheet()
    }
    
    private func showStorageRetentionSheet() {
        guard let parentWindow = self.window else { return }
        
        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 320),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        sheet.title = "Storage & Auto-Retention"
        
        let content = NSView(frame: sheet.contentRect(forFrameRect: sheet.frame))
        content.autoresizingMask = [.width, .height]
        
        // Header Icon & Titles
        let iconView = NSImageView(frame: NSRect(x: 24, y: content.frame.height - 56, width: 36, height: 36))
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)?.withSymbolConfiguration(iconConfig)
        iconView.contentTintColor = .controlAccentColor
        content.addSubview(iconView)
        
        let titleLabel = NSTextField(labelWithString: "Storage & Auto-Retention")
        titleLabel.frame = NSRect(x: 70, y: content.frame.height - 42, width: 340, height: 22)
        titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        content.addSubview(titleLabel)
        
        let subLabel = NSTextField(labelWithString: "Manage automatic cleanup to free up disk space.")
        subLabel.frame = NSRect(x: 70, y: content.frame.height - 60, width: 340, height: 16)
        subLabel.font = NSFont.systemFont(ofSize: 11.5)
        subLabel.textColor = .secondaryLabelColor
        content.addSubview(subLabel)
        
        // Storage Breakdown Box
        let box = NSBox(frame: NSRect(x: 24, y: content.frame.height - 156, width: content.frame.width - 48, height: 86))
        box.boxType = .custom
        box.cornerRadius = 8
        box.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6)
        box.borderColor = NSColor.separatorColor.withAlphaComponent(0.3)
        box.borderWidth = 0.5
        box.autoresizingMask = [.width]
        
        let totalLbl = NSTextField(labelWithString: "Total Space Used:")
        totalLbl.frame = NSRect(x: 16, y: 50, width: 140, height: 18)
        totalLbl.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        totalLbl.textColor = .secondaryLabelColor
        box.addSubview(totalLbl)
        
        let totalVal = NSTextField(labelWithString: "Calculating...")
        totalVal.frame = NSRect(x: 160, y: 50, width: 230, height: 18)
        totalVal.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        box.addSubview(totalVal)
        
        let cleanLbl = NSTextField(labelWithString: "Cleanable Now:")
        cleanLbl.frame = NSRect(x: 16, y: 20, width: 140, height: 18)
        cleanLbl.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        cleanLbl.textColor = .secondaryLabelColor
        box.addSubview(cleanLbl)
        
        let cleanVal = NSTextField(labelWithString: "Calculating...")
        cleanVal.frame = NSRect(x: 160, y: 20, width: 230, height: 18)
        cleanVal.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        cleanVal.textColor = .controlAccentColor
        box.addSubview(cleanVal)
        
        content.addSubview(box)
        
        // Threshold Segmented Control
        let thresholdLbl = NSTextField(labelWithString: "Retention Period:")
        thresholdLbl.frame = NSRect(x: 24, y: content.frame.height - 194, width: 130, height: 18)
        thresholdLbl.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        content.addSubview(thresholdLbl)
        
        let segment = NSSegmentedControl(labels: ["7 Days", "15 Days", "30 Days", "60 Days"], trackingMode: .selectOne, target: nil, action: nil)
        segment.frame = NSRect(x: 154, y: content.frame.height - 198, width: 272, height: 26)
        content.addSubview(segment)
        
        let currentDays = RetentionManager.shared.retentionDays
        let daysOptions = [7, 15, 30, 60]
        if let idx = daysOptions.firstIndex(of: currentDays) {
            segment.selectedSegment = idx
        } else {
            segment.selectedSegment = 1 // default 15
        }
        
        // Auto-Delete Checkbox
        let autoCheck = NSButton(checkboxWithTitle: "Automatically delete old recordings on app launch", target: nil, action: nil)
        autoCheck.frame = NSRect(x: 24, y: content.frame.height - 232, width: 380, height: 20)
        autoCheck.font = NSFont.systemFont(ofSize: 12)
        autoCheck.state = RetentionManager.shared.isAutoDeleteEnabled ? .on : .off
        content.addSubview(autoCheck)
        
        // Bottom Action Buttons
        let cleanBtn = NSButton(frame: NSRect(x: 24, y: 16, width: 190, height: 32))
        cleanBtn.title = "Clean Up Now"
        cleanBtn.bezelStyle = .rounded
        cleanBtn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        content.addSubview(cleanBtn)
        
        let doneBtn = NSButton(frame: NSRect(x: content.frame.width - 104, y: 16, width: 80, height: 32))
        doneBtn.title = "Done"
        doneBtn.bezelStyle = .rounded
        doneBtn.keyEquivalent = "\r"
        content.addSubview(doneBtn)
        
        func updateAnalysisUI() {
            let selectedDays = daysOptions[max(0, min(segment.selectedSegment, daysOptions.count - 1))]
            let analysis = RetentionManager.shared.analyzeStorage(forDays: selectedDays)
            
            totalVal.stringValue = "\(analysis.formattedTotalSize) (\(analysis.totalRecordingsCount) recordings)"
            if analysis.eligibleCount > 0 {
                cleanVal.stringValue = "\(analysis.formattedEligibleSize) (\(analysis.eligibleCount) old recordings)"
                cleanBtn.isEnabled = true
                cleanBtn.title = "Clean Up Now (Free \(analysis.formattedEligibleSize))"
            } else {
                cleanVal.stringValue = "0 MB (No recordings older than \(selectedDays) days)"
                cleanBtn.isEnabled = false
                cleanBtn.title = "Clean Up Now (Free 0 MB)"
            }
        }
        
        updateAnalysisUI()
        
        // Storage Sheet Actions Helper
        class SheetHelper: NSObject {
            let sheet: NSWindow
            let parentWindow: NSWindow
            let updateUI: () -> Void
            let daysOptions: [Int]
            let segment: NSSegmentedControl
            let autoCheck: NSButton
            let owner: RecordingsWindowController
            
            init(sheet: NSWindow, parentWindow: NSWindow, updateUI: @escaping () -> Void, daysOptions: [Int], segment: NSSegmentedControl, autoCheck: NSButton, owner: RecordingsWindowController) {
                self.sheet = sheet
                self.parentWindow = parentWindow
                self.updateUI = updateUI
                self.daysOptions = daysOptions
                self.segment = segment
                self.autoCheck = autoCheck
                self.owner = owner
            }
            
            @objc func segmentChanged(_ sender: NSSegmentedControl) {
                let days = daysOptions[max(0, min(sender.selectedSegment, daysOptions.count - 1))]
                RetentionManager.shared.retentionDays = days
                updateUI()
                owner.updateRetentionUI()
            }
            
            @objc func autoDeleteToggled(_ sender: NSButton) {
                let enabled = (sender.state == .on)
                RetentionManager.shared.isAutoDeleteEnabled = enabled
                owner.updateRetentionUI()
            }
            
            @objc func cleanUpClicked(_ sender: NSButton) {
                let days = daysOptions[max(0, min(segment.selectedSegment, daysOptions.count - 1))]
                let analysis = RetentionManager.shared.analyzeStorage(forDays: days)
                guard analysis.eligibleCount > 0 else { return }
                
                let (pruned, freed) = RetentionManager.shared.pruneRecordingsOlderThan(days: days)
                let freedStr = ByteCountFormatter.string(fromByteCount: freed, countStyle: .file)
                
                owner.refreshRecordingsList()
                owner.updateSelectionState()
                owner.updateRetentionUI()
                updateUI()
                
                owner.showToast(message: "✓ Cleaned up \(pruned) recordings (\(freedStr) freed)", iconName: "trash.circle.fill", iconColor: .controlAccentColor)
            }
            
            @objc func doneClicked(_ sender: NSButton) {
                parentWindow.endSheet(sheet)
            }
        }
        
        let helper = SheetHelper(sheet: sheet, parentWindow: parentWindow, updateUI: updateAnalysisUI, daysOptions: daysOptions, segment: segment, autoCheck: autoCheck, owner: self)
        objc_setAssociatedObject(sheet, "sheetHelper", helper, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        segment.target = helper
        segment.action = #selector(SheetHelper.segmentChanged(_:))
        
        autoCheck.target = helper
        autoCheck.action = #selector(SheetHelper.autoDeleteToggled(_:))
        
        cleanBtn.target = helper
        cleanBtn.action = #selector(SheetHelper.cleanUpClicked(_:))
        
        doneBtn.target = helper
        doneBtn.action = #selector(SheetHelper.doneClicked(_:))
        
        parentWindow.beginSheet(sheet)
    }
    
    // MARK: - Context Menu Actions
    @objc private func contextCopyPath() {
        copyPathClicked()
    }
    
    @objc private func contextCopyMp4() {
        copyMp4Clicked()
    }
    
    @objc private func contextCopyGif() {
        copyGifClicked()
    }
    
    @objc private func contextReveal() {
        revealClicked()
    }
    
    @objc private func contextDelete() {
        deleteSelected()
    }
    
    // MARK: - NSMenuDelegate (Dynamically update Context Menu titles based on selection)
    public func menuWillOpen(_ menu: NSMenu) {
        let count = tableView.selectedRowIndexes.count
        if count > 1 {
            contextCopyPathItem?.title = "Copy \(count) Paths for LLMs"
            contextCopyMp4Item?.title = "Copy \(count) MP4s"
            contextCopyGifItem?.isHidden = true
            contextRevealItem?.title = "Reveal \(count) in Finder"
            contextDeleteItem?.title = "Delete \(count) Recordings..."
        } else {
            contextCopyPathItem?.title = "Copy Path for LLMs"
            contextCopyMp4Item?.title = "Copy MP4"
            contextCopyGifItem?.isHidden = false
            contextRevealItem?.title = "Reveal in Finder"
            contextDeleteItem?.title = "Delete Recording..."
        }
    }
    
    // MARK: - NSTableViewDataSource & Delegate
    public func numberOfRows(in tableView: NSTableView) -> Int {
        return recordings.count
    }
    
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < recordings.count else { return nil }
        let url = recordings[row]
        
        let cellId = NSUserInterfaceItemIdentifier("SidebarRecordingCell")
        var cell = tableView.makeView(withIdentifier: cellId, owner: nil) as? SidebarRecordingCellView
        if cell == nil {
            cell = SidebarRecordingCellView()
            cell?.identifier = cellId
        }
        
        let title = formattedSidebarDate(for: url)
        let size = RetentionManager.formattedFileSize(for: url)
        let dur = durationCache[url]
        let sub = dur != nil ? "\(dur!)  •  \(size)" : size
        
        cell?.configure(url: url, title: title, subtitle: sub)
        
        return cell
    }
    
    public func tableViewSelectionDidChange(_ notification: Notification) {
        updateSelectionState()
    }
    
    // MARK: - NSTableViewDelegate Row Actions (Swipe Left / Trailing Edge)
    public func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
        guard edge == .trailing else { return [] }
        guard row >= 0 && row < recordings.count else { return [] }
        
        let deleteAction = NSTableViewRowAction(style: .destructive, title: "Delete") { [weak self] _, row in
            self?.deleteRecording(at: row)
        }
        deleteAction.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")
        deleteAction.backgroundColor = .systemRed
        
        let copyAction = NSTableViewRowAction(style: .regular, title: "Copy Path") { [weak self] _, row in
            self?.copyPath(at: row)
        }
        copyAction.image = NSImage(systemSymbolName: "link", accessibilityDescription: "Copy Path")
        copyAction.backgroundColor = .controlAccentColor
        
        return [deleteAction, copyAction]
    }
}

// MARK: - SidebarRecordingCellView
final class SidebarRecordingCellView: NSTableCellView {
    private let thumbnailImageView = NSImageView()
    private let durationBadge = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private var currentURL: URL?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        // Thumbnail
        thumbnailImageView.frame = NSRect(x: 10, y: 8, width: 58, height: 38)
        thumbnailImageView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailImageView.wantsLayer = true
        thumbnailImageView.layer?.cornerRadius = 5
        thumbnailImageView.layer?.masksToBounds = true
        thumbnailImageView.layer?.borderWidth = 0.5
        thumbnailImageView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        thumbnailImageView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
        addSubview(thumbnailImageView)
        
        // Duration Badge on Thumbnail (YouTube/QuickTime style)
        durationBadge.frame = NSRect(x: 23, y: 2, width: 32, height: 13)
        durationBadge.font = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .bold)
        durationBadge.textColor = .white
        durationBadge.alignment = .center
        durationBadge.wantsLayer = true
        durationBadge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        durationBadge.layer?.cornerRadius = 3
        durationBadge.layer?.masksToBounds = true
        durationBadge.isHidden = true
        thumbnailImageView.addSubview(durationBadge)
        
        // Title
        titleLabel.frame = NSRect(x: 78, y: 27, width: 170, height: 18)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.autoresizingMask = [.width]
        addSubview(titleLabel)
        
        // Subtitle
        subtitleLabel.frame = NSRect(x: 78, y: 9, width: 170, height: 15)
        subtitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.autoresizingMask = [.width]
        addSubview(subtitleLabel)
    }
    
    func configure(url: URL, title: String, subtitle: String) {
        self.currentURL = url
        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle
        durationBadge.isHidden = true
        
        // Set placeholder icon first
        let placeholder = NSImage(systemSymbolName: "film", accessibilityDescription: nil)
        thumbnailImageView.image = placeholder
        thumbnailImageView.contentTintColor = .tertiaryLabelColor
        
        // Asynchronously load real video frame
        VideoThumbnailProvider.shared.thumbnail(for: url) { [weak self] img in
            guard let self = self, self.currentURL == url else { return }
            if let img = img {
                self.thumbnailImageView.image = img
                self.thumbnailImageView.contentTintColor = nil
            }
        }
        
        // Asynchronously load duration
        Task {
            let asset = AVURLAsset(url: url)
            let duration = (try? await asset.load(.duration)) ?? .zero
            let secs = Int(CMTimeGetSeconds(duration))
            let durStr = String(format: "%02d:%02d", secs / 60, secs % 60)
            let sizeStr = RetentionManager.formattedFileSize(for: url)
            
            await MainActor.run {
                guard self.currentURL == url else { return }
                if secs > 0 {
                    self.durationBadge.stringValue = durStr
                    self.durationBadge.sizeToFit()
                    let badgeW = max(self.durationBadge.frame.width + 6, 28)
                    self.durationBadge.frame = NSRect(x: 58 - badgeW - 3, y: 2, width: badgeW, height: 13)
                    self.durationBadge.isHidden = false
                    self.subtitleLabel.stringValue = "\(durStr)  •  \(sizeStr)"
                }
            }
        }
    }
}

// MARK: - SidebarTableView (Handles right-click selection and keyboard delete)
final class SidebarTableView: NSTableView {
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        if row >= 0 && row < numberOfRows {
            if !isRowSelected(row) {
                selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            return super.menu(for: event)
        }
        return nil
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 { // Delete / Backspace key
            if let windowController = delegate as? RecordingsWindowController {
                windowController.deleteSelected()
                return
            }
        }
        super.keyDown(with: event)
    }
}

