import Foundation
import ServiceManagement

/// "Open at login" through the system's Login Items list.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns an error message to show, or nil on success.
    @discardableResult
    static func set(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            penlightLog("login item \(on ? "register" : "unregister") failed: \(error)")
            return "無法設定開機啟動：\(error.localizedDescription)"
        }
    }

    /// The system may require the user to approve it in System Settings → Login Items.
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }
}
