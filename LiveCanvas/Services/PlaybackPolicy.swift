import Foundation

/// Pure decision logic: given system conditions and user settings, which suppressions apply?
/// Kept free of AppKit so it can be exhaustively unit-tested.
enum PlaybackPolicy {
    struct Conditions: Equatable, Sendable {
        var userPaused: Bool = false
        var onBattery: Bool = false
        var lowPowerMode: Bool = false
        var appFullScreen: Bool = false
        var screenLocked: Bool = false
        var systemAsleep: Bool = false
        var displaysAsleep: Bool = false
    }

    struct Decision: Equatable, Sendable {
        var suppressions: Set<WallpaperEngine.Suppression>
        /// nil means "leave the player's rate alone"; otherwise a hint for reduced work.
        var reducedQuality: Bool
    }

    static func decide(conditions c: Conditions, settings: PlaybackSettings) -> Decision {
        var suppressions: Set<WallpaperEngine.Suppression> = []
        var reduced = false

        if c.userPaused { suppressions.insert(.userPaused) }
        // Nothing is visible while asleep or locked: stop decoding entirely.
        if c.systemAsleep || c.displaysAsleep { suppressions.insert(.asleep) }
        if c.screenLocked { suppressions.insert(.screenLocked) }
        if settings.pauseWhenAppFullScreen && c.appFullScreen { suppressions.insert(.fullScreenApp) }
        if settings.pauseInLowPowerMode && c.lowPowerMode { suppressions.insert(.lowPower) }

        if c.onBattery {
            switch settings.batteryBehavior {
            case .continueNormally: break
            case .reduceQuality: reduced = true
            case .pause: suppressions.insert(.battery)
            }
        }

        switch settings.quality {
        case .maximum: reduced = false
        case .batterySaver: reduced = true
        case .balanced: reduced = true
        case .auto: break   // battery behaviour above already decided
        }

        return Decision(suppressions: suppressions, reducedQuality: reduced)
    }
}
