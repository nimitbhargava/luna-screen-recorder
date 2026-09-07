import Foundation
import Speech
import AVFoundation

public final class AudioTranscriber {
    public static let shared = AudioTranscriber()
    
    private init() {}
    
    private func getRecognizer() -> SFSpeechRecognizer? {
        if let current = SFSpeechRecognizer(locale: Locale.current), current.isAvailable {
            return current
        }
        if let en = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), en.isAvailable {
            return en
        }
        return SFSpeechRecognizer()
    }
    
    /// Checks prompt.md to see if a transcript was already generated and saved
    public func extractSavedTranscript(for videoURL: URL) -> String? {
        let promptURL = videoURL.deletingPathExtension().appendingPathExtension("prompt.md")
        guard let content = try? String(contentsOf: promptURL, encoding: .utf8) else { return nil }
        
        let marker = "### Voice Narration Transcript:"
        guard let markerRange = content.range(of: marker) else { return nil }
        
        let sub = content[markerRange.upperBound...]
        let lines = sub.components(separatedBy: "\n")
        var quoteLines: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("> \"") && trimmed.hasSuffix("\"") {
                let inner = trimmed.dropFirst(3).dropLast(1)
                return String(inner)
            } else if trimmed.hasPrefix(">") {
                quoteLines.append(trimmed.dropFirst(1).trimmingCharacters(in: .whitespaces))
            } else if !trimmed.isEmpty && !quoteLines.isEmpty {
                break
            }
        }
        if !quoteLines.isEmpty {
            let combined = quoteLines.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            return combined.isEmpty ? nil : combined
        }
        return nil
    }
    
    /// Transcribes audio track from a video file using Apple Speech framework with on-device preference
    public func transcribeAudio(from videoURL: URL) async -> String? {
        guard let recognizer = getRecognizer() else {
            print("[AudioTranscriber] Speech recognizer not available")
            return nil
        }
        
        // Check if file has an audio track
        let asset = AVURLAsset(url: videoURL)
        let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        guard !audioTracks.isEmpty else {
            print("[AudioTranscriber] No audio tracks found in \(videoURL.lastPathComponent)")
            return nil
        }
        
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .notDetermined {
            let granted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { newStatus in
                    continuation.resume(returning: newStatus == .authorized)
                }
            }
            if !granted {
                print("[AudioTranscriber] Speech recognition authorization denied")
                return nil
            }
        } else if status != .authorized {
            print("[AudioTranscriber] Speech recognition status not authorized: \(status.rawValue)")
            return nil
        }
        
        // Try on-device recognition first, fall back to standard recognition if on-device model unavailable
        if recognizer.supportsOnDeviceRecognition {
            if let text = await performRecognition(url: videoURL, recognizer: recognizer, onDeviceOnly: true) {
                return text
            }
        }
        
        return await performRecognition(url: videoURL, recognizer: recognizer, onDeviceOnly: false)
    }
    
    private func performRecognition(url: URL, recognizer: SFSpeechRecognizer, onDeviceOnly: Bool) async -> String? {
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        if onDeviceOnly && recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        
        return await withCheckedContinuation { continuation in
            var hasResumed = false
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let result = result, result.isFinal {
                    if !hasResumed {
                        hasResumed = true
                        let transcript = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(returning: transcript.isEmpty ? nil : transcript)
                    }
                } else if let error = error {
                    print("[AudioTranscriber] Recognition task error (onDevice=\(onDeviceOnly)): \(error.localizedDescription)")
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(returning: nil)
                    }
                }
            }
            
            // Timeout safeguard for speech recognition (12 seconds)
            DispatchQueue.global().asyncAfter(deadline: .now() + 12.0) {
                if !hasResumed {
                    hasResumed = true
                    task.cancel()
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    /// Ensures a transcript exists: reads existing or runs transcription on-demand and updates prompt.md
    @discardableResult
    public func ensureTranscript(for videoURL: URL) async -> String? {
        if let existing = extractSavedTranscript(for: videoURL) {
            return existing
        }
        
        guard let transcript = await transcribeAudio(from: videoURL), !transcript.isEmpty else {
            return nil
        }
        
        // Update prompt.md with transcript
        let promptURL = videoURL.deletingPathExtension().appendingPathExtension("prompt.md")
        if let currentPrompt = try? String(contentsOf: promptURL, encoding: .utf8) {
            if !currentPrompt.contains("### Voice Narration Transcript:") {
                var lines = currentPrompt.components(separatedBy: "\n")
                // Insert after context section or at top
                let insertIdx = lines.firstIndex(where: { $0.hasPrefix("### Keyframe Snapshots") || $0.hasPrefix("### User Action Steps") }) ?? lines.count
                let block = [
                    "### Voice Narration Transcript:",
                    "> \"\(transcript)\"",
                    ""
                ]
                lines.insert(contentsOf: block, at: insertIdx)
                let updated = lines.joined(separator: "\n")
                try? updated.data(using: .utf8)?.write(to: promptURL)
            }
        }
        
        return transcript
    }
}
