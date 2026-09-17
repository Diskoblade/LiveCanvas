import Foundation

/// What a display should show: a single wallpaper, or a playlist that rotates.
/// Persisted shape stays backwards compatible with the single-asset form that earlier
/// builds wrote (`{"assetID": "…"}`), so an existing settings.json keeps working.
struct WallpaperAssignment: Codable, Equatable, Sendable {
    var assetID: UUID?
    var playlistID: UUID?
    var fitMode: FitMode?          // nil → use PlaybackSettings.defaultFitMode

    init(assetID: UUID? = nil, playlistID: UUID? = nil, fitMode: FitMode? = nil) {
        self.assetID = assetID
        self.playlistID = playlistID
        self.fitMode = fitMode
    }

    static func asset(_ id: UUID, fitMode: FitMode? = nil) -> WallpaperAssignment {
        WallpaperAssignment(assetID: id, fitMode: fitMode)
    }

    static func playlist(_ id: UUID, fitMode: FitMode? = nil) -> WallpaperAssignment {
        WallpaperAssignment(playlistID: id, fitMode: fitMode)
    }

    var isPlaylist: Bool { playlistID != nil }

    /// True when this assignment points at nothing playable.
    var isEmpty: Bool { assetID == nil && playlistID == nil }
}

/// Desktop assignment set. `useSameOnAllDisplays` + `global` covers the common case;
/// `perDisplay` is keyed by DisplayConfiguration.id.
struct DesktopAssignments: Codable, Equatable, Sendable {
    var useSameOnAllDisplays: Bool = true
    var global: WallpaperAssignment?
    var perDisplay: [String: WallpaperAssignment] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        useSameOnAllDisplays = try c.decodeIfPresent(Bool.self, forKey: .useSameOnAllDisplays) ?? true
        global = try c.decodeIfPresent(WallpaperAssignment.self, forKey: .global)
        perDisplay = try c.decodeIfPresent([String: WallpaperAssignment].self, forKey: .perDisplay) ?? [:]
    }

    func assignment(for displayID: String) -> WallpaperAssignment? {
        if useSameOnAllDisplays { return global }
        return perDisplay[displayID] ?? global
    }

    /// Every assignment currently in use, global and per-display.
    var all: [WallpaperAssignment] {
        ([global].compactMap { $0 }) + Array(perDisplay.values)
    }

    /// True if any display references the asset directly (not via a playlist).
    func references(_ assetID: UUID) -> Bool {
        all.contains { $0.assetID == assetID }
    }

    func referencesPlaylist(_ playlistID: UUID) -> Bool {
        all.contains { $0.playlistID == playlistID }
    }

    mutating func remove(assetID: UUID) {
        if global?.assetID == assetID { global = nil }
        perDisplay = perDisplay.filter { $0.value.assetID != assetID }
    }

    mutating func removePlaylist(_ playlistID: UUID) {
        if global?.playlistID == playlistID { global = nil }
        perDisplay = perDisplay.filter { $0.value.playlistID != playlistID }
    }
}
