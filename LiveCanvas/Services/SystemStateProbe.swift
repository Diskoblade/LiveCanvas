import CoreGraphics
import Foundation

/// Reads the *current* display-sleep and screen-lock state.
///
/// The workspace and distributed notifications only report **transitions**, so an app
/// launched (or relaunched) while the screen is already off or locked would otherwise
/// believe everything is awake and keep decoding video to a dark display. Both values
/// here are read-only CoreGraphics queries; nothing is modified.
enum SystemStateProbe {

    /// True when every active display is asleep. With no active display list available
    /// (which is itself what CoreGraphics reports while the screen is off) the main
    /// display's own flag is used.
    static func areDisplaysAsleep() -> Bool {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        if CGGetActiveDisplayList(16, &ids, &count) == .success, count > 0 {
            return (0..<Int(count)).allSatisfy { CGDisplayIsAsleep(ids[$0]) != 0 }
        }
        return CGDisplayIsAsleep(CGMainDisplayID()) != 0
    }

    /// True when the login session reports the screen as locked.
    static func isScreenLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        if let locked = session["CGSSessionScreenIsLocked"] as? Bool { return locked }
        if let locked = session["CGSSessionScreenIsLocked"] as? Int { return locked != 0 }
        return false
    }

    /// True when this session owns the console. A fast-user-switched-away session should
    /// not be driving wallpaper playback either.
    static func isOnConsole() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return true }
        if let onConsole = session["kCGSSessionOnConsoleKey"] as? Bool { return onConsole }
        if let onConsole = session["kCGSSessionOnConsoleKey"] as? Int { return onConsole != 0 }
        return true
    }
}
