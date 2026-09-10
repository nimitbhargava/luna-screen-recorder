import AppKit
import ScreenCaptureKit

public final class OverlayWindowController: NSWindowController {
    public typealias SelectionHandler = (CaptureTarget) -> Void
    
    private var selectionHandler: SelectionHandler?
    private var overlayWindows: [NSWindow] = []
    
    public static let shared = OverlayWindowController()
    
    public func startSelection(completion: @escaping SelectionHandler) {
        self.selectionHandler = completion
        dismissAll()
        
        Task { @MainActor in
            do {
                let content = try await CaptureEngine.fetchShareableContent()
                guard let mainDisplay = content.displays.first else {
                    print("[OverlayWindow] Failed to fetch displays for overlay")
                    return
                }
                
                for screen in NSScreen.screens {
                    let window = NSWindow(
                        contentRect: screen.frame,
                        styleMask: [.borderless],
                        backing: .buffered,
                        defer: false
                    )
                    window.level = .floating
                    window.backgroundColor = .clear
                    window.isOpaque = false
                    window.hasShadow = false
                    window.ignoresMouseEvents = false
                    
                    // Match SCDisplay by CGDirectDisplayID or coordinate proximity
                    let screenNum = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
                    let matchingDisplay = content.displays.first(where: {
                        if let screenNum = screenNum, $0.displayID == screenNum { return true }
                        return abs($0.frame.origin.x - screen.frame.origin.x) < 5
                    }) ?? mainDisplay
                    
                    let overlayView = OverlaySelectionView(
                        frame: NSRect(origin: .zero, size: screen.frame.size),
                        screenFrame: screen.frame,
                        display: matchingDisplay
                    ) { [weak self] target in
                        self?.dismissAll()
                        self?.selectionHandler?(target)
                    } onCancel: { [weak self] in
                        self?.dismissAll()
                    }
                    
                    window.contentView = overlayView
                    window.makeKeyAndOrderFront(nil)
                    self.overlayWindows.append(window)
                }
                
                NSApp.activate(ignoringOtherApps: true)
            } catch {
                print("[OverlayWindow] Failed to fetch shareable content: \(error)")
                let nsError = error as NSError
                if nsError.code == -3801 || nsError.domain.contains("ScreenCaptureKit") {
                    PermissionManager.shared.showPermissionAlert()
                }
            }
        }
    }
    
    private func dismissAll() {
        for win in overlayWindows {
            win.orderOut(nil)
        }
        overlayWindows.removeAll()
    }
}

private final class OverlaySelectionView: NSView {
    private let screenFrame: CGRect
    private let display: SCDisplay
    private let onSelect: (CaptureTarget) -> Void
    private let onCancel: () -> Void
    
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    
    init(frame: NSRect, screenFrame: CGRect, display: SCDisplay, onSelect: @escaping (CaptureTarget) -> Void, onCancel: @escaping () -> Void) {
        self.screenFrame = screenFrame
        self.display = display
        self.onSelect = onSelect
        self.onCancel = onCancel
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var acceptsFirstResponder: Bool { true }
    
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }
    
    private var selectionRect: CGRect? {
        guard let start = startPoint, let current = currentPoint else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Dim background
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()
        
        // Clear selected area
        if let rect = selectionRect, rect.width > 2 && rect.height > 2 {
            NSGraphicsContext.current?.compositingOperation = .clear
            NSColor.clear.setFill()
            rect.fill()
            
            // Draw border around cutout
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
            path.lineWidth = 2
            NSColor.systemCyan.setStroke()
            path.stroke()
            
            // Draw dimension badge
            let dimensionText = "\(Int(rect.width)) × \(Int(rect.height))"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let textSize = dimensionText.size(withAttributes: attributes)
            let badgeRect = CGRect(
                x: max(10, min(rect.midX - (textSize.width + 16) / 2, bounds.width - textSize.width - 20)),
                y: rect.minY > 35 ? rect.minY - 26 : rect.maxY + 8,
                width: textSize.width + 16,
                height: 20
            )
            
            let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 5, yRadius: 5)
            NSColor.black.withAlphaComponent(0.75).setFill()
            badgePath.fill()
            
            dimensionText.draw(
                at: CGPoint(x: badgeRect.origin.x + 8, y: badgeRect.origin.y + 2),
                withAttributes: attributes
            )
        }
        
        // Draw instructions at top
        let tipText = "Drag to select area • Click to record this screen • Esc to cancel"
        let tipAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let tipSize = tipText.size(withAttributes: tipAttributes)
        let tipBadgeRect = CGRect(
            x: (bounds.width - tipSize.width - 24) / 2,
            y: bounds.height - 45,
            width: tipSize.width + 24,
            height: 28
        )
        let tipPath = NSBezierPath(roundedRect: tipBadgeRect, xRadius: 7, yRadius: 7)
        NSColor.black.withAlphaComponent(0.8).setFill()
        tipPath.fill()
        tipText.draw(at: CGPoint(x: tipBadgeRect.origin.x + 12, y: tipBadgeRect.origin.y + 5), withAttributes: tipAttributes)
    }
    
    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        // If the user simply clicked or barely dragged (< 15pt), treat as selecting the entire display
        let isClick: Bool
        if let rect = selectionRect {
            isClick = (rect.width < 15 && rect.height < 15)
        } else {
            isClick = true
        }
        
        if isClick {
            print("[OverlayWindow] User clicked screen \(display.displayID): recording entire screen")
            onSelect(.display(display))
            return
        }
        
        guard let rect = selectionRect, rect.width >= 20 && rect.height >= 20 else {
            startPoint = nil
            currentPoint = nil
            needsDisplay = true
            return
        }
        
        // Convert AppKit (bottom-left) to ScreenCaptureKit coordinates (top-left of display)
        let screenHeight = screenFrame.height
        let sckY = screenHeight - (rect.origin.y + rect.height)
        let sckX = rect.origin.x
        let sckRect = CGRect(x: max(0, sckX), y: max(0, sckY), width: rect.width, height: rect.height)
        
        onSelect(.area(display: display, rect: sckRect))
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            onCancel()
        } else {
            super.keyDown(with: event)
        }
    }
}
