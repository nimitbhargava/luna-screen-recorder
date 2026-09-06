import Foundation
import AVFoundation
import Vision
import AppKit

public final class KeyframeExtractor {
    public static let shared = KeyframeExtractor()
    
    private init() {}
    
    /// Extracts the most salient and action-relevant keyframes from the recording
    /// using Apple Vision feature prints and user interaction click timestamps.
    public func extractKeyframes(videoURL: URL, events: [InteractionEvent], maxFrames: Int = 6) async -> [URL] {
        let asset = AVURLAsset(url: videoURL)
        guard let durationTime = try? await asset.load(.duration) else { return [] }
        let totalDuration = CMTimeGetSeconds(durationTime)
        guard totalDuration > 0.5 else { return [] }
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.maximumSize = CGSize(width: 1920, height: 1080)
        
        // Target timestamps: user click events + distributed scene probes
        var targetTimestamps: [Double] = []
        
        // 1. Frame immediately after each click (approx 0.15s to capture the reaction)
        for event in events {
            if event.type != "app_switch" {
                let targetSec = min(max(event.timeSec + 0.15, 0.1), totalDuration - 0.1)
                if !targetTimestamps.contains(where: { abs($0 - targetSec) < 0.6 }) {
                    targetTimestamps.append(targetSec)
                }
            }
        }
        
        // 2. Uniform probes across the video to detect scene changes
        let step = max(totalDuration / Double(max(maxFrames * 2, 8)), 1.0)
        var probe = 0.5
        while probe < totalDuration - 0.2 {
            if !targetTimestamps.contains(where: { abs($0 - probe) < 0.6 }) {
                targetTimestamps.append(probe)
            }
            probe += step
        }
        
        targetTimestamps.sort()
        
        // Create keyframes destination directory
        let keyframesDir = videoURL.deletingPathExtension().appendingPathExtension("keyframes")
        try? FileManager.default.createDirectory(at: keyframesDir, withIntermediateDirectories: true)
        
        // Analyze frames with Vision
        struct CandidateFrame {
            let timestamp: Double
            let image: CGImage
            let featurePrint: VNFeaturePrintObservation?
            var saliencyScore: Float
        }
        
        var candidates: [CandidateFrame] = []
        var previousPrint: VNFeaturePrintObservation?
        
        for ts in targetTimestamps {
            let time = CMTime(seconds: ts, preferredTimescale: 600)
            guard let (cgImage, _) = try? await generator.image(at: time) else { continue }
            
            // Generate Vision Feature Print for visual difference
            var currentPrint: VNFeaturePrintObservation?
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            let fpReq = VNGenerateImageFeaturePrintRequest()
            if (try? handler.perform([fpReq])) != nil {
                currentPrint = fpReq.results?.first as? VNFeaturePrintObservation
            }
            
            // Visual transition score
            var score: Float = 0.0
            if let prev = previousPrint, let curr = currentPrint {
                var distance: Float = 0.0
                if (try? curr.computeDistance(&distance, to: prev)) != nil {
                    score = distance
                }
            } else {
                score = 1.0 // First frame is always a key anchor
            }
            
            // Give higher weight to frames close to a click event
            let isNearClick = events.contains(where: { abs($0.timeSec - ts) < 0.5 })
            if isNearClick {
                score += 1.5
            }
            
            candidates.append(CandidateFrame(
                timestamp: ts,
                image: cgImage,
                featurePrint: currentPrint,
                saliencyScore: score
            ))
            
            if currentPrint != nil {
                previousPrint = currentPrint
            }
        }
        
        // Select top scoring diverse frames
        candidates.sort { $0.saliencyScore > $1.saliencyScore }
        let selectedCandidates = candidates.prefix(maxFrames).sorted { $0.timestamp < $1.timestamp }
        
        var savedURLs: [URL] = []
        for (index, candidate) in selectedCandidates.enumerated() {
            let mins = Int(candidate.timestamp) / 60
            let secs = Int(candidate.timestamp) % 60
            let timeStr = String(format: "%02d-%02d", mins, secs)
            let filename = String(format: "step%d_%@.png", index + 1, timeStr)
            let fileURL = keyframesDir.appendingPathComponent(filename)
            
            let bitmapRep = NSBitmapImageRep(cgImage: candidate.image)
            if let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                try? pngData.write(to: fileURL)
                savedURLs.append(fileURL)
            }
        }
        
        print("[KeyframeExtractor] Extracted \(savedURLs.count) keyframes to \(keyframesDir.lastPathComponent)")
        return savedURLs
    }
}
