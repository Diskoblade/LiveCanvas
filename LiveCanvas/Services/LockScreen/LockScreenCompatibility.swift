import Foundation

/// Gates the undocumented Lock Screen integration on the OS version.
/// macOS 27 is not assumed to behave like macOS 26: an unknown major version disables the
/// feature and says why, rather than writing to a store whose layout has not been validated.
struct LockScreenCompatibility: Sendable, Equatable {
    enum Support: Equatable, Sendable {
        case supported
        case unsupportedOS(String)
    }

    /// The only macOS major version whose Aerial store layout LiveCanvas has validated.
    static let validatedMajorVersion = 26

    var osVersion: OSVersion
    var support: Support

    static var current: LockScreenCompatibility { LockScreenCompatibility(osVersion: .current) }

    init(osVersion: OSVersion) {
        self.osVersion = osVersion
        switch osVersion.major {
        case Self.validatedMajorVersion:
            support = .supported
        case ..<Self.validatedMajorVersion:
            support = .unsupportedOS("Live Lock Screen wallpapers need macOS \(Self.validatedMajorVersion) Tahoe or later. This Mac runs macOS \(osVersion.major).\(osVersion.minor).")
        default:
            support = .unsupportedOS("LiveCanvas has only validated the Lock Screen wallpaper store on macOS \(Self.validatedMajorVersion). macOS \(osVersion.major) may store wallpapers differently, so the feature is disabled to avoid damaging it. Desktop wallpapers are unaffected.")
        }
    }

    var isSupported: Bool { support == .supported }

    var explanation: String? {
        if case .unsupportedOS(let reason) = support { return reason }
        return nil
    }
}
