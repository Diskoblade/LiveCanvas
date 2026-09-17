import Foundation

/// Preferences for the Lock Screen feature (persisted).
struct LockScreenPreferences: Codable, Equatable, Sendable {
    var enabled: Bool = false
    var useDesktopWallpaper: Bool = true
    var assetID: UUID?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        useDesktopWallpaper = try c.decodeIfPresent(Bool.self, forKey: .useDesktopWallpaper) ?? true
        assetID = try c.decodeIfPresent(UUID.self, forKey: .assetID)
    }
}

/// Runtime status reported by the installer (not persisted directly).
enum LockScreenStatus: Equatable, Sendable {
    case checking
    case unsupported(reason: String)
    case ready                       // store validated, Apple wallpaper in place
    case installed(assetID: UUID, installedAt: Date)
    case needsAttention(reason: String)

    var isInstalled: Bool {
        if case .installed = self { return true }
        return false
    }
}
