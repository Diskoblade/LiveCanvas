import Foundation

/// Where a playlist is in its rotation. Persisted so a relaunch resumes rather than
/// restarting from the first video, and so a due change is applied immediately on launch.
struct PlaylistState: Codable, Equatable, Sendable {
    var index: Int = 0
    var lastAdvance: Date = .distantPast
    /// Shuffle order, regenerated whenever the playlist's contents change.
    var shuffledOrder: [UUID] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = try c.decodeIfPresent(Int.self, forKey: .index) ?? 0
        lastAdvance = try c.decodeIfPresent(Date.self, forKey: .lastAdvance) ?? .distantPast
        shuffledOrder = try c.decodeIfPresent([UUID].self, forKey: .shuffledOrder) ?? []
    }
}
