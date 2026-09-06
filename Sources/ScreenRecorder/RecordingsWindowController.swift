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

// MARK: - RecordingsWindowController
public final class RecordingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSplitViewDelegate, NSWindowDelegate {
    public static let shared = RecordingsWindowController()
    
    private var recordings: [URL] = []
    private var selectedRecordingURL: URL?
    private var durationCache: [URL: String] = [:]
    
    private var splitView: NSSplitView!
    private var sidebarView: NSView!
    private var detailView: NSView!
    
    private var tableView: NSTableView!
    private var countLabel: NSTextField!
    private var retentionFooterLabel: NSTextField!
    
    private var titleLabel: NSTextField!
    private var subtitleLabel: NSTextField!
    private var playerView: AVPlayerView!
    private var feedbackPill: NSBox!
    private var feedbackLabel: NSTextField!
    private var playerTimeObserver: Any?
    
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
        window.minSize = NSSize(width: 820, height: 520)
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
                showFeedback(message: "✓ File path copied for your LLM (⌘V)", isAccent: true)
            } else {
                hideFeedback()
            }
        } else if !recordings.isEmpty {
            let index = 0
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            selectedRecordingURL = recordings.first
            hideFeedback()
        } else {
            selectedRecordingURL = nil
            hideFeedback()
        }
        
        updatePlayerAndDetails()
        
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
        if isAutoDelete {
            retentionFooterLabel?.stringValue = "15-Day Auto-Delete"
            retentionFooterLabel?.toolTip = "Recordings older than 15 days are automatically removed to save disk space."
        } else {
            retentionFooterLabel?.stringValue = "Auto-Delete Disabled"
            retentionFooterLabel?.toolTip = "Recordings are retained forever until you manually delete them."
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
        
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SidebarColumn"))
        col.resizingMask = .autoresizingMask
        col.width = scrollView.contentSize.width
        tbl.addTableColumn(col)
        tbl.sizeLastColumnToFit()
        
        tbl.dataSource = self
        tbl.delegate = self
        tbl.target = self
        tbl.doubleAction = #selector(tableDoubleClicked)
        
        // Context Menu for right-click desktop experience
        let menu = NSMenu()
        let copyPathItem = NSMenuItem(title: "Copy Path for LLMs", action: #selector(contextCopyPath), keyEquivalent: "")
        copyPathItem.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
        copyPathItem.target = self
        menu.addItem(copyPathItem)
        
        let copyMp4Item = NSMenuItem(title: "Copy MP4", action: #selector(contextCopyMp4), keyEquivalent: "")
        copyMp4Item.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyMp4Item.target = self
        menu.addItem(copyMp4Item)
        
        let copyGifItem = NSMenuItem(title: "Copy GIF", action: #selector(contextCopyGif), keyEquivalent: "")
        copyGifItem.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        copyGifItem.target = self
        menu.addItem(copyGifItem)
        
        let revealItem = NSMenuItem(title: "Reveal in Finder", action: #selector(contextReveal), keyEquivalent: "")
        revealItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        revealItem.target = self
        menu.addItem(revealItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let deleteItem = NSMenuItem(title: "Delete Recording...", action: #selector(contextDelete), keyEquivalent: "")
        deleteItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        deleteItem.target = self
        menu.addItem(deleteItem)
        
        tbl.menu = menu
        
        scrollView.documentView = tbl
        sidebar.addSubview(scrollView)
        self.tableView = tbl
        
        // Footer Bar: Retention status & Open in Finder
        let footerBar = NSView(frame: NSRect(x: 0, y: 0, width: sidebar.frame.width, height: 44))
        footerBar.autoresizingMask = [.width, .maxYMargin]
        
        let divider = NSBox(frame: NSRect(x: 0, y: 43, width: footerBar.frame.width, height: 1))
        divider.boxType = .separator
        divider.autoresizingMask = [.width]
        footerBar.addSubview(divider)
        
        let statusIcon = NSImageView(frame: NSRect(x: 14, y: 14, width: 16, height: 16))
        statusIcon.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        statusIcon.contentTintColor = .secondaryLabelColor
        footerBar.addSubview(statusIcon)
        
        let retLbl = NSTextField(labelWithString: "15-Day Auto-Delete")
        retLbl.frame = NSRect(x: 34, y: 12, width: 140, height: 18)
        retLbl.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        retLbl.textColor = .secondaryLabelColor
        footerBar.addSubview(retLbl)
        self.retentionFooterLabel = retLbl
        
        let finderBtn = NSButton(frame: NSRect(x: footerBar.frame.width - 40, y: 8, width: 28, height: 28))
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
        self.detailView = detail
        
        // Header View: Formatted title, subtitle & feedback pill
        let headerView = NSView(frame: NSRect(x: 28, y: detail.frame.height - 76, width: detail.frame.width - 56, height: 50))
        headerView.autoresizingMask = [.width, .minYMargin]
        
        let mainTitle = NSTextField(labelWithString: "Select a Recording")
        mainTitle.frame = NSRect(x: 0, y: 22, width: headerView.frame.width - 240, height: 24)
        mainTitle.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        mainTitle.lineBreakMode = .byTruncatingTail
        mainTitle.autoresizingMask = [.width]
        headerView.addSubview(mainTitle)
        self.titleLabel = mainTitle
        
        let subTitle = NSTextField(labelWithString: "")
        subTitle.frame = NSRect(x: 0, y: 2, width: headerView.frame.width - 240, height: 18)
        subTitle.font = NSFont.systemFont(ofSize: 12)
        subTitle.textColor = .secondaryLabelColor
        subTitle.lineBreakMode = .byTruncatingMiddle
        subTitle.autoresizingMask = [.width]
        headerView.addSubview(subTitle)
        self.subtitleLabel = subTitle
        
        // Feedback Pill (Apple-style subtle capsule)
        let pill = NSBox(frame: NSRect(x: headerView.frame.width - 230, y: 12, width: 230, height: 28))
        pill.boxType = .custom
        pill.cornerRadius = 14
        pill.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.12)
        pill.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.35)
        pill.borderWidth = 1
        pill.autoresizingMask = [.minXMargin]
        pill.isHidden = true
        
        let pillLbl = NSTextField(labelWithString: "✓ Copied for Antigravity (⌘V)")
        pillLbl.frame = NSRect(x: 10, y: 5, width: 210, height: 16)
        pillLbl.font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        pillLbl.textColor = .controlAccentColor
        pillLbl.alignment = .center
        pill.addSubview(pillLbl)
        
        headerView.addSubview(pill)
        self.feedbackPill = pill
        self.feedbackLabel = pillLbl
        
        detail.addSubview(headerView)
        
        // Native Widescreen Video Player (AVPlayerView)
        let playerY: CGFloat = 88
        let playerHeight = detail.frame.height - 76 - playerY - 16
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
        
        // Action Bar (Bottom)
        let actionBar = NSView(frame: NSRect(x: 28, y: 18, width: detail.frame.width - 56, height: 54))
        actionBar.autoresizingMask = [.width, .maxYMargin]
        
        // Primary CTA: Copy Path for LLMs (Prominent Apple Accent Button)
        let copyPathBtn = NSButton(frame: NSRect(x: 0, y: 0, width: 185, height: 32))
        copyPathBtn.title = "Copy Path for LLMs"
        copyPathBtn.image = NSImage(systemSymbolName: "link", accessibilityDescription: "Copy Path")
        copyPathBtn.imagePosition = .imageLeading
        copyPathBtn.bezelStyle = .rounded
        copyPathBtn.wantsLayer = true
        copyPathBtn.layer?.cornerRadius = 6
        copyPathBtn.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        copyPathBtn.contentTintColor = .white
        copyPathBtn.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        copyPathBtn.keyEquivalent = "\r"
        copyPathBtn.isBordered = false
        copyPathBtn.target = self
        copyPathBtn.action = #selector(copyPathClicked)
        
        // Secondary Actions Group
        let copyMp4Btn = NSButton(frame: NSRect(x: 0, y: 0, width: 105, height: 32))
        copyMp4Btn.title = "Copy MP4"
        copyMp4Btn.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy MP4")
        copyMp4Btn.imagePosition = .imageLeading
        copyMp4Btn.bezelStyle = .rounded
        copyMp4Btn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        copyMp4Btn.target = self
        copyMp4Btn.action = #selector(copyMp4Clicked)
        
        let copyGifBtn = NSButton(frame: NSRect(x: 0, y: 0, width: 100, height: 32))
        copyGifBtn.title = "Copy GIF"
        copyGifBtn.image = NSImage(systemSymbolName: "photo", accessibilityDescription: "Copy GIF")
        copyGifBtn.imagePosition = .imageLeading
        copyGifBtn.bezelStyle = .rounded
        copyGifBtn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        copyGifBtn.target = self
        copyGifBtn.action = #selector(copyGifClicked)
        
        let revealBtn = NSButton(frame: NSRect(x: 0, y: 0, width: 100, height: 32))
        revealBtn.title = "In Finder"
        revealBtn.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "In Finder")
        revealBtn.imagePosition = .imageLeading
        revealBtn.bezelStyle = .rounded
        revealBtn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        revealBtn.target = self
        revealBtn.action = #selector(revealClicked)
        
        let deleteBtn = NSButton(frame: NSRect(x: 0, y: 0, width: 88, height: 32))
        deleteBtn.title = "Delete"
        deleteBtn.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")
        deleteBtn.imagePosition = .imageLeading
        deleteBtn.bezelStyle = .rounded
        deleteBtn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        deleteBtn.contentTintColor = .systemRed
        deleteBtn.target = self
        deleteBtn.action = #selector(deleteClicked)
        
        // NSStackView for automatic leading & trailing distribution without overlap
        let buttonStack = NSStackView()
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8
        buttonStack.alignment = .centerY
        buttonStack.frame = NSRect(x: 0, y: 16, width: actionBar.frame.width, height: 32)
        buttonStack.autoresizingMask = [.width]
        
        buttonStack.addView(copyPathBtn, in: .leading)
        buttonStack.addView(copyMp4Btn, in: .leading)
        buttonStack.addView(copyGifBtn, in: .leading)
        buttonStack.addView(revealBtn, in: .leading)
        buttonStack.addView(deleteBtn, in: .trailing)
        
        actionBar.addSubview(buttonStack)
        
        // Helpful subtitle tip below buttons
        let tipLbl = NSTextField(labelWithString: "Ready for Antigravity. Simply press ⌘V in your prompt to inspect recording.")
        tipLbl.frame = NSRect(x: 2, y: 0, width: actionBar.frame.width - 4, height: 14)
        tipLbl.font = NSFont.systemFont(ofSize: 11)
        tipLbl.textColor = .tertiaryLabelColor
        actionBar.addSubview(tipLbl)
        
        detail.addSubview(actionBar)
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
    
    // MARK: - Feedback Banner
    private func showFeedback(message: String, isAccent: Bool = true) {
        feedbackLabel.stringValue = message
        if isAccent {
            feedbackPill.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.12)
            feedbackPill.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.35)
            feedbackLabel.textColor = .controlAccentColor
        } else {
            feedbackPill.fillColor = NSColor.systemOrange.withAlphaComponent(0.12)
            feedbackPill.borderColor = NSColor.systemOrange.withAlphaComponent(0.35)
            feedbackLabel.textColor = .systemOrange
        }
        feedbackPill.isHidden = false
    }
    
    private func hideFeedback() {
        feedbackPill?.isHidden = true
    }
    
    // MARK: - Detail Updating
    private func updatePlayerAndDetails() {
        guard let url = selectedRecordingURL, FileManager.default.fileExists(atPath: url.path) else {
            titleLabel.stringValue = "No Recording Selected"
            subtitleLabel.stringValue = "Take a recording using ⌘⌥1, ⌘⌥2, or ⌘⌥3"
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
                self.subtitleLabel.stringValue = "\(url.lastPathComponent)  •  \(durStr)  •  \(sizeStr)"
            }
        }
        
        if let observer = playerTimeObserver {
            playerView.player?.removeTimeObserver(observer)
            playerTimeObserver = nil
        }
        
        let player = AVPlayer(url: url)
        self.playerView.player = player
        
        playerTimeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 2), queue: .main) { [weak self] time in
            guard let self = self else { return }
            let curSecs = Int(CMTimeGetSeconds(time))
            let curStr = String(format: "%02d:%02d", curSecs / 60, curSecs % 60)
            let totalSecs = Int(CMTimeGetSeconds(player.currentItem?.duration ?? .zero))
            let totalStr = totalSecs > 0 ? String(format: "%02d:%02d", totalSecs / 60, totalSecs % 60) : "--:--"
            self.subtitleLabel.stringValue = "\(url.lastPathComponent)  •  ⏱ \(curStr) / \(totalStr)  •  \(sizeStr)"
        }
        
        player.play()
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
    public func copyPath(at row: Int) {
        guard row >= 0 && row < recordings.count else { return }
        let url = recordings[row]
        if selectedRecordingURL != url {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            selectedRecordingURL = url
            updatePlayerAndDetails()
        }
        PasteboardManager.shared.copyPathToPasteboard(fileURL: url)
        showFeedback(message: "✓ Copied file path for LLMs (⌘V)")
    }
    
    @objc private func copyPathClicked() {
        if let url = selectedRecordingURL, let row = recordings.firstIndex(of: url) {
            copyPath(at: row)
        } else if tableView.selectedRow >= 0 {
            copyPath(at: tableView.selectedRow)
        }
    }
    
    @objc private func copyMp4Clicked() {
        guard let url = selectedRecordingURL else { return }
        PasteboardManager.shared.copyFileToPasteboard(fileURL: url)
        showFeedback(message: "✓ Copied MP4 file to clipboard")
    }
    
    @objc private func copyGifClicked() {
        guard let url = selectedRecordingURL else { return }
        showFeedback(message: "⏳ Converting to GIF...", isAccent: false)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if let gifURL = MediaPostProcessor.shared.generateGIF(from: url) {
                PasteboardManager.shared.copyGIFToPasteboard(gifURL: gifURL)
                DispatchQueue.main.async {
                    self?.showFeedback(message: "✓ Copied GIF to clipboard")
                }
            } else {
                DispatchQueue.main.async {
                    self?.showFeedback(message: "❌ GIF conversion failed", isAccent: false)
                }
            }
        }
    }
    
    @objc private func revealClicked() {
        guard let url = selectedRecordingURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    public func deleteRecording(at row: Int) {
        guard row >= 0 && row < recordings.count else { return }
        let url = recordings[row]
        let alert = NSAlert()
        alert.messageText = "Delete Recording?"
        alert.informativeText = "Are you sure you want to delete \"\(formattedDateTitle(for: url))\"?"
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
            
            try? FileManager.default.removeItem(at: url)
            let gifURL = url.deletingPathExtension().appendingPathExtension("gif")
            try? FileManager.default.removeItem(at: gifURL)
            
            refreshRecordingsList()
            
            if wasSelected {
                if !recordings.isEmpty {
                    let newIndex = min(row, recordings.count - 1)
                    tableView.selectRowIndexes(IndexSet(integer: newIndex), byExtendingSelection: false)
                    selectedRecordingURL = recordings[newIndex]
                }
            } else if let selURL = selectedRecordingURL, let newIndex = recordings.firstIndex(of: selURL) {
                tableView.selectRowIndexes(IndexSet(integer: newIndex), byExtendingSelection: false)
            }
            
            updatePlayerAndDetails()
            showFeedback(message: "Deleted recording", isAccent: false)
        }
    }
    
    public func deleteSelected() {
        let row = tableView.selectedRow
        guard row >= 0 && row < recordings.count else { return }
        deleteRecording(at: row)
    }
    
    @objc private func deleteClicked() {
        if let url = selectedRecordingURL, let row = recordings.firstIndex(of: url) {
            deleteRecording(at: row)
        } else if tableView.selectedRow >= 0 {
            deleteRecording(at: tableView.selectedRow)
        }
    }
    
    @objc private func openFolderClicked() {
        NSWorkspace.shared.open(RetentionManager.shared.recordingsDirectory)
    }
    
    @objc private func tableDoubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0 && row < recordings.count else { return }
        NSWorkspace.shared.open(recordings[row])
    }
    
    // MARK: - Context Menu Actions
    @objc private func contextCopyPath() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0 && row < recordings.count else { return }
        copyPath(at: row)
    }
    
    @objc private func contextCopyMp4() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0 && row < recordings.count else { return }
        let url = recordings[row]
        PasteboardManager.shared.copyFileToPasteboard(fileURL: url)
        showFeedback(message: "✓ Copied MP4 file to clipboard")
    }
    
    @objc private func contextCopyGif() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0 && row < recordings.count else { return }
        let url = recordings[row]
        showFeedback(message: "⏳ Converting to GIF...", isAccent: false)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if let gifURL = MediaPostProcessor.shared.generateGIF(from: url) {
                PasteboardManager.shared.copyGIFToPasteboard(gifURL: gifURL)
                DispatchQueue.main.async {
                    self?.showFeedback(message: "✓ Copied GIF to clipboard")
                }
            } else {
                DispatchQueue.main.async {
                    self?.showFeedback(message: "❌ GIF conversion failed", isAccent: false)
                }
            }
        }
    }
    
    @objc private func contextReveal() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0 && row < recordings.count else { return }
        let url = recordings[row]
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    @objc private func contextDelete() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0 && row < recordings.count else { return }
        deleteRecording(at: row)
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
        let row = tableView.selectedRow
        guard row >= 0 && row < recordings.count else { return }
        selectedRecordingURL = recordings[row]
        updatePlayerAndDetails()
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
        thumbnailImageView.frame = NSRect(x: 8, y: 7, width: 58, height: 38)
        thumbnailImageView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailImageView.wantsLayer = true
        thumbnailImageView.layer?.cornerRadius = 5
        thumbnailImageView.layer?.masksToBounds = true
        thumbnailImageView.layer?.borderWidth = 0.5
        thumbnailImageView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        thumbnailImageView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
        addSubview(thumbnailImageView)
        
        // Duration Badge on Thumbnail (YouTube/QuickTime style)
        durationBadge.frame = NSRect(x: 23, y: 2, width: 33, height: 13)
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
        titleLabel.frame = NSRect(x: 74, y: 26, width: 170, height: 18)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.autoresizingMask = [.width]
        addSubview(titleLabel)
        
        // Subtitle
        subtitleLabel.frame = NSRect(x: 74, y: 8, width: 170, height: 15)
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

