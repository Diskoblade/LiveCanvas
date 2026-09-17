import AppKit
import Observation

/// Wires the system monitors to the wallpaper engine through PlaybackPolicy.
@MainActor
@Observable
final class SystemCoordinator {
    let power = PowerMonitor()
    let lock = ScreenLockMonitor()
    let sleepWake = SleepWakeMonitor()
    let fullScreen = FullScreenMonitor()
    let loginItem = LoginItemManager()

    private let engine: WallpaperEngine
    private let preferences: PreferencesStore
    private var userPaused = false
    private var stateCheck: Task<Void, Never>?

    init(engine: WallpaperEngine, preferences: PreferencesStore) {
        self.engine = engine
        self.preferences = preferences
        sleepWake.onWake = { [weak self] in
            guard let self else { return }
            self.sleepWake.refreshFromHardware()
            self.lock.refreshFromSession()
            self.engine.validateWindows()
            self.apply()
        }
        observeAndApply()
        startPeriodicStateCheck()
    }

    isolated deinit { stateCheck?.cancel() }

    var isPaused: Bool { userPaused }

    func setUserPaused(_ paused: Bool) {
        userPaused = paused
        apply()
    }

    func togglePaused() { setUserPaused(!userPaused) }

    private func observeAndApply() {
        withObservationTracking {
            apply()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeAndApply() }
        }
    }

    /// A slow safety net. Wake and lock notifications are occasionally missed (notably
    /// when the app launches or is resumed around a sleep transition), and the cost of a
    /// missed one is decoding video to a dark screen indefinitely. This check is cheap
    /// and only runs while something is actually playing.
    private func startPeriodicStateCheck() {
        stateCheck?.cancel()
        stateCheck = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, !Task.isCancelled else { return }
                self.sleepWake.refreshFromHardware()
                self.lock.refreshFromSession()
            }
        }
    }

    private func apply() {
        let settings = preferences.settings.playback
        fullScreen.setEnabled(settings.pauseWhenAppFullScreen)

        let conditions = PlaybackPolicy.Conditions(
            userPaused: userPaused,
            onBattery: power.isOnBattery,
            lowPowerMode: power.isLowPowerMode,
            appFullScreen: fullScreen.isAnyAppFullScreen,
            screenLocked: lock.isLocked,
            systemAsleep: sleepWake.isAsleep,
            displaysAsleep: sleepWake.isDisplayAsleep
        )
        let decision = PlaybackPolicy.decide(conditions: conditions, settings: settings)
        engine.applySuppressions(decision.suppressions)
    }
}
