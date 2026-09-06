import AppKit
import ApplicationServices

// MARK: - InteractionEvent Data Model
public struct InteractionEvent: Codable, Sendable {
    public let timestamp: String
    public let timeSec: Double
    public let type: String
    public let x: Int?
    public let y: Int?
    public let appName: String
    public let windowTitle: String?
    public let elementRole: String?
    public let elementTitle: String?
    public let elementValue: String?
    public let webURL: String?
    public let keyModifiers: String?
    
    public var summaryDescription: String {
        switch type {
        case "app_switch":
            let win = windowTitle != nil && !windowTitle!.isEmpty ? " (\"\(windowTitle!)\")" : ""
            return "Switched to \(appName)\(win)"
        case "right_click":
            var desc = "Right-click"
            if let role = elementRole, let title = elementTitle, !title.isEmpty {
                desc += " on \(role) \"\(title)\""
            } else if let role = elementRole {
                desc += " on \(role)"
            }
            if let x = x, let y = y {
                desc += " at (\(x), \(y))"
            }
            return "\(appName): \(desc)"
        default:
            var desc = type == "double_click" ? "Double-click" : "Left-click"
            if let role = elementRole, let title = elementTitle, !title.isEmpty {
                desc += " on \(role) \"\(title)\""
            } else if let role = elementRole {
                desc += " on \(role)"
            }
            if let x = x, let y = y {
                desc += " at (\(x), \(y))"
            }
            if let mod = keyModifiers, !mod.isEmpty {
                desc += " with \(mod)"
            }
            return "\(appName): \(desc)"
        }
    }
}

// MARK: - InteractionTracker
public final class InteractionTracker: NSObject, @unchecked Sendable {
    public static let shared = InteractionTracker()
    
    private var eventMonitor: Any?
    private var appSwitchObserver: NSObjectProtocol?
    private var startTime: Date?
    private var recordedEvents: [InteractionEvent] = []
    private var currentOutputURL: URL?
    private let trackerQueue = DispatchQueue(label: "com.screenrecorder.tracker", qos: .userInitiated)
    private var lastCapturedURL: String?
    private var activeAppName: String = ""
    
    private override init() {
        super.init()
    }
    
    @discardableResult
    public static func checkAccessibilityPermission(prompt: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    @MainActor
    public func startSession(outputURL: URL) {
        _ = stopSession()
        _ = InteractionTracker.checkAccessibilityPermission(prompt: true)
        
        self.startTime = Date()
        self.currentOutputURL = outputURL
        self.lastCapturedURL = nil
        self.activeAppName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Finder"
        trackerQueue.sync {
            self.recordedEvents = []
        }
        
        // Start visual click ripple overlay
        ClickRippleOverlay.shared.start()
        
        // Initial URL if starting on browser
        self.lastCapturedURL = getBrowserURL(appName: activeAppName)
        
        // Global mouse click monitor
        self.eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            self?.handleMouseEvent(event)
        }
        
        // App switch notification
        self.appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            self?.handleAppSwitch(notif)
        }
        
