import Foundation
import Observation

/// Drives playlist rotation. Holds a single timer scheduled for the soonest due change
/// rather than polling, and persists rotation state so a relaunch resumes in place.
@MainActor
@Observable
final class PlaylistCoordinator {
    private let preferences: PreferencesStore
    private let library: VideoAssetManager
    private var timer: Task<Void, Never>?
    /// Bumped on every rotation so the engine's observation tracking re-runs reconcile.
    private(set) var generation: Int = 0
    private var isSuspended = false

    init(preferences: PreferencesStore, library: VideoAssetManager) {
        self.preferences = preferences
        self.library = library
    }

    isolated deinit { timer?.cancel() }

    // MARK: Resolution

    func playlist(id: UUID?) -> Playlist? {
        guard let id else { return nil }
        return preferences.settings.playlists.first { $0.id == id }
    }

    /// The asset an assignment currently resolves to, following a playlist if needed.
    func resolveAsset(for assignment: WallpaperAssignment?) -> WallpaperAsset? {
        guard let assignment else { return nil }
        if let playlistID = assignment.playlistID {
            guard let playlist = playlist(id: playlistID) else { return nil }
            let state = preferences.settings.playlistState(playlistID)
            // Skip entries whose media has been deleted from the library.
            let order = PlaylistRotation.resolvedOrder(playlist: playlist, state: state)
                .filter { library.asset(id: $0) != nil }
            guard !order.isEmpty else { return nil }
            let index = PlaylistRotation.wrap(state.index, count: order.count)
            return library.asset(id: order[index])
        }
        return library.asset(id: assignment.assetID)
    }

    // MARK: Scheduling

    /// Applies any rotation that fell due while the app was closed or asleep, then
    /// schedules the next one. Safe to call repeatedly.
    func start() {
        applyDueRotations()
        scheduleNext()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Rotation pauses with playback: a paused or suppressed wallpaper should not be
    /// silently cycling in the background.
    func setSuspended(_ suspended: Bool) {
        guard suspended != isSuspended else { return }
        isSuspended = suspended
        if suspended { stop() } else { start() }
    }

    /// Playlists referenced by a current desktop assignment.
    private var activePlaylists: [Playlist] {
        let ids = Set(preferences.settings.desktop.all.compactMap(\.playlistID))
        return preferences.settings.playlists.filter { ids.contains($0.id) }
    }

    private func applyDueRotations() {
        let now = Date()
        var changed = false
        var generator = SystemRandomNumberGenerator()
        var states = preferences.settings.playlistStates

        for playlist in activePlaylists {
            var state = states[playlist.id.uuidString] ?? PlaylistState()
            // A brand new playlist starts its clock now instead of appearing overdue.
            if state.lastAdvance == .distantPast {
                state.lastAdvance = now
                if PlaylistRotation.needsReshuffle(playlist: playlist, state: state) {
                    state.shuffledOrder = PlaylistRotation.shuffle(playlist.assetIDs, using: &generator)
                }
                states[playlist.id.uuidString] = state
                changed = true
                continue
            }
            if PlaylistRotation.isDue(playlist: playlist, state: state, now: now) {
                states[playlist.id.uuidString] = PlaylistRotation.advance(playlist: playlist, state: state, now: now, using: &generator)
                changed = true
                Log.playback.info("Playlist \(playlist.name, privacy: .public) advanced")
            }
        }

        guard changed else { return }
        preferences.update { $0.playlistStates = states }
        generation &+= 1
    }

    private func scheduleNext() {
        timer?.cancel()
        guard !isSuspended else { return }
        let now = Date()
        let due = activePlaylists.compactMap {
            PlaylistRotation.nextChange(playlist: $0, state: preferences.settings.playlistState($0.id), now: now)
        }.min()
        guard let due else { return }

        let delay = max(due.timeIntervalSince(now), 1)
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.start()
        }
    }

    // MARK: Manual control

    /// Advances every active playlist immediately (menu bar "Next Wallpaper").
    @discardableResult
    func advanceNow() -> Bool {
        let playlists = activePlaylists
        guard !playlists.isEmpty else { return false }
        var generator = SystemRandomNumberGenerator()
        let now = Date()
        var states = preferences.settings.playlistStates
        for playlist in playlists {
            let state = states[playlist.id.uuidString] ?? PlaylistState()
            states[playlist.id.uuidString] = PlaylistRotation.advance(playlist: playlist, state: state, now: now, using: &generator)
        }
        preferences.update { $0.playlistStates = states }
        generation &+= 1
        scheduleNext()
        return true
    }

    /// Called after a playlist is edited so its schedule and shuffle order stay valid.
    func playlistDidChange(_ playlistID: UUID) {
        guard let playlist = playlist(id: playlistID) else { return }
        var generator = SystemRandomNumberGenerator()
        var state = preferences.settings.playlistState(playlistID)
        if PlaylistRotation.needsReshuffle(playlist: playlist, state: state) {
            let showing = PlaylistRotation.currentAssetID(playlist: playlist, state: state)
            state.shuffledOrder = PlaylistRotation.shuffle(playlist.assetIDs, avoidingFirst: showing, using: &generator)
        }
        state.index = PlaylistRotation.wrap(state.index, count: max(playlist.assetIDs.count, 1))
        preferences.update { $0.setPlaylistState(state, for: playlistID) }
        generation &+= 1
        scheduleNext()
    }
}
