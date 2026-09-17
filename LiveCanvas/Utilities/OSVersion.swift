import Foundation

/// Thin wrapper around `ProcessInfo.operatingSystemVersion` that is easy to stub in tests.
struct OSVersion: Equatable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    static var current: OSVersion {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return OSVersion(major: v.majorVersion, minor: v.minorVersion, patch: v.patchVersion)
    }

    var description: String { "\(major).\(minor).\(patch)" }

    /// macOS 26 Tahoe is the first release whose Lock Screen store has been validated.
    var isTahoe: Bool { major == 26 }
}
