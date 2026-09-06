import Foundation
import AVFoundation
import AppKit

public final class MicrophoneManager: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    public static let shared = MicrophoneManager()
    
    private let defaultsKey = "LunaSelectedMicrophoneUID"
    private var captureSession: AVCaptureSession?
    private var audioOutput: AVCaptureAudioDataOutput?
    private let captureQueue = DispatchQueue(label: "com.luna.microphoneCapture", qos: .userInitiated)
    
    private var sampleBufferCallback: ((CMSampleBuffer) -> Void)?
    private(set) public var isCapturing = false
    private var isPaused = false
    
    public static let selectionDidChangeNotification = Notification.Name("LunaMicrophoneSelectionDidChange")
    
    private override init() {
        super.init()
        setupDeviceNotifications()
    }
    
    // MARK: - Device Discovery
    public func availableDevices() -> [AVCaptureDevice] {
        if #available(macOS 14.0, *) {
            let session = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone, .external],
                mediaType: .audio,
                position: .unspecified
            )
            return session.devices.filter { $0.isConnected }
        } else {
            let session = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInMicrophone, .externalUnknown],
                mediaType: .audio,
                position: .unspecified
            )
            return session.devices.filter { $0.isConnected }
        }
    }
    
    private func setupDeviceNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceListChanged),
            name: AVCaptureDevice.wasConnectedNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceListChanged),
            name: AVCaptureDevice.wasDisconnectedNotification,
            object: nil
        )
    }
    
    @objc private func deviceListChanged(_ notification: Notification) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.selectionDidChangeNotification, object: nil)
        }
    }
    
    // MARK: - Selected Device & Persistence
    public var selectedDeviceUID: String? {
        get {
            return UserDefaults.standard.string(forKey: defaultsKey)
        }
        set {
            if let val = newValue {
                UserDefaults.standard.set(val, forKey: defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: defaultsKey)
            }
            UserDefaults.standard.synchronize()
            
            // If currently recording, switch capture device dynamically on the fly
            if isCapturing {
                reconfigureActiveSession()
            }
            
            NotificationCenter.default.post(name: Self.selectionDidChangeNotification, object: nil)
        }
    }
    
    public var isMuted: Bool {
        get {
            return selectedDeviceUID == "none"
        }
        set {
            if newValue {
                selectedDeviceUID = "none"
            } else {
                selectedDeviceUID = nil // revert to system default
            }
        }
    }
    
    public var currentDevice: AVCaptureDevice? {
        if isMuted { return nil }
        
        let devices = availableDevices()
        if let savedUID = selectedDeviceUID, savedUID != "system_default" && savedUID != "none" {
            if let matched = devices.first(where: { $0.uniqueID == savedUID }) {
                return matched
            }
        }
        
        // Fallback to system default audio input device
        return AVCaptureDevice.default(for: .audio)
    }
    
    public var currentDeviceName: String {
        if isMuted {
            return "Muted"
        }
        if let device = currentDevice {
            return device.localizedName
        }
        return "No Microphone"
    }
    
    public func selectDevice(uid: String?) {
        self.selectedDeviceUID = uid
        print("[MicrophoneManager] Selected microphone: \(currentDeviceName) (UID: \(uid ?? "default"))")
    }
    
    // MARK: - Audio Capture
    public func startCapture(onSampleBuffer: @escaping (CMSampleBuffer) -> Void) throws {
        guard !isMuted else {
            print("[MicrophoneManager] Microphone is muted, skipping capture")
            return
        }
        
        guard let device = currentDevice else {
            print("[MicrophoneManager] No audio device available to capture")
            return
        }
        
        stopCapture()
        self.sampleBufferCallback = onSampleBuffer
        self.isPaused = false
        
        let session = AVCaptureSession()
        session.beginConfiguration()
        
        let input = try AVCaptureDeviceInput(device: device)
        if session.canAddInput(input) {
            session.addInput(input)
        } else {
            session.commitConfiguration()
            throw NSError(domain: "MicrophoneManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot add audio input to capture session"])
        }
        
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: captureQueue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        } else {
            session.commitConfiguration()
            throw NSError(domain: "MicrophoneManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Cannot add audio data output to capture session"])
        }
        
        session.commitConfiguration()
        session.startRunning()
        
        self.captureSession = session
        self.audioOutput = output
        self.isCapturing = true
        print("[MicrophoneManager] Started audio capture with: \(device.localizedName)")
    }
    
    public func pause() {
        self.isPaused = true
    }
    
    public func resume() {
        self.isPaused = false
    }
    
    public func stopCapture() {
        guard isCapturing || captureSession != nil else { return }
        captureSession?.stopRunning()
        captureSession = nil
        audioOutput = nil
        sampleBufferCallback = nil
        isCapturing = false
        isPaused = false
        print("[MicrophoneManager] Stopped audio capture")
    }
    
    private func reconfigureActiveSession() {
        guard let session = captureSession else { return }
        
        session.beginConfiguration()
        // Remove existing input
        for input in session.inputs {
            session.removeInput(input)
        }
        
        if isMuted {
            session.commitConfiguration()
            print("[MicrophoneManager] Dynamically muted active recording")
            return
        }
        
        if let newDevice = currentDevice, let newInput = try? AVCaptureDeviceInput(device: newDevice) {
            if session.canAddInput(newInput) {
                session.addInput(newInput)
                print("[MicrophoneManager] Dynamically switched active mic to: \(newDevice.localizedName)")
            }
        }
        
        session.commitConfiguration()
    }
    
    // MARK: - AVCaptureAudioDataOutputSampleBufferDelegate
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isCapturing, !isPaused, !isMuted else { return }
        sampleBufferCallback?(sampleBuffer)
    }
    
    // MARK: - UI Menu Builder
    public func buildMenu(onSelect: (() -> Void)? = nil) -> NSMenu {
        let menu = NSMenu()
        
        // Header
        let headerItem = NSMenuItem(title: "Microphone Input", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(NSMenuItem.separator())
        
        let devices = availableDevices()
        let defaultDevice = AVCaptureDevice.default(for: .audio)
        let savedUID = selectedDeviceUID
        let isCurrentMuted = isMuted
        
        // System Default Option
        let defaultTitle = defaultDevice != nil ? "System Default (\(defaultDevice!.localizedName))" : "System Default"
        let defaultItem = NSMenuItem(title: defaultTitle, action: #selector(menuItemSelected(_:)), keyEquivalent: "")
        defaultItem.target = self
        defaultItem.representedObject = "system_default"
        defaultItem.state = (!isCurrentMuted && (savedUID == nil || savedUID == "system_default")) ? .on : .off
        defaultItem.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)
        menu.addItem(defaultItem)
        
        if !devices.isEmpty {
            menu.addItem(NSMenuItem.separator())
            
            for device in devices {
                let item = NSMenuItem(title: device.localizedName, action: #selector(menuItemSelected(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = device.uniqueID
                
                // State is ON if explicitly selected
                let isExplicit = (!isCurrentMuted && savedUID == device.uniqueID)
                item.state = isExplicit ? .on : .off
                
                let symbol = device.localizedName.lowercased().contains("airpod") ? "airpodspro" :
                             device.localizedName.lowercased().contains("iphone") ? "iphone" : "mic"
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage(systemSymbolName: "mic", accessibilityDescription: nil)
                
                menu.addItem(item)
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Mute / Off option
        let muteItem = NSMenuItem(title: "Mute / No Audio", action: #selector(menuItemSelected(_:)), keyEquivalent: "")
        muteItem.target = self
        muteItem.representedObject = "none"
        muteItem.state = isCurrentMuted ? .on : .off
        muteItem.image = NSImage(systemSymbolName: "mic.slash", accessibilityDescription: nil)
        menu.addItem(muteItem)
        
        // Store onSelect closure
        self.lastOnSelect = onSelect
        
        return menu
    }
    
    private var lastOnSelect: (() -> Void)?
    
    @objc private func menuItemSelected(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        
        if uid == "system_default" {
            selectDevice(uid: nil)
        } else {
            selectDevice(uid: uid)
        }
        
        lastOnSelect?()
    }
}
