import AppKit

/// Borderless window that sits at the desktop level: above Finder's desktop picture,
/// below desktop icons and every normal window. Never key, never main, ignores the
/// mouse, joins all Spaces, stationary in Mission Control, excluded from window cycling.
final class WallpaperWindow: NSWindow {
    static let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = Self.desktopLevel
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        ignoresMouseEvents = true
        isExcludedFromWindowsMenu = true
        isReleasedWhenClosed = false
        hasShadow = false
        isOpaque = true
        backgroundColor = .black
        hidesOnDeactivate = false
        animationBehavior = .none
        isMovable = false
        isRestorable = false
        displaysWhenScreenProfileChanges = true
        // Stay capturable: a screen-share or screenshot must show the wallpaper, not a hole.
        sharingType = .readOnly
        tabbingMode = .disallowed
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Order the window in without ever activating the app or stealing focus.
    func show() {
        orderFrontRegardless()
    }
}
