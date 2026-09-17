import Foundation

/// Everything persisted in settings.json. Versioned for forward migrations.
///
/// Decoding is defensive **per field**: a single malformed value falls back to its
/// default instead of throwing, which would discard every other setting the user has.
struct AppSettings: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int = AppSettings.currentVersion
    var playback = PlaybackSettings()
    var desktop = DesktopAssignments()
    var lockScreen = LockScreenPreferences()
    var playlists: [Playlist] = []
    /// Rotation state per playlist, keyed by the playlist's UUID string.
    /// A `[UUID: …]` dictionary would encode as an interleaved array rather than a JSON
    /// object, which makes the file hard to read and easy to hand-edit incorrectly.
    var playlistStates: [String: PlaylistState] = [:]
    var startAtLogin: Bool = false
    var showInMenuBar: Bool = true
    /// Sidebar section to restore on launch.
    var lastSection: String = SidebarSection.library.rawValue

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        /// Decodes one field, falling back to `fallback` and logging if it is malformed.
        func lenient<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            do {
                return try c.decodeIfPresent(T.self, forKey: key) ?? fallback
            } catch {
                Log.persistence.error("Ignoring malformed settings field '\(key.stringValue, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                return fallback
            }
        }

        version = lenient(.version, 1)
        playback = lenient(.playback, PlaybackSettings())
        desktop = lenient(.desktop, DesktopAssignments())
        lockScreen = lenient(.lockScreen, LockScreenPreferences())
        playlists = lenient(.playlists, [])
        playlistStates = lenient(.playlistStates, [:])
        startAtLogin = lenient(.startAtLogin, false)
        showInMenuBar = lenient(.showInMenuBar, true)
        lastSection = lenient(.lastSection, SidebarSection.library.rawValue)
    }

    // MARK: Playlist state accessors

    func playlistState(_ id: UUID) -> PlaylistState {
        playlistStates[id.uuidString] ?? PlaylistState()
    }

    mutating func setPlaylistState(_ state: PlaylistState, for id: UUID) {
        playlistStates[id.uuidString] = state
    }

    mutating func removePlaylistState(_ id: UUID) {
        playlistStates[id.uuidString] = nil
    }
}
