import Foundation
import Speech
import AVFoundation

public final class AudioTranscriber {
    public static let shared = AudioTranscriber()
    
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    
    private init() {}
    
    /// Transcribes audio track from a video file using on-device Apple Speech framework
    public func transcribeAudio(from videoURL: URL) async -> String? {
        guard let recognizer = recognizer, recognizer.isAvailable else {
            print("[AudioTranscriber] Speech recognizer not available")
            return nil
        }
        
        // Check if file has audio track
        let asset = AVURLAsset(url: videoURL)
        let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        guard !audioTracks.isEmpty else {
            return nil
        }
        
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .notDetermined {
            let granted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { newStatus in
                    continuation.resume(returning: newStatus == .authorized)
                }
            }
            if !granted { return nil }
        } else if status != .authorized {
            return nil
        }
        
        let request = SFSpeechURLRecognitionRequest(url: videoURL)
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        
        return await withCheckedContinuation { continuation in
            var hasResumed = false
            recognizer.recognitionTask(with: request) { result, error in
                if let result = result, result.isFinal {
                    if !hasResumed {
                        hasResumed = true
                        let transcript = result.bestTranscription.formattedString
                        continuation.resume(returning: transcript.isEmpty ? nil : transcript)
                    }
                } else if error != nil {
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }
}
