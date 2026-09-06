import AppKit
import QuartzCore

public final class ClickRippleOverlay: NSObject {
    public static let shared = ClickRippleOverlay()
    
    private var overlayWindows: [NSWindow] = []
    private var isRunning = false
    
    private override init() {
        super.init()
    }
    
    @MainActor
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        dismiss()
        
        for screen in NSScreen.screens {
            let win = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            win.title = "LunaClickRippleOverlay"
            win.level = .floating
            win.backgroundColor = .clear
            win.isOpaque = false
            win.hasShadow = false
            win.ignoresMouseEvents = true
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            win.sharingType = .readOnly
            
            let view = NSView(frame: win.contentView!.bounds)
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.clear.cgColor
            win.contentView = view
            
            win.orderFront(nil)
            overlayWindows.append(win)
        }
    }
    
    @MainActor
    public func stop() {
        isRunning = false
        dismiss()
    }
    
    @MainActor
    private func dismiss() {
        for win in overlayWindows {
            win.orderOut(nil)
        }
        overlayWindows.removeAll()
    }
    
    @MainActor
    public func showRipple(at screenPoint: NSPoint, isRightClick: Bool = false) {
        guard isRunning else { return }
        
        // Find matching window containing the screen point
        for win in overlayWindows {
            if win.frame.contains(screenPoint) {
                guard let contentView = win.contentView, let rootLayer = contentView.layer else { continue }
                
                let localPoint = win.convertPoint(fromScreen: screenPoint)
                createRippleLayer(in: rootLayer, at: localPoint, isRightClick: isRightClick)
                break
            }
        }
    }
    
    @MainActor
    private func createRippleLayer(in parentLayer: CALayer, at point: CGPoint, isRightClick: Bool) {
        let initialRadius: CGFloat = 8
        let finalRadius: CGFloat = 26
        let duration: CFTimeInterval = 0.32
        
        // Outer expanding ring
        let ringLayer = CAShapeLayer()
        ringLayer.frame = CGRect(x: point.x - finalRadius, y: point.y - finalRadius, width: finalRadius * 2, height: finalRadius * 2)
        ringLayer.fillColor = NSColor.clear.cgColor
        
        let strokeColor = isRightClick
            ? NSColor.systemOrange.cgColor
            : NSColor.controlAccentColor.cgColor
        ringLayer.strokeColor = strokeColor
        ringLayer.lineWidth = 2.5
        
        let initialPath = CGPath(ellipseIn: CGRect(
            x: finalRadius - initialRadius,
            y: finalRadius - initialRadius,
            width: initialRadius * 2,
            height: initialRadius * 2
        ), transform: nil)
        
        let finalPath = CGPath(ellipseIn: CGRect(
            x: 0,
            y: 0,
            width: finalRadius * 2,
            height: finalRadius * 2
        ), transform: nil)
        
        ringLayer.path = initialPath
        parentLayer.addSublayer(ringLayer)
        
        // Center dot
        let dotRadius: CGFloat = 4
        let dotLayer = CAShapeLayer()
        dotLayer.frame = CGRect(x: point.x - dotRadius, y: point.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
        dotLayer.fillColor = strokeColor
        dotLayer.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: dotRadius * 2, height: dotRadius * 2), transform: nil)
        parentLayer.addSublayer(dotLayer)
        
        // Animations
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            ringLayer.removeFromSuperlayer()
            dotLayer.removeFromSuperlayer()
        }
        
        let pathAnim = CABasicAnimation(keyPath: "path")
        pathAnim.fromValue = initialPath
        pathAnim.toValue = finalPath
        pathAnim.duration = duration
        pathAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        
        let opacityAnim = CABasicAnimation(keyPath: "opacity")
        opacityAnim.fromValue = 0.95
        opacityAnim.toValue = 0.0
        opacityAnim.duration = duration
        opacityAnim.timingFunction = CAMediaTimingFunction(name: .easeIn)
        
        let widthAnim = CABasicAnimation(keyPath: "lineWidth")
        widthAnim.fromValue = 3.0
        widthAnim.toValue = 1.0
        widthAnim.duration = duration
        
        ringLayer.add(pathAnim, forKey: "path")
        ringLayer.add(opacityAnim, forKey: "opacity")
        ringLayer.add(widthAnim, forKey: "lineWidth")
        
        let dotFade = CABasicAnimation(keyPath: "opacity")
        dotFade.fromValue = 0.9
        dotFade.toValue = 0.0
        dotFade.duration = duration * 0.75
        dotFade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        dotLayer.add(dotFade, forKey: "opacity")
        
        CATransaction.commit()
    }
}
