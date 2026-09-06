import Foundation
import AVFoundation

public final class MediaPostProcessor {
    public static let shared = MediaPostProcessor()
    
    public let ffmpegPath: String?
    
    private init() {
        let defaultPaths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        self.ffmpegPath = defaultPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
        if let path = self.ffmpegPath {
            print("[MediaPostProcessor] Found ffmpeg at: \(path)")
        } else {
            print("[MediaPostProcessor] ffmpeg not found in default paths")
        }
    }
    
    /// Remuxes the MP4 with `+faststart` and preserves real audio track, or injects a silent AAC audio track if muted so web platforms like Gemini accept it.
    @discardableResult
    public func remuxForWebCompatibility(inputURL: URL) -> URL {
        guard let ffmpeg = ffmpegPath else {
            print("[MediaPostProcessor] ffmpeg not available, skipping web remux")
            return inputURL
        }
        
        let tempURL = inputURL.deletingPathExtension().appendingPathExtension("web.mp4")
        
        let asset = AVURLAsset(url: inputURL)
        let hasAudio = !asset.tracks(withMediaType: .audio).isEmpty
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        
        if hasAudio {
            // Video already contains recorded microphone audio: copy both video and audio directly
            process.arguments = [
                "-y",
                "-i", inputURL.path,
                "-c", "copy",
                "-movflags", "+faststart",
                tempURL.path
            ]
        } else {
            // Muted recording: inject silent null audio so web/Gemini accept it
            process.arguments = [
                "-y",
                "-i", inputURL.path,
                "-f", "lavfi",
                "-i", "anullsrc=channel_layout=stereo:sample_rate=44100",
                "-c:v", "copy",
                "-c:a", "aac",
                "-shortest",
                "-movflags", "+faststart",
                tempURL.path
            ]
        }
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 && FileManager.default.fileExists(atPath: tempURL.path) {
                // Replace original with optimized version
                _ = try? FileManager.default.removeItem(at: inputURL)
                try FileManager.default.moveItem(at: tempURL, to: inputURL)
                print("[MediaPostProcessor] Successfully remuxed \(inputURL.lastPathComponent) with faststart and silent AAC")
                return inputURL
            } else {
                print("[MediaPostProcessor] ffmpeg exited with status: \(process.terminationStatus)")
                try? FileManager.default.removeItem(at: tempURL)
                return inputURL
            }
        } catch {
            print("[MediaPostProcessor] Remux failed with error: \(error)")
            try? FileManager.default.removeItem(at: tempURL)
            return inputURL
        }
    }
    
    /// Generates a high-quality, lightweight GIF from the recorded MP4.
    public func generateGIF(from inputURL: URL, maxSeconds: Double = 45) -> URL? {
        guard let ffmpeg = ffmpegPath else { return nil }
        
        let gifURL = inputURL.deletingPathExtension().appendingPathExtension("gif")
        if FileManager.default.fileExists(atPath: gifURL.path) {
            return gifURL
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        
        // 12 fps, max width 800px, 128 colors palette for optimal size and crisp code readability
        let vfFilter = "fps=12,scale=min(800\\,iw):-2:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128:reserve_transparent=0[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3"
        
        process.arguments = [
            "-y",
            "-t", String(format: "%.1f", maxSeconds),
            "-i", inputURL.path,
            "-vf", vfFilter,
            gifURL.path
        ]
        
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 && FileManager.default.fileExists(atPath: gifURL.path) {
                print("[MediaPostProcessor] Generated GIF: \(gifURL.lastPathComponent)")
                return gifURL
            }
        } catch {
            print("[MediaPostProcessor] GIF generation failed: \(error)")
        }
        return nil
    }
}
