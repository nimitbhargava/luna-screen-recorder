import AppKit

public final class ToastHUDController: NSObject {
    public static let shared = ToastHUDController()
    
    private var window: NSPanel?
    private var titleLabel: NSTextField?
    private var messageLabel: NSTextField?
    private var iconView: NSImageView?
    private var dismissTimer: Timer?
    private var currentFileURL: URL?
    
    private override init() {
        super.init()
    }
    
    public func show(
        title: String = "Recording URL Copied",
        message: String = "Ready to paste (⌘V) into your LLM",
        fileURL: URL? = nil
    ) {
        self.currentFileURL = fileURL
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.dismissTimer?.invalidate()
            self.dismissTimer = nil
            
            if self.window == nil {
                self.createWindow()
            }
            
            self.titleLabel?.stringValue = title
            self.messageLabel?.stringValue = message
            
            guard let window = self.window, let screen = NSScreen.main else { return }
            let screenRect = screen.visibleFrame
            let toastWidth: CGFloat = 390
            let toastHeight: CGFloat = 48
            let targetX = screenRect.midX - (toastWidth / 2)
            let targetY = screenRect.maxY - 70
            
            window.setFrame(NSRect(x: targetX, y: targetY + 12, width: toastWidth, height: toastHeight), display: true)
            window.alphaValue = 0.0
            window.orderFrontRegardless()
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(NSRect(x: targetX, y: targetY, width: toastWidth, height: toastHeight), display: true)
                window.animator().alphaValue = 1.0
            }
            
            self.dismissTimer = Timer.scheduledTimer(withTimeInterval: 3.2, repeats: false) { [weak self] _ in
                self?.hide()
            }
        }
    }
    
    public func hide() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let window = self.window else { return }
            self.dismissTimer?.invalidate()
            self.dismissTimer = nil
            
            guard let screen = NSScreen.main else {
                window.orderOut(nil)
                return
            }
            let screenRect = screen.visibleFrame
            let targetX = screenRect.midX - (window.frame.width / 2)
            let targetY = screenRect.maxY - 58
            
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                window.animator().setFrame(NSRect(x: targetX, y: targetY, width: window.frame.width, height: window.frame.height), display: true)
                window.animator().alphaValue = 0.0
            }, completionHandler: {
                window.orderOut(nil)
            })
        }
    }
    
    private func createWindow() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        
        let visualEffect = NSVisualEffectView(frame: panel.contentView!.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .withinWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 24
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderWidth = 0.5
        visualEffect.layer?.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor
        
        // Icon: Checkmark circle fill in vibrant system green
        let icon = NSImageView(frame: NSRect(x: 16, y: 12, width: 24, height: 24))
        icon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Copied")
        icon.contentTintColor = .systemGreen
        visualEffect.addSubview(icon)
        self.iconView = icon
        
        // Title (Bold)
        let title = NSTextField(labelWithString: "Recording URL Copied")
        title.frame = NSRect(x: 48, y: 24, width: 260, height: 17)
        title.font = NSFont.systemFont(ofSize: 12.5, weight: .bold)
        title.textColor = .white
        visualEffect.addSubview(title)
        self.titleLabel = title
        
        // Message / Subtitle
        let message = NSTextField(labelWithString: "Ready to paste (⌘V) into your LLM")
        message.frame = NSRect(x: 48, y: 8, width: 260, height: 15)
        message.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        message.textColor = NSColor.white.withAlphaComponent(0.82)
        visualEffect.addSubview(message)
        self.messageLabel = message
        
        // Trailing "View" Pill Button
        let openBtn = NSButton(frame: NSRect(x: 316, y: 11, width: 58, height: 26))
        openBtn.title = "View"
        openBtn.bezelStyle = .inline
        openBtn.isBordered = false
        openBtn.wantsLayer = true
        openBtn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        openBtn.layer?.cornerRadius = 13
        openBtn.layer?.masksToBounds = true
        openBtn.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        openBtn.contentTintColor = .white
        openBtn.target = self
        openBtn.action = #selector(viewClicked)
        visualEffect.addSubview(openBtn)
        
        // Click anywhere to view
        let click = NSClickGestureRecognizer(target: self, action: #selector(toastClicked))
        visualEffect.addGestureRecognizer(click)
        
        panel.contentView = visualEffect
        self.window = panel
    }
    
    @objc private func viewClicked() {
        toastClicked()
    }
    
    @objc private func toastClicked() {
        if let url = currentFileURL {
            RecordingsWindowController.shared.show(with: url)
        } else {
            RecordingsWindowController.shared.show()
        }
        hide()
    }
}
