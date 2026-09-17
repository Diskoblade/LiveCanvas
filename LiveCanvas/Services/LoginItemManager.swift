import Foundation
import ServiceManagement
import Observation

/// Start-at-login via SMAppService (macOS 13+). No LaunchAgent plist hacks.
@MainActor
@Observable
final class LoginItemManager {
    private(set) var isEnabled = false
    private(set) var lastError: String?

    init() {
        refresh()
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// Returns true when the requested state was reached.
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            lastError = nil
            refresh()
            Log.app.info("Login item \(enabled ? "registered" : "unregistered"), status now \(self.isEnabled)")
            return isEnabled == enabled
        } catch {
            lastError = error.localizedDescription
            Log.app.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
            refresh()
            return false
        }
    }

    /// macOS shows login items under Settings; the user may have disabled ours there.
    var requiresUserApproval: Bool { SMAppService.mainApp.status == .requiresApproval }
}
