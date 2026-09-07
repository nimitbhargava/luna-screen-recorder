import Foundation

public final class RetentionManager {
    public static let shared = RetentionManager()
    
    public var recordingsDirectory: URL
    
    public static let autoDeleteDidChangeNotification = Notification.Name("LunaAutoDeleteDidChangeNotification")
    public static let autoCopyPathDidChangeNotification = Notification.Name("LunaAutoCopyPathDidChangeNotification")
    
    public var hasCompletedOnboarding: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "luna_has_completed_onboarding")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "luna_has_completed_onboarding")
        }
    }
    
    public var isAutoCopyPathEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "luna_auto_copy_path_enabled") == nil {
                return true // default enabled for LLM pasting
            }
            return UserDefaults.standard.bool(forKey: "luna_auto_copy_path_enabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "luna_auto_copy_path_enabled")
            NotificationCenter.default.post(name: RetentionManager.autoCopyPathDidChangeNotification, object: nil)
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
    
    public struct StorageAnalysis {
        public let totalRecordingsCount: Int
        public let totalSizeBytes: Int64
        public let eligibleCount: Int
        public let eligibleSizeBytes: Int64
        public let retentionDays: Int
        
        public var formattedTotalSize: String {
            let bcf = ByteCountFormatter()
            bcf.allowedUnits = [.useAll]
            bcf.countStyle = .file
            return bcf.string(fromByteCount: totalSizeBytes)
        }
        
        public var formattedEligibleSize: String {
            let bcf = ByteCountFormatter()
            bcf.allowedUnits = [.useAll]
            bcf.countStyle = .file
            return bcf.string(fromByteCount: eligibleSizeBytes)
        }
    }
    
    public func analyzeStorage(forDays days: Int? = nil) -> StorageAnalysis {
        ensureDirectoryExists()
        let targetDays = days ?? retentionDays
        let cutoffDate = Date().addingTimeInterval(-Double(targetDays) * 86400)
        let fileManager = FileManager.default
        guard let items = try? fileManager.contentsOfDirectory(
            at: recordingsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        ) else {
            return StorageAnalysis(totalRecordingsCount: 0, totalSizeBytes: 0, eligibleCount: 0, eligibleSizeBytes: 0, retentionDays: targetDays)
        }
        
        var totalCount = 0
        var totalBytes: Int64 = 0
        var eligibleCount = 0
        var eligibleBytes: Int64 = 0
        
        for item in items {
            guard item.pathExtension.lowercased() == "mp4" else { continue }
            totalCount += 1
            let size = Int64((try? item.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            totalBytes += size
            
            // Also add size of auxiliary files
            let base = item.deletingPathExtension()
            for ext in ["gif", "prompt.md", "events.json"] {
                let aux = base.appendingPathExtension(ext)
                if let s = (try? aux.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                    totalBytes += Int64(s)
                }
            }
            
            if let modDate = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
               modDate < cutoffDate {
                eligibleCount += 1
                eligibleBytes += size
                for ext in ["gif", "prompt.md", "events.json"] {
                    let aux = base.appendingPathExtension(ext)
                    if let s = (try? aux.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                        eligibleBytes += Int64(s)
                    }
                }
            }
        }
        
        return StorageAnalysis(
            totalRecordingsCount: totalCount,
            totalSizeBytes: totalBytes,
            eligibleCount: eligibleCount,
            eligibleSizeBytes: eligibleBytes,
            retentionDays: targetDays
        )
    }
    
    @discardableResult
    public func pruneRecordingsOlderThan(days: Int) -> (count: Int, freedBytes: Int64) {
        ensureDirectoryExists()
        let cutoffDate = Date().addingTimeInterval(-Double(days) * 86400)
        let fileManager = FileManager.default
        guard let items = try? fileManager.contentsOfDirectory(
            at: recordingsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        ) else {
            return (0, 0)
        }
        
        var prunedCount = 0
        var freedBytes: Int64 = 0
        
        for item in items {
            guard item.pathExtension.lowercased() == "mp4" else { continue }
            if let values = try? item.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
               let modDate = values.contentModificationDate,
               modDate < cutoffDate {
                let size = Int64(values.fileSize ?? 0)
                freedBytes += size
                deleteRecordingAndAuxiliaries(for: item)
                prunedCount += 1
                print("[RetentionManager] Pruned recording and assets: \(item.lastPathComponent)")
            }
        }
        return (prunedCount, freedBytes)
    }
    
    public func deleteRecordingAndAuxiliaries(for videoURL: URL) {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: videoURL)
        
        let base = videoURL.deletingPathExtension()
        let auxFiles = [
            base.appendingPathExtension("gif"),
            base.appendingPathExtension("prompt.md"),
            base.appendingPathExtension("events.json"),
            base.appendingPathExtension("keyframes")
        ]
        for aux in auxFiles {
            try? fileManager.removeItem(at: aux)
        }
    }
    
    @discardableResult
    public func pruneOldRecordings() -> Int {
        guard isAutoDeleteEnabled else {
            print("[RetentionManager] Auto-delete is disabled. Keeping all recordings.")
            return 0
        }
        return pruneRecordingsOlderThan(days: retentionDays).count
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
