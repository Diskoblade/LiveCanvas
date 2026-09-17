import AppKit
import Observation

/// Screen lock / unlock and screensaver state via the distributed notification center.
/// These names are the long-standing public loginwindow notifications; nothing is written.
@MainActor
@Observable
final class ScreenLockMonitor {
    private(set) var isLocked = false
    private(set) var isScreenSaverRunning = false

    private var observers: [NSObjectProtocol] = []

    init() {
        // Distributed notifications only report transitions; read the launch state.
        isLocked = SystemStateProbe.isScreenLocked()
        if isLocked {
            Log.app.info("Launched with the screen locked")
        }
        let dnc = DistributedNotificationCenter.default()
        func observe(_ name: String, _ body: @escaping @MainActor () -> Void) {
            observers.append(dnc.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { body() }
            })
        }
        observe("com.apple.screenIsLocked") { [weak self] in
            self?.isLocked = true
            Log.app.info("Screen locked")
        }
        observe("com.apple.screenIsUnlocked") { [weak self] in
            self?.isLocked = false
            Log.app.info("Screen unlocked")
        }
        observe("com.apple.screensaver.didstart") { [weak self] in self?.isScreenSaverRunning = true }
        observe("com.apple.screensaver.didstop") { [weak self] in self?.isScreenSaverRunning = false }
    }

    /// Re-reads the live session state, for wake and reactivation.
    func refreshFromSession() {
        let locked = SystemStateProbe.isScreenLocked()
        guard locked != isLocked else { return }
        isLocked = locked
        Log.app.info("Screen lock state corrected to \(locked ? "locked" : "unlocked", privacy: .public)")
    }

    isolated deinit {
        let dnc = DistributedNotificationCenter.default()
        for o in observers { dnc.removeObserver(o) }
    }
}
