import Testing
import AppKit
import AVFoundation
@testable import LiveCanvas

/// Lifecycle and leak checks for the wallpaper engine and players.
/// Serialized: these build real AVPlayers and NSWindows, and running them concurrently
/// with each other contends for hardware video decoders.
@MainActor
@Suite(.serialized)
struct EngineLifecycleTests {

    /// Polls `condition` until it holds or the deadline passes. Returns whether it held.
    private func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    private func sandbox() throws -> (URL, VideoAssetManager, PreferencesStore) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lc-engine-\(UUID().uuidString)")
        let media = dir.appendingPathComponent("Media"), thumbs = dir.appendingPathComponent("Thumbnails")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbs, withIntermediateDirectories: true)
        let library = VideoAssetManager(store: LibraryStore(fileURL: dir.appendingPathComponent("library.json")),
                                        mediaDirectory: media, thumbnailDirectory: thumbs)
        let prefs = PreferencesStore(fileURL: dir.appendingPathComponent("settings.json"))
        return (dir, library, prefs)
    }

    // MARK: WallpaperPlayer

    @Test func playerReleasesItsLooperAndItemsOnTearDown() async throws {
        let video = try await SyntheticAerialStore.makeVideo()
        defer { try? FileManager.default.removeItem(at: video) }

        let player = WallpaperPlayer()
        player.load(url: video)
        #expect(player.currentURL == video)
        #expect(player.hasLooper)
        // AVPlayerLooper enqueues its copies asynchronously, so give it a moment rather
        // than asserting on the queue the instant load() returns.
        #expect(await waitUntil { player.player.items().isEmpty == false },
                "the looper should enqueue at least one item")

        player.tearDown()
        #expect(player.currentURL == nil)
        #expect(!player.hasLooper, "the looper must be released so its retain cycle with the queue player is broken")
        #expect(player.player.items().isEmpty, "queue must be drained so AVPlayerItems can deallocate")
    }

    @Test func repeatedCreateLoadTearDownDoesNotAccumulatePlayers() async throws {
        // A leak here would show up as an ever-growing queue across cycles. The players are
        // kept paused so the test does not open several hardware decode sessions at once.
        let video = try await SyntheticAerialStore.makeVideo()
        defer { try? FileManager.default.removeItem(at: video) }
        for _ in 0..<5 {
            let player = WallpaperPlayer()
            player.pause()
            player.load(url: video)
            #expect(player.player.items().count <= 4, "each cycle must start from a clean queue")
            player.tearDown()
            #expect(player.player.items().isEmpty)
            #expect(!player.hasLooper)
        }
    }

    @Test func reloadingTheSameURLIsANoOp() async throws {
        let video = try await SyntheticAerialStore.makeVideo()
        defer { try? FileManager.default.removeItem(at: video) }
        let player = WallpaperPlayer()
        player.load(url: video)
        let first = player.player.currentItem
        player.load(url: video)
        #expect(player.player.currentItem === first, "re-assigning the same video must not restart playback")
        player.tearDown()
    }

    @Test func switchingVideosDoesNotAccumulateItems() async throws {
        let a = try await SyntheticAerialStore.makeVideo(width: 160, height: 90)
        let b = try await SyntheticAerialStore.makeVideo(width: 192, height: 108)
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        let player = WallpaperPlayer()
        for _ in 0..<8 {
            player.load(url: a)
            player.load(url: b)
        }
        // AVPlayerLooper keeps a small fixed queue; it must not grow with each switch.
        #expect(player.player.items().count <= 4)
        player.tearDown()
        #expect(player.player.items().isEmpty)
    }

    @Test func pauseStateSurvivesALoad() async throws {
        let video = try await SyntheticAerialStore.makeVideo()
        defer { try? FileManager.default.removeItem(at: video) }
        let player = WallpaperPlayer()
        player.pause()
        player.load(url: video)
        #expect(player.isPaused)
        #expect(player.player.rate == 0, "a paused wallpaper must not start playing when its video changes")
        player.play()
        #expect(!player.isPaused)
        player.tearDown()
    }

    // MARK: Engine reconcile

    @Test func engineCreatesOneContextPerAssignedDisplayAndNoMore() async throws {
        let (dir, library, prefs) = try sandbox()
        defer { try? FileManager.default.removeItem(at: dir) }
        let video = try await SyntheticAerialStore.makeVideo()
        defer { try? FileManager.default.removeItem(at: video) }
        let asset = try #require(await library.importFile(video))

        let displays = DisplayManager()
        let engine = WallpaperEngine(library: library, preferences: prefs, displays: displays,
                                     playlists: PlaylistCoordinator(preferences: prefs, library: library))

        // Nothing assigned yet: no windows.
        engine.reconcile()
        #expect(engine.contexts.isEmpty)

        prefs.update { $0.desktop.useSameOnAllDisplays = true
                       $0.desktop.global = .asset(asset.id, fitMode: .fill) }
        engine.reconcile()
        #expect(engine.contexts.count == displays.displays.count)
        #expect(engine.activeAssetIDs == [asset.id])

        // Reconciling repeatedly must not create duplicates.
        let players = engine.contexts.mapValues { ObjectIdentifier($0.player) }
        for _ in 0..<5 { engine.reconcile() }
        #expect(engine.contexts.count == displays.displays.count)
        #expect(engine.contexts.mapValues { ObjectIdentifier($0.player) } == players,
                "reconcile must reuse existing players rather than rebuilding them")

        engine.stop()
        #expect(engine.contexts.isEmpty)
    }

    @Test func clearingAnAssignmentRemovesTheWindow() async throws {
        let (dir, library, prefs) = try sandbox()
        defer { try? FileManager.default.removeItem(at: dir) }
        let video = try await SyntheticAerialStore.makeVideo()
        defer { try? FileManager.default.removeItem(at: video) }
        let asset = try #require(await library.importFile(video))

        let engine = WallpaperEngine(library: library, preferences: prefs, displays: DisplayManager(),
                                     playlists: PlaylistCoordinator(preferences: prefs, library: library))
        prefs.update { $0.desktop.global = .asset(asset.id) }
        engine.reconcile()
        #expect(!engine.contexts.isEmpty)

        prefs.update { $0.desktop.global = nil }
        engine.reconcile()
        #expect(engine.contexts.isEmpty, "removing the assignment must tear the window down")
        engine.stop()
    }

    @Test func deletingTheAssignedAssetStopsPlayback() async throws {
        let (dir, library, prefs) = try sandbox()
        defer { try? FileManager.default.removeItem(at: dir) }
        let video = try await SyntheticAerialStore.makeVideo()
        defer { try? FileManager.default.removeItem(at: video) }
        let asset = try #require(await library.importFile(video))

        let engine = WallpaperEngine(library: library, preferences: prefs, displays: DisplayManager(),
                                     playlists: PlaylistCoordinator(preferences: prefs, library: library))
        prefs.update { $0.desktop.global = .asset(asset.id) }
        engine.reconcile()
        #expect(!engine.contexts.isEmpty)

        library.delete(asset)
        engine.reconcile()
        #expect(engine.contexts.isEmpty, "a deleted asset must not leave an orphan window")
        engine.stop()
    }

    @Test func suppressionsPauseAndResumeEveryContext() async throws {
        let (dir, library, prefs) = try sandbox()
        defer { try? FileManager.default.removeItem(at: dir) }
        let video = try await SyntheticAerialStore.makeVideo()
        defer { try? FileManager.default.removeItem(at: video) }
        let asset = try #require(await library.importFile(video))

        let engine = WallpaperEngine(library: library, preferences: prefs, displays: DisplayManager(),
                                     playlists: PlaylistCoordinator(preferences: prefs, library: library))
        prefs.update { $0.desktop.global = .asset(asset.id) }
        engine.reconcile()

        engine.applySuppressions([.screenLocked])
        #expect(engine.contexts.values.allSatisfy { $0.player.isPaused })
        engine.applySuppressions(Set<WallpaperEngine.Suppression>())
        #expect(engine.contexts.values.allSatisfy { !$0.player.isPaused })
        engine.stop()
    }

    @Test func stoppedEngineTearsDownItsWindows() async throws {
        // NSWindow deallocation is deferred by AppKit, so asserting on a weak reference is
        // unreliable. Assert the observable contract instead: the window is orderd out, its
        // content view and player are detached, and the engine drops every context.
        let (dir, library, prefs) = try sandbox()
        defer { try? FileManager.default.removeItem(at: dir) }
        let video = try await SyntheticAerialStore.makeVideo()
        defer { try? FileManager.default.removeItem(at: video) }
        let asset = try #require(await library.importFile(video))

        let engine = WallpaperEngine(library: library, preferences: prefs, displays: DisplayManager(),
                                     playlists: PlaylistCoordinator(preferences: prefs, library: library))
        prefs.update { $0.desktop.global = .asset(asset.id) }
        engine.reconcile()
        let context = try #require(engine.contexts.values.first)
        let window = context.window
        #expect(window.isVisible)
        #expect(window.contentView != nil)

        engine.stop()

        #expect(engine.contexts.isEmpty)
        #expect(!window.isVisible, "the window must be ordered out")
        #expect(window.contentView == nil, "the player view must be detached")
        #expect(context.player.currentURL == nil, "the player must be torn down")
        #expect(context.player.player.items().isEmpty)
        #expect(context.view.playerLayer.player == nil, "the layer must not keep the player alive")
    }

    @Test func wallpaperWindowHasTheRequiredDesktopBehaviour() {
        let screen = try! #require(NSScreen.main)
        let window = WallpaperWindow(screen: screen)
        #expect(!window.canBecomeKey, "must never take keyboard focus")
        #expect(!window.canBecomeMain)
        #expect(window.ignoresMouseEvents, "clicks must pass through to the desktop")
        #expect(window.isExcludedFromWindowsMenu)
        #expect(window.level == WallpaperWindow.desktopLevel)
        #expect(window.level.rawValue < NSWindow.Level.normal.rawValue, "must sit below ordinary windows")
        #expect(window.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(window.collectionBehavior.contains(.stationary))
        #expect(window.collectionBehavior.contains(.ignoresCycle), "must not appear in window cycling")
        #expect(window.collectionBehavior.contains(.fullScreenNone))
        #expect(!window.hasShadow)
        #expect(window.styleMask.contains(.borderless))
        #expect(window.sharingType == .readOnly, "screenshots and screen sharing must show the wallpaper")
        window.close()
    }

    // MARK: Preview player

    @Test func previewPlayerKeepsOnlyOneVideoAlive() async throws {
        let a = try await SyntheticAerialStore.makeVideo(width: 160, height: 90)
        let b = try await SyntheticAerialStore.makeVideo(width: 192, height: 108)
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }

        func asset(_ id: UUID) -> WallpaperAsset {
            WallpaperAsset(id: id, displayName: "x", sourceURL: nil, managedFileName: "x.mp4", thumbnailFileName: nil,
                           kind: .video, duration: 1, pixelWidth: 160, pixelHeight: 90, frameRate: 24, codec: .h264,
                           codecFourCC: "avc1", dynamicRange: .sdr, hasAudio: false, fileSize: 1, dateImported: Date())
        }
        let preview = PreviewPlayer()
        let first = asset(UUID()), second = asset(UUID())

        preview.play(asset: first, url: a)
        #expect(preview.currentAssetID == first.id)
        #expect(preview.player.isMuted, "previews are always silent")

        preview.play(asset: second, url: b)
        #expect(preview.currentAssetID == second.id)
        #expect(preview.player.items().count <= 4, "switching previews must not stack players")

        // Stopping a different asset must not disturb the running one.
        preview.stop(if: first.id)
        #expect(preview.currentAssetID == second.id)

        preview.stop()
        #expect(preview.currentAssetID == nil)
        #expect(preview.player.items().isEmpty)
    }
}
