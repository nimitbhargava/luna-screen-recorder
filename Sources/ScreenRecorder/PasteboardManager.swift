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
            promptContent = InteractionTracker.shared.generatePromptMarkdown(videoURL: fileURL)
        }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(promptContent, forType: .string)
        print("[PasteboardManager] Successfully copied AI prompt with path & interaction log to pasteboard")
    }
}
