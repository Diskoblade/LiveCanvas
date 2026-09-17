import Foundation

/// Asks the per-user wallpaper agent to reload after `Store/Index.plist` changes.
///
/// This only signals an ordinary per-user LaunchAgent, which `launchd` restarts on demand.
/// No system process is modified, nothing is injected, and no elevated privileges are used.
enum WallpaperAgentController {
    static let agentLabel = "com.apple.wallpaper.agent"

    /// Returns true when the agent was signalled. Failure is not fatal: the change still
    /// lands on the next login or when the user opens System Settings.
    @discardableResult
    static func reload() -> Bool {
        let uid = getuid()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["kickstart", "-k", "gui/\(uid)/\(agentLabel)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let ok = process.terminationStatus == 0
            Log.lockscreen.info("Wallpaper agent reload \(ok ? "succeeded" : "returned \(process.terminationStatus)", privacy: .public)")
            return ok
        } catch {
            Log.lockscreen.error("Could not reload the wallpaper agent: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
