import Foundation

/// How a video is laid out on a display. Mapped to AVLayerVideoGravity / manual layout in the engine.
enum FitMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case fill
    case fit
    case stretch
    case original

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fill: return "Fill"
        case .fit: return "Fit"
        case .stretch: return "Stretch"
        case .original: return "Original"
        }
    }

    var help: String {
        switch self {
        case .fill: return "Preserve aspect ratio and crop the excess."
        case .fit: return "Preserve aspect ratio and letterbox if required."
        case .stretch: return "Fill the entire screen, even if that distorts the video."
        case .original: return "Show at natural size, centered."
        }
    }
}

enum PlaybackQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto, maximum, balanced, batterySaver
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .maximum: return "Maximum"
        case .balanced: return "Balanced"
        case .batterySaver: return "Battery Saver"
        }
    }
}

enum BatteryBehavior: String, Codable, CaseIterable, Identifiable, Sendable {
    case continueNormally, reduceQuality, pause
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .continueNormally: return "Continue normally"
        case .reduceQuality: return "Reduce playback quality"
        case .pause: return "Pause live wallpaper"
        }
    }
}

struct PlaybackSettings: Codable, Equatable, Sendable {
    var defaultFitMode: FitMode = .fill
    var allowAudio: Bool = false
    var quality: PlaybackQuality = .auto
    var batteryBehavior: BatteryBehavior = .reduceQuality
    var pauseInLowPowerMode: Bool = true
    var pauseWhenAppFullScreen: Bool = true

    init() {}

    // Tolerant decoding so new keys can be added without invalidating saved settings.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultFitMode = try c.decodeIfPresent(FitMode.self, forKey: .defaultFitMode) ?? .fill
        allowAudio = try c.decodeIfPresent(Bool.self, forKey: .allowAudio) ?? false
        quality = try c.decodeIfPresent(PlaybackQuality.self, forKey: .quality) ?? .auto
        batteryBehavior = try c.decodeIfPresent(BatteryBehavior.self, forKey: .batteryBehavior) ?? .reduceQuality
        pauseInLowPowerMode = try c.decodeIfPresent(Bool.self, forKey: .pauseInLowPowerMode) ?? true
        pauseWhenAppFullScreen = try c.decodeIfPresent(Bool.self, forKey: .pauseWhenAppFullScreen) ?? true
    }
}
