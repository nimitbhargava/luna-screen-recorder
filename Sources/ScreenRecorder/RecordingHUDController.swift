import AppKit

public final class RecordingHUDController: NSObject {
    public static let shared = RecordingHUDController()
    
    private var window: NSPanel?
    private var timerLabel: NSTextField?
    private var pauseButton: NSButton?
    private var stopButton: NSButton?
    private var statusDot: NSView?
    private var hasCustomPosition = false
    
    public var onTogglePause: (() -> Void)?
    public var onStop: (() -> Void)?
    
    private var isPaused = false
    
    public var hudWindowNumber: Int? {
        return window?.windowNumber
    }
    
    private override init() {
        super.init()
    }
    
    public func prepareWindow() {
        if window == nil {
            createWindow()
        }
    }
    
    public func show(onTogglePause: @escaping () -> Void, onStop: @escaping () -> Void) {
        self.onTogglePause = onTogglePause
        self.onStop = onStop
        self.isPaused = false
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if self.window == nil {
                self.createWindow()
            }
            
            self.updateUI(seconds: 0, isPaused: false)
            self.positionWindow()
            self.startPulseAnimation()
            self.window?.orderFrontRegardless()
        }
    }
    
    public func hide() {
        DispatchQueue.main.async { [weak self] in
            self?.stopPulseAnimation()
            self?.window?.orderOut(nil)
        }
    }
    
    public func updateTimer(seconds: Int, isPaused: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.isPaused = isPaused
            self?.updateUI(seconds: seconds, isPaused: isPaused)
        }
    }
    
    private func positionWindow() {
        guard !hasCustomPosition else { return }
        guard let window = self.window, let screen = NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        let x = screenRect.midX - (window.frame.width / 2)
        let y = screenRect.maxY - 68
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    private func createWindow() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 232, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            self?.hasCustomPosition = true
        }
        
        let visualEffect = NSVisualEffectView(frame: panel.contentView!.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .withinWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 22
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderWidth = 0.5
        visualEffect.layer?.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor
        
        // Red Recording Status Dot with shadow
        let dot = NSView(frame: NSRect(x: 16, y: 17, width: 10, height: 10))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.shadowColor = NSColor.systemRed.cgColor
        dot.layer?.shadowRadius = 4
        dot.layer?.shadowOpacity = 0.8
        dot.layer?.shadowOffset = .zero
        visualEffect.addSubview(dot)
        self.statusDot = dot
        
        // Monospaced SF Pro Timer
        let label = NSTextField(labelWithString: "00:00")
        label.frame = NSRect(x: 32, y: 12, width: 68, height: 20)
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .bold)
        label.textColor = .white
        label.alignment = .left
        visualEffect.addSubview(label)
        self.timerLabel = label
        
        // Subtle divider
        let divider = NSView(frame: NSRect(x: 104, y: 11, width: 1, height: 22))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        visualEffect.addSubview(divider)
        
        // Apple-style Glass Pause / Resume Button
        let pauseBtn = NSButton(frame: NSRect(x: 114, y: 8, width: 34, height: 28))
        pauseBtn.bezelStyle = .inline
        pauseBtn.isBordered = false
        pauseBtn.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "Pause")
        pauseBtn.imagePosition = .imageOnly
        pauseBtn.contentTintColor = .white
        pauseBtn.toolTip = "Pause Recording (⌘⌥P)"
        pauseBtn.target = self
        pauseBtn.action = #selector(pauseClicked)
        visualEffect.addSubview(pauseBtn)
        self.pauseButton = pauseBtn
        
        // Apple-style Stop Button (Pill with stop.fill)
        let stopBtn = NSButton(frame: NSRect(x: 154, y: 7, width: 66, height: 30))
        stopBtn.bezelStyle = .rounded
        stopBtn.title = "Stop"
        stopBtn.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Stop")
        stopBtn.imagePosition = .imageLeading
        stopBtn.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        stopBtn.contentTintColor = .systemRed
        stopBtn.toolTip = "Stop Recording (⌘⌥S)"
        stopBtn.target = self
        stopBtn.action = #selector(stopClicked)
        visualEffect.addSubview(stopBtn)
        self.stopButton = stopBtn
        
        panel.contentView = visualEffect
        self.window = panel
    }
    
    private func startPulseAnimation() {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.duration = 0.8
        pulse.fromValue = 1.0
        pulse.toValue = 0.35
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        statusDot?.layer?.add(pulse, forKey: "dot_pulse")
    }
    
    private func stopPulseAnimation() {
        statusDot?.layer?.removeAnimation(forKey: "dot_pulse")
    }
    
    private func updateUI(seconds: Int, isPaused: Bool) {
        let mins = seconds / 60
        let secs = seconds % 60
        timerLabel?.stringValue = String(format: "%02d:%02d", mins, secs)
        
        if isPaused {
            statusDot?.layer?.backgroundColor = NSColor.systemOrange.cgColor
            statusDot?.layer?.shadowColor = NSColor.systemOrange.cgColor
            statusDot?.layer?.removeAnimation(forKey: "dot_pulse")
            statusDot?.alphaValue = 1.0
            pauseButton?.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Resume")
            pauseButton?.toolTip = "Resume Recording (⌘⌥P)"
        } else {
            statusDot?.layer?.backgroundColor = NSColor.systemRed.cgColor
            statusDot?.layer?.shadowColor = NSColor.systemRed.cgColor
            if statusDot?.layer?.animation(forKey: "dot_pulse") == nil {
                startPulseAnimation()
            }
            pauseButton?.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "Pause")
            pauseButton?.toolTip = "Pause Recording (⌘⌥P)"
        }
    }
    
    @objc private func pauseClicked() {
        onTogglePause?()
    }
    
    @objc private func stopClicked() {
        onStop?()
    }
}
