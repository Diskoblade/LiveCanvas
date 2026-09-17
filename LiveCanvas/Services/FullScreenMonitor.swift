import AppKit
import Observation

/// Detects whether a window is covering an entire screen (fullscreen video, presentations,
/// games). Uses CGWindowList, refreshed only when the frontmost app changes or a space
/// switch happens, plus a slow safety re-check while something is covering a screen.
@MainActor
@Observable
final class FullScreenMonitor {
    private(set) var isAnyAppFullScreen = false

    private var observers: [NSObjectProtocol] = []
    private var recheckTask: Task<Void, Never>?
    private var enabled = false

    init() {
        let nc = NSWorkspace.shared.notificationCenter
        func observe(_ name: Notification.Name) {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleCheck() }
            })
        }
        observe(NSWorkspace.didActivateApplicationNotification)
        observe(NSWorkspace.activeSpaceDidChangeNotification)
        observe(NSWorkspace.didDeactivateApplicationNotification)
    }

    isolated deinit {
        recheckTask?.cancel()
        let nc = NSWorkspace.shared.notificationCenter
        for o in observers { nc.removeObserver(o) }
    }

    func setEnabled(_ on: Bool) {
        guard enabled != on else { return }
        enabled = on
        if on { scheduleCheck() } else { recheckTask?.cancel(); isAnyAppFullScreen = false }
    }

    private func scheduleCheck() {
        guard enabled else { return }
        recheckTask?.cancel()
        recheckTask = Task { [weak self] in
            // Let the space/window animation settle before sampling.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.check()
        }
    }

    private func check() {
        // CGDisplayBounds is already in the same top-left-origin global space as
        // CGWindowBounds, so no AppKit/CoreGraphics coordinate conversion is needed.
        let bounds = NSScreen.screens.map { CGDisplayBounds(DisplayManager.directDisplayID(for: $0)) }
        guard !bounds.isEmpty else { return }
        let covering = Self.hasWindowCoveringAnyScreen(displayBounds: bounds)
        if covering != isAnyAppFullScreen {
            isAnyAppFullScreen = covering
            Log.power.info("Fullscreen app \(covering ? "detected" : "gone", privacy: .public)")
        }
        // While something is fullscreen, re-check occasionally: leaving fullscreen does not
        // always produce an app activation notification.
        if covering, enabled {
            recheckTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                self?.check()
            }
        }
    }

    /// A window at normal level, owned by another app, that covers an entire display.
    /// `displayBounds` must be in CoreGraphics global coordinates (CGDisplayBounds).
    nonisolated static func hasWindowCoveringAnyScreen(displayBounds: [CGRect]) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let ownPID = Int(ProcessInfo.processInfo.processIdentifier)
        for window in list {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  (window[kCGWindowOwnerPID as String] as? Int) != ownPID,
                  let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            if displayBounds.contains(where: { covers(window: rect, display: $0) }) { return true }
        }
        return false
    }

    /// True when `window` covers `display` on every edge. A zoomed ("maximized") window
    /// stops below the menu bar and therefore does not qualify.
    nonisolated static func covers(window: CGRect, display: CGRect, tolerance: CGFloat = 1) -> Bool {
        window.minX <= display.minX + tolerance &&
        window.minY <= display.minY + tolerance &&
        window.maxX >= display.maxX - tolerance &&
        window.maxY >= display.maxY - tolerance
    }
}
