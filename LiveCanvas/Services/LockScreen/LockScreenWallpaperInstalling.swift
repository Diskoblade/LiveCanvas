import Foundation

/// What the app needs to install a video as the Lock Screen wallpaper.
/// The undocumented, OS-version-specific work lives entirely behind this protocol so a
/// future macOS can get a different implementation without touching the rest of the app.
protocol LockScreenWallpaperInstalling: Sendable {
    /// Read-only check: is this mechanism usable on this machine right now?
    func status() async -> LockScreenInstallerStatus

    /// Installs `videoURL` as the Lock Screen wallpaper. Must take a verified backup first
    /// and must refuse rather than risk corrupting the store.
    func install(request: LockScreenInstallRequest) async throws -> LockScreenInstallation

    /// Puts the Lock Screen back exactly as it was before `installation`.
    func restore(_ installation: LockScreenInstallation) async throws

    /// Restores the most recent installation, if any.
    func restoreLatest() async throws
}

struct LockScreenInstallRequest: Sendable {
    /// The library asset being installed (used for the name and for bookkeeping).
    var assetID: UUID
    var displayName: String
    /// The source video in LiveCanvas's own Media directory.
    var videoURL: URL
    /// Probe of that video, so the installer does not have to re-read it.
    var probe: VideoProbe
    /// Optional poster to show in System Settings.
    var posterURL: URL?
}

/// A record of one successful installation, persisted so Restore works across launches.
struct LockScreenInstallation: Codable, Equatable, Sendable {
    var backupID: UUID
    var aerialAssetID: String
    var libraryAssetID: UUID
    var displayName: String
    var installedAt: Date
    var osVersion: String
    /// Asset IDs the Lock Screen used before LiveCanvas changed it, per display.
    var previousAssetIDsByDisplay: [String: String]
    var addedFilePaths: [String]
}

enum LockScreenInstallerStatus: Equatable, Sendable {
    case unsupportedOS(String)
    case storeUnavailable(String)
    /// Usable. `warning` is non-blocking context, e.g. another tool has edited the store.
    case ready(warning: String?)

    var isReady: Bool { if case .ready = self { return true }; return false }

    var message: String? {
        switch self {
        case .unsupportedOS(let s), .storeUnavailable(let s): return s
        case .ready(let warning): return warning
        }
    }
}
