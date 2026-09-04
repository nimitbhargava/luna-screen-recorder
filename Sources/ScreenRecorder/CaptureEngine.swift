import Foundation
import ScreenCaptureKit
import CoreMedia
import AppKit

public enum CaptureTarget {
    case display(SCDisplay)
    case window(SCWindow)
    case area(display: SCDisplay, rect: CGRect)
}

public final class CaptureEngine: NSObject, SCStreamDelegate, SCStreamOutput {
    public static let shared = CaptureEngine()
    
    private var stream: SCStream?
    private var videoEncoder: VideoEncoder?
    private let captureQueue = DispatchQueue(label: "com.screenrecorder.capture", qos: .userInitiated)
    
    private(set) public var isRecording = false
    private(set) public var isPaused = false
    private var currentOutputURL: URL?
    
    public override init() {
        super.init()
    }
    
    public static func fetchShareableContent() async throws -> SCShareableContent {
        return try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    }
    
    public func startCapture(target: CaptureTarget, outputURL: URL) async throws {
        guard !isRecording else {
            throw NSError(domain: "CaptureEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Already recording"])
        }
        
        // Find windows belonging to this app to exclude them from recording (e.g. HUD and overlay)
        let shareableContent = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let myPID = ProcessInfo.processInfo.processIdentifier
        let appWindowsToExclude = shareableContent?.windows.filter {
            $0.owningApplication?.processID == myPID ||
            $0.owningApplication?.applicationName == "Luna" ||
            $0.owningApplication?.applicationName == "ScreenRecorder" ||
            $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
        } ?? []
        
        let filter: SCContentFilter
        let config = SCStreamConfiguration()
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30) // 30 FPS
        config.showsCursor = true
        config.pixelFormat = kCVPixelFormatType_32BGRA
        
        var outputWidth = 1920
        var outputHeight = 1080
        
        switch target {
        case .display(let display):
            filter = SCContentFilter(display: display, excludingWindows: appWindowsToExclude)
            let screenWidth = display.width
            let screenHeight = display.height
            if screenWidth > 2560 {
                outputWidth = screenWidth / 2
                outputHeight = screenHeight / 2
            } else {
                outputWidth = screenWidth
                outputHeight = screenHeight
            }
            config.width = outputWidth
            config.height = outputHeight
            
        case .window(let window):
            filter = SCContentFilter(desktopIndependentWindow: window)
            outputWidth = max(Int(window.frame.width), 320)
            outputHeight = max(Int(window.frame.height), 240)
            config.width = outputWidth
            config.height = outputHeight
            
        case .area(let display, let rect):
            filter = SCContentFilter(display: display, excludingWindows: appWindowsToExclude)
            config.sourceRect = rect
            outputWidth = max(Int(rect.width), 160)
            outputHeight = max(Int(rect.height), 120)
            config.width = outputWidth
            config.height = outputHeight
        }
        
        // Ensure even dimensions for H.264
        outputWidth = (outputWidth / 2) * 2
        outputHeight = (outputHeight / 2) * 2
        config.width = outputWidth
        config.height = outputHeight
        
        let encoder = try VideoEncoder(outputURL: outputURL, width: outputWidth, height: outputHeight, frameRate: 30)
        try encoder.start()
        
        self.videoEncoder = encoder
        self.currentOutputURL = outputURL
        self.isPaused = false
        
        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
        
        try await newStream.startCapture()
        self.stream = newStream
        self.isRecording = true
        print("[CaptureEngine] Started capturing \(outputWidth)x\(outputHeight) to \(outputURL.path)")
    }
    
    public func startCapture(filter: SCContentFilter, outputURL: URL) async throws {
        guard !isRecording else {
            throw NSError(domain: "CaptureEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Already recording"])
        }
        
        let config = SCStreamConfiguration()
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30) // 30 FPS
        config.showsCursor = true
        config.pixelFormat = kCVPixelFormatType_32BGRA
        
        var outputWidth = 1920
        var outputHeight = 1080
        if #available(macOS 14.0, *) {
            outputWidth = max(Int(filter.contentRect.width), 320)
            outputHeight = max(Int(filter.contentRect.height), 240)
        }
        
        if outputWidth > 2560 {
            outputWidth /= 2
            outputHeight /= 2
        }
        
        // Ensure even dimensions for H.264
        outputWidth = (outputWidth / 2) * 2
        outputHeight = (outputHeight / 2) * 2
        config.width = outputWidth
        config.height = outputHeight
        
        let encoder = try VideoEncoder(outputURL: outputURL, width: outputWidth, height: outputHeight, frameRate: 30)
        try encoder.start()
        
        self.videoEncoder = encoder
        self.currentOutputURL = outputURL
        self.isPaused = false
        
        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
        
        try await newStream.startCapture()
        self.stream = newStream
        self.isRecording = true
        print("[CaptureEngine] Started capturing visual filter (\(outputWidth)x\(outputHeight)) to \(outputURL.path)")
    }
    
    public func pauseCapture() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        videoEncoder?.pause()
        print("[CaptureEngine] Capture paused")
    }
    
    public func resumeCapture() {
        guard isRecording, isPaused else { return }
        isPaused = false
        videoEncoder?.resume()
        print("[CaptureEngine] Capture resumed")
    }
    
    public func stopCapture() async throws -> URL {
        guard isRecording, let stream = self.stream, let encoder = self.videoEncoder else {
            throw NSError(domain: "CaptureEngine", code: -2, userInfo: [NSLocalizedDescriptionKey: "No active recording to stop"])
        }
        
        self.isRecording = false
        self.isPaused = false
        try await stream.stopCapture()
        self.stream = nil
        
        let rawURL = try await withCheckedThrowingContinuation { continuation in
            encoder.finish { result in
                switch result {
                case .success(let url):
                    continuation.resume(returning: url)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
        
        // Optimize with faststart & inject silent audio so web/Gemini accept it cleanly
        let finalURL = MediaPostProcessor.shared.remuxForWebCompatibility(inputURL: rawURL)
        return finalURL
    }
    
    // MARK: - SCStreamOutput
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        videoEncoder?.append(sampleBuffer: sampleBuffer)
    }
    
    // MARK: - SCStreamDelegate
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[CaptureEngine] Stream stopped with error: \(error)")
        self.isRecording = false
        self.isPaused = false
    }
}