        print("[InteractionTracker] Session started for \(outputURL.lastPathComponent)")
    }
    
    @MainActor
    public func stopSession() -> (eventsURL: URL?, promptMarkdown: String) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            self.eventMonitor = nil
        }
        if let observer = appSwitchObserver {
            NotificationCenter.default.removeObserver(observer)
            self.appSwitchObserver = nil
        }
        ClickRippleOverlay.shared.stop()
        
        guard let outputURL = currentOutputURL else {
            return (nil, "")
        }
        
        var finalEvents: [InteractionEvent] = []
        trackerQueue.sync {
            finalEvents = self.recordedEvents
        }
        
        // Save events to JSON
        let eventsURL = outputURL.deletingPathExtension().appendingPathExtension("events.json")
        let promptURL = outputURL.deletingPathExtension().appendingPathExtension("prompt.md")
        
        let prompt = generatePromptMarkdown(videoURL: outputURL, events: finalEvents)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(finalEvents) {
            try? data.write(to: eventsURL)
            print("[InteractionTracker] Saved \(finalEvents.count) events to \(eventsURL.path)")
        }
        try? prompt.data(using: .utf8)?.write(to: promptURL)
        
        return (eventsURL, prompt)
    }
    
    public func getEvents() -> [InteractionEvent] {
        var events: [InteractionEvent] = []
        trackerQueue.sync {
            events = self.recordedEvents
        }
        return events
    }
    
    // MARK: - Event Handlers
    private func handleMouseEvent(_ event: NSEvent) {
        guard let start = startTime else { return }
        let now = Date()
        let timeSec = now.timeIntervalSince(start)
        let mins = Int(timeSec) / 60
        let secs = Int(timeSec) % 60
        let timeFormatted = String(format: "%02d:%02d", mins, secs)
        
        let screenPoint = NSEvent.mouseLocation
        let isRight = (event.type == .rightMouseDown)
        let isDouble = (event.clickCount > 1)
        let typeStr = isRight ? "right_click" : (isDouble ? "double_click" : "click")
        
        // Show visual ripple immediately on main thread
        DispatchQueue.main.async {
            ClickRippleOverlay.shared.showRipple(at: screenPoint, isRightClick: isRight)
        }
        
        // Gather modifiers
        var modifiers: [String] = []
        if event.modifierFlags.contains(.command) { modifiers.append("⌘") }
        if event.modifierFlags.contains(.option) { modifiers.append("⌥") }
        if event.modifierFlags.contains(.shift) { modifiers.append("⇧") }
        if event.modifierFlags.contains(.control) { modifiers.append("⌃") }
        let modStr = modifiers.isEmpty ? nil : modifiers.joined()
        
        trackerQueue.async { [weak self] in
            guard let self = self else { return }
            
            let frontApp = DispatchQueue.main.sync {
                NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
            }
            let webURL = self.getBrowserURL(appName: frontApp)
            if let u = webURL {
                self.lastCapturedURL = u
            }
            
            let elementInfo = self.getElementInfo(at: screenPoint)
            
            let interaction = InteractionEvent(
                timestamp: timeFormatted,
                timeSec: Double(round(timeSec * 10) / 10),
                type: typeStr,
                x: Int(screenPoint.x),
                y: Int(screenPoint.y),
                appName: frontApp,
                windowTitle: elementInfo.windowTitle,
                elementRole: elementInfo.role,
                elementTitle: elementInfo.title,
                elementValue: elementInfo.value,
                webURL: webURL ?? self.lastCapturedURL,
                keyModifiers: modStr
            )
            
            self.recordedEvents.append(interaction)
        }
    }
    
    private func handleAppSwitch(_ notification: Notification) {
        guard let start = startTime else { return }
        let now = Date()
        let timeSec = now.timeIntervalSince(start)
        let mins = Int(timeSec) / 60
        let secs = Int(timeSec) % 60
        let timeFormatted = String(format: "%02d:%02d", mins, secs)
        
        let app = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.localizedName ?? "Unknown"
        self.activeAppName = app
        let webURL = getBrowserURL(appName: app)
        if let u = webURL {
            self.lastCapturedURL = u
        }
        
        let interaction = InteractionEvent(
            timestamp: timeFormatted,
            timeSec: Double(round(timeSec * 10) / 10),
            type: "app_switch",
            x: nil,
            y: nil,
            appName: app,
            windowTitle: nil,
            elementRole: nil,
            elementTitle: nil,
            elementValue: nil,
            webURL: webURL ?? self.lastCapturedURL,
            keyModifiers: nil
        )
        
        trackerQueue.async { [weak self] in
            self?.recordedEvents.append(interaction)
        }
    }
    
    // MARK: - Accessibility Resolution
    private func getElementInfo(at screenPoint: NSPoint) -> (role: String?, title: String?, value: String?, windowTitle: String?) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080
        let axY = primaryHeight - screenPoint.y
        let systemWide = AXUIElementCreateSystemWide()
        
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(screenPoint.x), Float(axY), &element) == .success,
              let el = element else {
            return (nil, nil, nil, nil)
        }
        
        var roleVal: AnyObject?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleVal)
        let role = cleanRoleName(roleVal as? String)
        
        var titleVal: AnyObject?
        AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &titleVal)
        if titleVal == nil {
            AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &titleVal)
        }
        
        var valueVal: AnyObject?
        AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &valueVal)
        
        // Climb parent hierarchy for label if current title is empty
        var currentEl = el
        var resolvedTitle: String? = titleVal as? String
        var windowTitle: String?
        
        for _ in 0..<4 {
            var parent: AnyObject?
            if AXUIElementCopyAttributeValue(currentEl, kAXParentAttribute as CFString, &parent) == .success,
               let p = parent {
                let pEl = p as! AXUIElement
                
                var pRole: AnyObject?
                AXUIElementCopyAttributeValue(pEl, kAXRoleAttribute as CFString, &pRole)
                if (pRole as? String) == (kAXWindowRole as String) {
                    var wTitle: AnyObject?
                    AXUIElementCopyAttributeValue(pEl, kAXTitleAttribute as CFString, &wTitle)
                    windowTitle = wTitle as? String
                }
                
                if resolvedTitle == nil || resolvedTitle?.isEmpty == true {
                    var pTitle: AnyObject?
                    AXUIElementCopyAttributeValue(pEl, kAXTitleAttribute as CFString, &pTitle)
                    if let pt = pTitle as? String, !pt.isEmpty {
                        resolvedTitle = pt
                    }
                }
                currentEl = pEl
            } else {
                break
            }
        }
        
        return (role, resolvedTitle, valueVal as? String, windowTitle)
    }
    
    private func cleanRoleName(_ rawRole: String?) -> String? {
        guard let role = rawRole else { return nil }
        switch role {
        case "AXButton": return "Button"
        case "AXTextField": return "TextField"
        case "AXTextArea": return "TextArea"
        case "AXLink": return "Link"
        case "AXPopUpButton": return "Dropdown"
        case "AXCheckBox": return "Checkbox"
        case "AXRadioButton": return "Radio"
        case "AXMenuItem": return "Menu Item"
        case "AXRow": return "Table Row"
        case "AXStaticText": return "Text"
        case "AXImage": return "Image"
        case "AXTabGroup", "AXRadioButtonTab": return "Tab"
        default:
            if role.hasPrefix("AX") {
                return String(role.dropFirst(2))
            }
            return role
        }
    }
    
    // MARK: - Browser URL Detection
    public func getBrowserURL(appName: String) -> String? {
        let scriptText: String
        switch appName.lowercased() {
        case let s where s.contains("chrome"):
            scriptText = "tell application \"Google Chrome\" to if (count of windows) > 0 then return URL of active tab of front window"
        case let s where s.contains("safari"):
            scriptText = "tell application \"Safari\" to if (count of documents) > 0 then return URL of front document"
        case let s where s.contains("brave"):
            scriptText = "tell application \"Brave Browser\" to if (count of windows) > 0 then return URL of active tab of front window"
        case let s where s.contains("arc"):
            scriptText = "tell application \"Arc\" to if (count of windows) > 0 then return URL of active tab of front window"
        case let s where s.contains("edge"):
            scriptText = "tell application \"Microsoft Edge\" to if (count of windows) > 0 then return URL of active tab of front window"
        default:
            return nil
        }
        
        var error: NSDictionary?
        if let script = NSAppleScript(source: scriptText),
           let output = script.executeAndReturnError(&error).stringValue,
           output.hasPrefix("http") {
            return output
        }
        return nil
    }
    
    // MARK: - Prompt Generation
    public func generatePromptMarkdown(videoURL: URL, events: [InteractionEvent]? = nil, keyframePaths: [String] = [], speechTranscript: String? = nil) -> String {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let mainScreen = NSScreen.screens.first?.frame.size ?? .zero
        let mainScale = NSScreen.screens.first?.backingScaleFactor ?? 2.0
        let targetEvents = events ?? getEvents()
        
        var lines: [String] = []
        lines.append(videoURL.path)
        lines.append("")
        lines.append("### Screen Recording Context & Interaction Log")
        lines.append("- **Video File**: `\(videoURL.path)`")
        if let url = lastCapturedURL {
            lines.append("- **Target Webpage**: `\(url)`")
        }
        lines.append("- **Environment**: macOS (\(osVersion)) | \(Int(mainScreen.width))×\(Int(mainScreen.height)) @ \(Int(mainScale))x")
        
        if let speech = speechTranscript, !speech.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append("### Voice Narration Transcript:")
            lines.append("> \"\(speech)\"")
        }
        
        if !keyframePaths.isEmpty {
            lines.append("")
            lines.append("### Keyframe Snapshots (Apple Vision Saliency):")
            for (idx, path) in keyframePaths.enumerated() {
                lines.append("\(idx + 1). `\(path)`")
            }
        }
        
        if !targetEvents.isEmpty {
            lines.append("")
            lines.append("### User Action Steps:")
            for (idx, event) in targetEvents.enumerated() {
                lines.append("\(idx + 1). `\(event.timestamp)` — \(event.summaryDescription)")
            }
        }
        
        return lines.joined(separator: "\n")
    }
}
