import Foundation

/// Second-phase feature. The data model exists now so persistence never needs a migration.
enum PlaylistMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case sequential, shuffle
    var id: String { rawValue }
    var displayName: String { self == .sequential ? "Sequential" : "Shuffle" }
}

enum PlaylistInterval: Codable, Equatable, Hashable, Sendable {
    case minutes(Int)
    case custom(TimeInterval)

    static let presets: [PlaylistInterval] = [.minutes(5), .minutes(15), .minutes(30), .minutes(60)]

    var seconds: TimeInterval {
        switch self {
        case .minutes(let m): return TimeInterval(m * 60)
        case .custom(let s): return s
        }
    }

    var displayName: String {
        switch self {
        case .minutes(let m): return m >= 60 ? "\(m / 60) hour" : "\(m) min"
        case .custom(let s): return FileUtilities.formattedDuration(s)
        }
    }
}

struct Playlist: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var assetIDs: [UUID]
    var mode: PlaylistMode
    var interval: PlaylistInterval

    init(id: UUID = UUID(), name: String, assetIDs: [UUID] = [], mode: PlaylistMode = .sequential, interval: PlaylistInterval = .minutes(30)) {
        self.id = id
        self.name = name
        self.assetIDs = assetIDs
        self.mode = mode
        self.interval = interval
    }
}
