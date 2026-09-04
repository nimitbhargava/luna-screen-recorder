import Foundation

public final class RetentionManager {
    public static let shared = RetentionManager()
    
    public let recordingsDirectory: URL
    
    public static let autoDeleteDidChangeNotification = Notification.Name("LunaAutoDeleteDidChangeNotification")
    
    public var hasCompletedOnboarding: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "luna_has_completed_onboarding")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "luna_has_completed_onboarding")
        }
    }
    
    public var isAutoDeleteEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "luna_auto_delete_enabled") == nil {
                return true // default enabled for throwaway recordings
            }
            return UserDefaults.standard.bool(forKey: "luna_auto_delete_enabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "luna_auto_delete_enabled")
            NotificationCenter.default.post(name: RetentionManager.autoDeleteDidChangeNotification, object: nil)
        }
    }
    
    public var retentionDays: Int {
        get {
            let days = UserDefaults.standard.integer(forKey: "luna_retention_days")
            return days > 0 ? days : 15
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "luna_retention_days")
            NotificationCenter.default.post(name: RetentionManager.autoDeleteDidChangeNotification, object: nil)
        }
    }
    
    public init(customDirectory: URL? = nil) {
        if let dir = customDirectory {
            self.recordingsDirectory = dir
        } else {
            let moviesDir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Movies")
            self.recordingsDirectory = moviesDir.appendingPathComponent("ScreenRecordings", isDirectory: true)
        }
        ensureDirectoryExists()
    }
    
    public func ensureDirectoryExists() {
        if !FileManager.default.fileExists(atPath: recordingsDirectory.path) {
            try? FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    @discardableResult
    public func pruneOldRecordings() -> Int {
        guard isAutoDeleteEnabled else {
            print("[RetentionManager] Auto-delete is disabled. Keeping all recordings.")
            return 0
        }
        
        ensureDirectoryExists()
        let fileManager = FileManager.default
        guard let items = try? fileManager.contentsOfDirectory(
            at: recordingsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        ) else {
            return 0
        }
        
        let cutoffDate = Date().addingTimeInterval(-Double(retentionDays) * 86400)
        var prunedCount = 0
        
        for item in items {
            guard item.pathExtension.lowercased() == "mp4" || item.pathExtension.lowercased() == "mov" || item.pathExtension.lowercased() == "gif" else {
                continue
            }
            if let values = try? item.resourceValues(forKeys: [.contentModificationDateKey]),
               let modDate = values.contentModificationDate,
               modDate < cutoffDate {
                do {
                    try fileManager.removeItem(at: item)
                    prunedCount += 1
                    print("[RetentionManager] Pruned old recording: \(item.lastPathComponent)")
                } catch {
                    print("[RetentionManager] Failed to prune \(item.lastPathComponent): \(error)")
                }
            }
        }
        return prunedCount
    }
    
    public func generateOutputFileURL(prefix: String = "Recording") -> URL {
        ensureDirectoryExists()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let filename = "\(prefix)_\(timestamp).mp4"
        return recordingsDirectory.appendingPathComponent(filename)
    }
    
    public static func formattedFileSize(for url: URL) -> String {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else {
            return "Unknown size"
        }
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useMB, .useKB]
        bcf.countStyle = .file
        return bcf.string(fromByteCount: Int64(size))
    }
}
