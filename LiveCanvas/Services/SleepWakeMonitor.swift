import AppKit
import Observation

/// System and display sleep/wake via NSWorkspace notifications.
@MainActor
@Observable
final class SleepWakeMonitor {
    private(set) var isAsleep = false
    private(set) var isDisplayAsleep = false

    /// Fired after the system or the displays wake, so the engine can validate its windows.
    var onWake: (() -> Void)?

    /// Re-reads the live hardware state. Used on wake and when the app is reactivated,
    /// because a missed notification would otherwise leave playback running unseen.
    func refreshFromHardware() {
        let asleep = SystemStateProbe.areDisplaysAsleep()
        guard asleep != isDisplayAsleep else { return }
        isDisplayAsleep = asleep
        Log.app.info("Display sleep state corrected to \(asleep ? "asleep" : "awake", privacy: .public)")
    }

    private var observers: [NSObjectProtocol] = []

    init() {
        // Notifications only report transitions, so read the state we launched into.
        isDisplayAsleep = SystemStateProbe.areDisplaysAsleep()
        if isDisplayAsleep {
            Log.app.info("Launched with displays asleep")
        }
        let nc = NSWorkspace.shared.notificationCenter
        func observe(_ name: Notification.Name, _ body: @escaping @MainActor () -> Void) {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { body() }
            })
        }
        observe(NSWorkspace.willSleepNotification) { [weak self] in
            self?.isAsleep = true
            Log.app.info("System will sleep")
        }
        observe(NSWorkspace.didWakeNotification) { [weak self] in
            self?.isAsleep = false
            self?.isDisplayAsleep = SystemStateProbe.areDisplaysAsleep()
            Log.app.info("System did wake")
            self?.onWake?()
        }
        observe(NSWorkspace.screensDidSleepNotification) { [weak self] in
            self?.isDisplayAsleep = true
            Log.app.info("Displays slept")
        }
        observe(NSWorkspace.screensDidWakeNotification) { [weak self] in
            // Trust the hardware over the notification: a wake notification can arrive
            // while the panel is still off.
            self?.isDisplayAsleep = SystemStateProbe.areDisplaysAsleep()
            Log.app.info("Displays woke")
            self?.onWake?()
        }
    }

    isolated deinit {
        let nc = NSWorkspace.shared.notificationCenter
        for o in observers { nc.removeObserver(o) }
    }
}
