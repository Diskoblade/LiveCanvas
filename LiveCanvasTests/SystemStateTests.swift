import Testing
import AppKit
@testable import LiveCanvas

/// Regression cover for the "launched while the screen was already off" energy bug:
/// the workspace and distributed notifications only report transitions, so the monitors
/// must read the live state at init or they keep decoding video to a dark display.
@MainActor
struct SystemStateTests {

    @Test func probeIsReadableAndSelfConsistent() {
        // Reading must be stable and side-effect free.
        let asleepFirst = SystemStateProbe.areDisplaysAsleep()
        let asleepSecond = SystemStateProbe.areDisplaysAsleep()
        #expect(asleepFirst == asleepSecond)

        let lockedFirst = SystemStateProbe.isScreenLocked()
        #expect(lockedFirst == SystemStateProbe.isScreenLocked())

        // The session dictionary is always readable from a logged-in GUI session.
        #expect(SystemStateProbe.isOnConsole() == SystemStateProbe.isOnConsole())
    }

    @Test func displaysAsleepAgreesWithScreenAvailability() {
        // When CoreGraphics reports the displays awake, AppKit must see at least one
        // screen; the two APIs disagreeing would mean the probe is reading the wrong thing.
        if !SystemStateProbe.areDisplaysAsleep() {
            #expect(!NSScreen.screens.isEmpty)
        }
    }

    @Test func sleepMonitorAdoptsTheLaunchTimeDisplayState() {
        let monitor = SleepWakeMonitor()
        #expect(monitor.isDisplayAsleep == SystemStateProbe.areDisplaysAsleep(),
                "a monitor created while the screen is off must start in the asleep state")
        #expect(!monitor.isAsleep, "system sleep cannot be true while code is running")
    }

    @Test func lockMonitorAdoptsTheLaunchTimeLockState() {
        let monitor = ScreenLockMonitor()
        #expect(monitor.isLocked == SystemStateProbe.isScreenLocked(),
                "a monitor created while the screen is locked must start locked")
    }

    @Test func refreshFromHardwareConvergesOnTheLiveState() {
        let monitor = SleepWakeMonitor()
        monitor.refreshFromHardware()
        #expect(monitor.isDisplayAsleep == SystemStateProbe.areDisplaysAsleep())
        // Idempotent: a second refresh must not flip the value.
        monitor.refreshFromHardware()
        #expect(monitor.isDisplayAsleep == SystemStateProbe.areDisplaysAsleep())
    }

    @Test func refreshFromSessionConvergesOnTheLiveState() {
        let monitor = ScreenLockMonitor()
        monitor.refreshFromSession()
        #expect(monitor.isLocked == SystemStateProbe.isScreenLocked())
        monitor.refreshFromSession()
        #expect(monitor.isLocked == SystemStateProbe.isScreenLocked())
    }

    @Test func aSleepingDisplayAlwaysSuppressesPlayback() {
        // The policy half of the bug: whatever the user's energy settings, nothing should
        // decode while the panel is off.
        var permissive = PlaybackSettings()
        permissive.pauseInLowPowerMode = false
        permissive.pauseWhenAppFullScreen = false
        permissive.batteryBehavior = .continueNormally
        permissive.quality = .maximum

        let decision = PlaybackPolicy.decide(
            conditions: .init(displaysAsleep: true), settings: permissive)
        #expect(decision.suppressions.contains(.asleep))

        let lockedDecision = PlaybackPolicy.decide(
            conditions: .init(screenLocked: true), settings: permissive)
        #expect(lockedDecision.suppressions.contains(.screenLocked))

        // Both at once, as at a real launch into a dark screen.
        let both = PlaybackPolicy.decide(
            conditions: .init(screenLocked: true, displaysAsleep: true), settings: permissive)
        #expect(both.suppressions == [.asleep, .screenLocked])
    }
}
