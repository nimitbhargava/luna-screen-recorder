import AppKit
import Foundation

public final class PasteboardManager {
    public static let shared = PasteboardManager()
    
    private init() {}
    
    @discardableResult
    public func copyFileToPasteboard(fileURL: URL) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        let pathList = [fileURL.path] as NSArray
        pasteboard.setPropertyList(pathList, forType: filenamesType)
        pasteboard.writeObjects([fileURL as NSURL])
        pasteboard.setString(fileURL.path, forType: .string)
        
        print("[PasteboardManager] Successfully copied \(fileURL.lastPathComponent) to pasteboard")
        return true
    }
    
    @discardableResult
    public func copyGIFToPasteboard(gifURL: URL) -> Bool {
        guard let data = try? Data(contentsOf: gifURL) else {
            return false
        }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        let gifType = NSPasteboard.PasteboardType("com.compuserve.gif")
        let publicGifType = NSPasteboard.PasteboardType("public.gif")
        
        pasteboard.setData(data, forType: gifType)
        pasteboard.setData(data, forType: publicGifType)
        
        // Also provide file URL and path so apps that prefer files can use it
        let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        let pathList = [gifURL.path] as NSArray
        pasteboard.setPropertyList(pathList, forType: filenamesType)
        pasteboard.writeObjects([gifURL as NSURL])
        pasteboard.setString(gifURL.path, forType: .string)
        
        print("[PasteboardManager] Successfully copied animated GIF \(gifURL.lastPathComponent) to pasteboard")
        return true
    }
    
    public func copyPathToPasteboard(fileURL: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(fileURL.path, forType: .string)
        print("[PasteboardManager] Successfully copied path as plain text \(fileURL.path) to pasteboard")
    }
    
    public func copyAIPromptToPasteboard(fileURL: URL) {
        let promptURL = fileURL.deletingPathExtension().appendingPathExtension("prompt.md")
        let promptContent: String
        if let savedPrompt = try? String(contentsOf: promptURL, encoding: .utf8), !savedPrompt.isEmpty {
            promptContent = savedPrompt
        } else {
            let transcript = AudioTranscriber.shared.extractSavedTranscript(for: fileURL)
            promptContent = InteractionTracker.shared.generatePromptMarkdown(videoURL: fileURL, speechTranscript: transcript)
        }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(promptContent, forType: .string)
        print("[PasteboardManager] Successfully copied AI prompt with path & interaction log to pasteboard")
    }
    
    public func copyMultipleAIPromptsToPasteboard(fileURLs: [URL]) {
        guard !fileURLs.isEmpty else { return }
        if fileURLs.count == 1 {
            copyAIPromptToPasteboard(fileURL: fileURLs[0])
            return
        }
        
        var combinedSections: [String] = []
        combinedSections.append(fileURLs.map { $0.path }.joined(separator: "\n"))
        combinedSections.append("\n---\n")
        
        for (index, fileURL) in fileURLs.enumerated() {
            let promptURL = fileURL.deletingPathExtension().appendingPathExtension("prompt.md")
            let content: String
            if let savedPrompt = try? String(contentsOf: promptURL, encoding: .utf8), !savedPrompt.isEmpty {
                var lines = savedPrompt.components(separatedBy: "\n")
                if lines.first == fileURL.path {
                    lines.removeFirst()
                }
                content = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                let transcript = AudioTranscriber.shared.extractSavedTranscript(for: fileURL)
                content = InteractionTracker.shared.generatePromptMarkdown(videoURL: fileURL, speechTranscript: transcript)
            }
            combinedSections.append("### Recording \(index + 1): `\(fileURL.lastPathComponent)`\n\(content)")
        }
        
        let combinedText = combinedSections.joined(separator: "\n\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(combinedText, forType: .string)
        print("[PasteboardManager] Successfully copied \(fileURLs.count) AI prompts to pasteboard")
    }
    
    @discardableResult
    public func copyMultipleFilesToPasteboard(fileURLs: [URL]) -> Bool {
        guard !fileURLs.isEmpty else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        let pathList = fileURLs.map { $0.path } as NSArray
        pasteboard.setPropertyList(pathList, forType: filenamesType)
        pasteboard.writeObjects(fileURLs.map { $0 as NSURL })
        pasteboard.setString(fileURLs.map { $0.path }.joined(separator: "\n"), forType: .string)
        
        print("[PasteboardManager] Successfully copied \(fileURLs.count) files to pasteboard")
        return true
    }
}
