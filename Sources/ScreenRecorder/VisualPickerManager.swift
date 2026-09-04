import AppKit
import ScreenCaptureKit

@available(macOS 14.0, *)
public final class VisualPickerManager: NSObject, SCContentSharingPickerObserver {
    public static let shared = VisualPickerManager()
    
    public var onFilterSelected: ((SCContentFilter) -> Void)?
    
    private override init() {
        super.init()
    }
    
    public func setup() {
        let picker = SCContentSharingPicker.shared
        picker.add(self)
        var config = SCContentSharingPickerConfiguration()
        config.allowedPickerModes = [.singleWindow, .singleDisplay, .multipleWindows]
        picker.defaultConfiguration = config
        picker.isActive = true
        print("[VisualPickerManager] Configured native visual screen/window picker")
    }
    
    public func present(onSelected: @escaping (SCContentFilter) -> Void) {
        self.onFilterSelected = onSelected
        let picker = SCContentSharingPicker.shared
        picker.isActive = true
        picker.present()
    }
    
    // MARK: - SCContentSharingPickerObserver
    public func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        print("[VisualPickerManager] User selected content filter: \(filter)")
        DispatchQueue.main.async { [weak self] in
            self?.onFilterSelected?(filter)
        }
    }
    
    public func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        print("[VisualPickerManager] User cancelled visual picker")
    }
    
    public func contentSharingPickerStartDidFailWithError(_ error: Error) {
        print("[VisualPickerManager] Visual picker failed with error: \(error)")
    }
}
