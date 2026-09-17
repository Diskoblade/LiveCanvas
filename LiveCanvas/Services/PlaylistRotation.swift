import Foundation

/// Pure rotation logic for playlists, kept free of timers and AppKit so every branch is
/// unit-testable. The coordinator owns the clock; this owns the decisions.
enum PlaylistRotation {

    /// The asset a playlist should be showing, given its state.
    /// Returns nil for an empty playlist.
    static func currentAssetID(playlist: Playlist, state: PlaylistState) -> UUID? {
        let order = resolvedOrder(playlist: playlist, state: state)
        guard !order.isEmpty else { return nil }
        return order[wrap(state.index, count: order.count)]
    }

    /// The order to play in: the playlist's own order, or the stored shuffle when it is
    /// still valid for the current contents. A stale shuffle is ignored rather than
    /// silently dropping or repeating videos.
    static func resolvedOrder(playlist: Playlist, state: PlaylistState) -> [UUID] {
        guard playlist.mode == .shuffle else { return playlist.assetIDs }
        guard !state.shuffledOrder.isEmpty,
              Set(state.shuffledOrder) == Set(playlist.assetIDs),
              state.shuffledOrder.count == playlist.assetIDs.count else {
            return playlist.assetIDs
        }
        return state.shuffledOrder
    }

    /// True when the shuffle order stored in `state` no longer matches the playlist.
    static func needsReshuffle(playlist: Playlist, state: PlaylistState) -> Bool {
        guard playlist.mode == .shuffle else { return false }
        return state.shuffledOrder.count != playlist.assetIDs.count
            || Set(state.shuffledOrder) != Set(playlist.assetIDs)
    }

    /// A fresh shuffle. When possible the first entry differs from `avoidingFirst`, so
    /// re-shuffling does not visibly replay the video that was already on screen.
    static func shuffle(_ assetIDs: [UUID], avoidingFirst: UUID? = nil,
                        using generator: inout some RandomNumberGenerator) -> [UUID] {
        guard assetIDs.count > 1 else { return assetIDs }
        var order = assetIDs.shuffled(using: &generator)
        if let avoid = avoidingFirst, order.first == avoid, let swap = order.indices.dropFirst().randomElement(using: &generator) {
            order.swapAt(0, swap)
        }
        return order
    }

    /// Whether the playlist is due to move on, and by how long it has been overdue.
    static func isDue(playlist: Playlist, state: PlaylistState, now: Date) -> Bool {
        guard playlist.assetIDs.count > 1 else { return false }
        return now.timeIntervalSince(state.lastAdvance) >= playlist.interval.seconds
    }

    /// When the next change is due. `nil` when the playlist never rotates.
    static func nextChange(playlist: Playlist, state: PlaylistState, now: Date) -> Date? {
        guard playlist.assetIDs.count > 1 else { return nil }
        let due = state.lastAdvance.addingTimeInterval(playlist.interval.seconds)
        return max(due, now)
    }

    /// Advances one step, reshuffling at the end of a shuffled pass.
    static func advance(playlist: Playlist, state: PlaylistState, now: Date,
                        using generator: inout some RandomNumberGenerator) -> PlaylistState {
        var next = state
        next.lastAdvance = now
        let count = playlist.assetIDs.count
        guard count > 1 else {
            next.index = 0
            return next
        }

        if playlist.mode == .shuffle {
            if needsReshuffle(playlist: playlist, state: next) {
                let showing = currentAssetID(playlist: playlist, state: state)
                next.shuffledOrder = shuffle(playlist.assetIDs, avoidingFirst: showing, using: &generator)
                next.index = 0
                return next
            }
            let advanced = state.index + 1
            if advanced >= count {
                // End of the pass: reshuffle so the next cycle is a different order.
                let showing = currentAssetID(playlist: playlist, state: state)
                next.shuffledOrder = shuffle(playlist.assetIDs, avoidingFirst: showing, using: &generator)
                next.index = 0
            } else {
                next.index = advanced
            }
            return next
        }

        next.index = wrap(state.index + 1, count: count)
        return next
    }

    /// Normalises an index that may be out of range after the playlist was edited.
    static func wrap(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let m = index % count
        return m < 0 ? m + count : m
    }
}
