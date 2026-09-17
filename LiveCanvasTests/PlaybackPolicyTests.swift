import Testing
@testable import LiveCanvas

struct PlaybackPolicyTests {
    private var defaults: PlaybackSettings { PlaybackSettings() }

    @Test func idleConditionsPlay() {
        let d = PlaybackPolicy.decide(conditions: .init(), settings: defaults)
        #expect(d.suppressions.isEmpty)
    }

    @Test func sleepAndLockAlwaysSuppressRegardlessOfSettings() {
        var s = defaults
        s.pauseInLowPowerMode = false
        s.pauseWhenAppFullScreen = false
        s.batteryBehavior = .continueNormally
        #expect(PlaybackPolicy.decide(conditions: .init(systemAsleep: true), settings: s).suppressions == [.asleep])
        #expect(PlaybackPolicy.decide(conditions: .init(displaysAsleep: true), settings: s).suppressions == [.asleep])
        #expect(PlaybackPolicy.decide(conditions: .init(screenLocked: true), settings: s).suppressions == [.screenLocked])
    }

    @Test func fullScreenHonoursSetting() {
        var on = defaults; on.pauseWhenAppFullScreen = true
        var off = defaults; off.pauseWhenAppFullScreen = false
        #expect(PlaybackPolicy.decide(conditions: .init(appFullScreen: true), settings: on).suppressions.contains(.fullScreenApp))
        #expect(PlaybackPolicy.decide(conditions: .init(appFullScreen: true), settings: off).suppressions.isEmpty)
    }

    @Test func lowPowerHonoursSetting() {
        var on = defaults; on.pauseInLowPowerMode = true
        var off = defaults; off.pauseInLowPowerMode = false
        #expect(PlaybackPolicy.decide(conditions: .init(lowPowerMode: true), settings: on).suppressions.contains(.lowPower))
        #expect(!PlaybackPolicy.decide(conditions: .init(lowPowerMode: true), settings: off).suppressions.contains(.lowPower))
    }

    @Test func batteryBehaviourBranches() {
        var pause = defaults; pause.batteryBehavior = .pause
        var reduce = defaults; reduce.batteryBehavior = .reduceQuality
        var normal = defaults; normal.batteryBehavior = .continueNormally
        let onBattery = PlaybackPolicy.Conditions(onBattery: true)

        #expect(PlaybackPolicy.decide(conditions: onBattery, settings: pause).suppressions.contains(.battery))
        let r = PlaybackPolicy.decide(conditions: onBattery, settings: reduce)
        #expect(!r.suppressions.contains(.battery))
        #expect(r.reducedQuality)
        let n = PlaybackPolicy.decide(conditions: onBattery, settings: normal)
        #expect(n.suppressions.isEmpty)
        #expect(!n.reducedQuality)
    }

    @Test func maximumQualityOverridesReduction() {
        var s = defaults
        s.quality = .maximum
        s.batteryBehavior = .reduceQuality
        #expect(!PlaybackPolicy.decide(conditions: .init(onBattery: true), settings: s).reducedQuality)
    }

    @Test func userPauseIsIndependent() {
        let d = PlaybackPolicy.decide(conditions: .init(userPaused: true), settings: defaults)
        #expect(d.suppressions == [.userPaused])
    }

    @Test func multipleReasonsAccumulate() {
        var s = defaults
        s.batteryBehavior = .pause
        let d = PlaybackPolicy.decide(
            conditions: .init(userPaused: true, onBattery: true, lowPowerMode: true, appFullScreen: true),
            settings: s)
        #expect(d.suppressions == [.userPaused, .battery, .lowPower, .fullScreenApp])
    }
}

struct FullScreenGeometryTests {
    // CoreGraphics global space: top-left origin, Y grows downward.
    let external = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    let builtIn = CGRect(x: 2560, y: 74, width: 1800, height: 1169)

    @Test func trueFullScreenWindowCovers() {
        #expect(FullScreenMonitor.covers(window: external, display: external))
        #expect(FullScreenMonitor.covers(window: builtIn, display: builtIn))
    }

    @Test func maximizedWindowUnderMenuBarDoesNotCover() {
        // Zoomed window on the external display: starts below the 30pt menu bar.
        let zoomed = CGRect(x: 0, y: 30, width: 2560, height: 1410)
        #expect(!FullScreenMonitor.covers(window: zoomed, display: external))
    }

    @Test func bigWindowOnOneDisplayDoesNotCoverAnother() {
        // The regression: a 2560×1410 window on the external monitor must not be treated
        // as covering the smaller built-in display just because it is larger than it.
        let zoomed = CGRect(x: 0, y: 30, width: 2560, height: 1410)
        #expect(!FullScreenMonitor.covers(window: zoomed, display: builtIn))
        let fullOnExternal = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        #expect(!FullScreenMonitor.covers(window: fullOnExternal, display: builtIn))
    }

    @Test func windowSpanningBothDisplaysCoversBoth() {
        // builtIn spans y 74…1243, so a full-height window across both displays covers it.
        let spanning = CGRect(x: 0, y: 0, width: 4360, height: 1440)
        #expect(FullScreenMonitor.covers(window: spanning, display: external))
        #expect(FullScreenMonitor.covers(window: spanning, display: builtIn))
    }

    @Test func windowTooShortForTheTallerDisplayDoesNotCoverIt() {
        // Ends at y=1200, above builtIn's bottom edge at y=1243.
        let short = CGRect(x: 0, y: 0, width: 4360, height: 1200)
        #expect(!FullScreenMonitor.covers(window: short, display: builtIn))
    }

    @Test func toleranceAbsorbsSubPixelRounding() {
        let almost = CGRect(x: 0.4, y: 0.4, width: 2559.2, height: 1439.2)
        #expect(FullScreenMonitor.covers(window: almost, display: external))
    }
}

import CoreGraphics
