import AppKit
import Observation

/// Drives one wallpaper window + player per active display. The engine reconciles the
/// desired state (displays × assignments × settings) with what is on screen and only
/// touches contexts whose display, asset, or fit mode actually changed.
@MainActor
@Observable
final class WallpaperEngine {
    /// Per-display playback context.
    @MainActor
    final class Context {
        private(set) var display: DisplayConfiguration
        let window: WallpaperWindow
        let view: WallpaperPlayerView
        let player = WallpaperPlayer()
        var assetID: UUID?

        init(display: DisplayConfiguration, screen: NSScreen) {
            self.display = display
            window = WallpaperWindow(screen: screen)
            view = WallpaperPlayerView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.playerLayer.player = player.player
            window.contentView = view
        }

        func updateDisplay(_ display: DisplayConfiguration) {
            self.display = display
        }

        func tearDown() {
            player.tearDown()
            view.playerLayer.player = nil
            window.orderOut(nil)
            window.contentView = nil
        }
    }

    private(set) var contexts: [String: Context] = [:]
    private(set) var isPausedByUser = false
    /// Reasons playback is currently suppressed by the system (battery, fullscreen, lock…).
    private(set) var suppressions: Set<Suppression> = []

    enum Suppression: String, Sendable { case userPaused, lowPower, battery, fullScreenApp, screenLocked, asleep }

    private let library: VideoAssetManager
    private let preferences: PreferencesStore
    private let displays: DisplayManager
    private let playlists: PlaylistCoordinator
    private var started = false

    init(library: VideoAssetManager, preferences: PreferencesStore, displays: DisplayManager,
         playlists: PlaylistCoordinator) {
        self.library = library
        self.preferences = preferences
        self.displays = displays
        self.playlists = playlists
    }

    var isPlaying: Bool { started && suppressions.isEmpty && contexts.values.contains { $0.assetID != nil } }
    var activeAssetIDs: Set<UUID> { Set(contexts.values.compactMap(\.assetID)) }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        Log.playback.info("Engine started")
        playlists.start()
        observeAndReconcile()
    }

    func stop() {
        started = false
        playlists.stop()
        for ctx in contexts.values { ctx.tearDown() }
        contexts.removeAll()
        Log.playback.info("Engine stopped")
    }

    /// Re-runs reconcile whenever any observed input changes (Observation tracking).
    private func observeAndReconcile() {
        guard started else { return }
        withObservationTracking {
            reconcile()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeAndReconcile() }
        }
    }

    // MARK: Reconcile

    func reconcile() {
        let settings = preferences.settings
        let current = displays.displays
        _ = library.assets              // tracked so deletions/imports trigger reconcile
        _ = playlists.generation        // tracked so a playlist rotation triggers reconcile

        // Remove contexts for displays that vanished.
        for (id, ctx) in contexts where !current.contains(where: { $0.id == id }) {
            Log.displays.info("Display removed: \(ctx.display.name, privacy: .public)")
            ctx.tearDown()
            contexts[id] = nil
        }

        for display in current {
            guard let screen = displays.screen(for: display) else { continue }
            let assignment = settings.desktop.assignment(for: display.id)
            // Resolves a playlist to whichever wallpaper is its turn right now.
            let asset = playlists.resolveAsset(for: assignment)

            // Nothing assigned → make sure no window is shown for this display.
            guard let asset else {
                if let ctx = contexts[display.id] {
                    ctx.tearDown()
                    contexts[display.id] = nil
                }
                continue
            }

            var ctx = contexts[display.id]
            if let existing = ctx, existing.display.frame != display.frame || existing.display.backingScaleFactor != display.backingScaleFactor {
                // Geometry changed (resolution / scaling / arrangement): move the window, keep the player.
                existing.window.setFrame(screen.frame, display: true)
                existing.view.frame = NSRect(origin: .zero, size: screen.frame.size)
                existing.view.needsLayout = true
                existing.updateDisplay(display)
                Log.displays.info("Display geometry updated: \(display.name, privacy: .public) \(display.pointResolutionLabel, privacy: .public)")
            }
            if ctx == nil {
                let new = Context(display: display, screen: screen)
                contexts[display.id] = new
                ctx = new
                Log.playback.info("Created wallpaper window for \(display.name, privacy: .public) \(display.pointResolutionLabel, privacy: .public) @\(display.scaleLabel, privacy: .public)")
            }
            guard let ctx else { continue }

            let fit = assignment?.fitMode ?? settings.playback.defaultFitMode
            if ctx.view.fitMode != fit { ctx.view.fitMode = fit }
            let pixelSize = CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
            if ctx.view.videoPixelSize != pixelSize { ctx.view.videoPixelSize = pixelSize }

            if ctx.assetID != asset.id {
                ctx.assetID = asset.id
                ctx.player.load(url: library.mediaURL(for: asset))
            }
            ctx.player.isMuted = !settings.playback.allowAudio
            ctx.window.show()
        }
        applyPlaybackState()
    }

    // MARK: Pause / resume

    /// Replaces the full suppression set (SystemCoordinator owns the policy decision).
    func applySuppressions(_ new: Set<Suppression>) {
        guard new != suppressions else { return }
        suppressions = new
        isPausedByUser = new.contains(.userPaused)
        let list = new.map(\.rawValue).sorted().joined(separator: ",")
        Log.playback.info("Suppressions: [\(list, privacy: .public)]")
        applyPlaybackState()
    }

    private func applyPlaybackState() {
        let shouldPlay = suppressions.isEmpty
        for ctx in contexts.values {
            if shouldPlay { ctx.player.play() } else { ctx.player.pause() }
        }
        // A paused wallpaper should not keep cycling through a playlist unseen.
        playlists.setSuspended(!shouldPlay)
    }

    /// After wake/unlock: make sure every window is still ordered in and on the right screen.
    func validateWindows() {
        displays.refresh()
        for ctx in contexts.values {
            if let screen = displays.screen(for: ctx.display), ctx.window.frame != screen.frame {
                ctx.window.setFrame(screen.frame, display: true)
            }
            if !ctx.window.isVisible { ctx.window.show() }
        }
        observeAndReconcile()
    }
}
