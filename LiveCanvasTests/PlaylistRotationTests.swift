import Testing
import Foundation
@testable import LiveCanvas

/// Deterministic generator so shuffle behaviour is reproducible in tests.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

struct PlaylistRotationTests {
    private let a = UUID(), b = UUID(), c = UUID()

    private func sequential(_ ids: [UUID], minutes: Int = 5) -> Playlist {
        Playlist(name: "P", assetIDs: ids, mode: .sequential, interval: .minutes(minutes))
    }

    // MARK: Sequential

    @Test func sequentialCyclesInOrderAndWrapsAround() {
        let playlist = sequential([a, b, c])
        var gen = SeededGenerator(seed: 1)
        var state = PlaylistState()
        var seen: [UUID] = []
        for _ in 0..<7 {
            seen.append(try! #require(PlaylistRotation.currentAssetID(playlist: playlist, state: state)))
            state = PlaylistRotation.advance(playlist: playlist, state: state, now: Date(), using: &gen)
        }
        #expect(seen == [a, b, c, a, b, c, a])
    }

    @Test func emptyPlaylistResolvesToNothing() {
        let playlist = sequential([])
        #expect(PlaylistRotation.currentAssetID(playlist: playlist, state: PlaylistState()) == nil)
        #expect(!PlaylistRotation.isDue(playlist: playlist, state: PlaylistState(), now: Date()))
        #expect(PlaylistRotation.nextChange(playlist: playlist, state: PlaylistState(), now: Date()) == nil)
    }

    @Test func singleEntryPlaylistNeverRotates() {
        let playlist = sequential([a])
        var gen = SeededGenerator(seed: 2)
        let state = PlaylistState()
        #expect(!PlaylistRotation.isDue(playlist: playlist, state: state, now: Date().addingTimeInterval(100_000)))
        #expect(PlaylistRotation.nextChange(playlist: playlist, state: state, now: Date()) == nil)
        let advanced = PlaylistRotation.advance(playlist: playlist, state: state, now: Date(), using: &gen)
        #expect(PlaylistRotation.currentAssetID(playlist: playlist, state: advanced) == a)
    }

    @Test func anIndexLeftOutOfRangeByAnEditIsWrapped() {
        // Playlist shrank from 3 to 2 while sitting on index 2.
        var state = PlaylistState(); state.index = 2
        let playlist = sequential([a, b])
        #expect(PlaylistRotation.currentAssetID(playlist: playlist, state: state) == a)
        #expect(PlaylistRotation.wrap(-1, count: 3) == 2)
        #expect(PlaylistRotation.wrap(0, count: 0) == 0)
    }

    // MARK: Timing

    @Test func dueOnlyAfterTheIntervalElapses() {
        let playlist = sequential([a, b], minutes: 5)
        var state = PlaylistState()
        let start = Date()
        state.lastAdvance = start
        #expect(!PlaylistRotation.isDue(playlist: playlist, state: state, now: start.addingTimeInterval(299)))
        #expect(PlaylistRotation.isDue(playlist: playlist, state: state, now: start.addingTimeInterval(300)))
        #expect(PlaylistRotation.isDue(playlist: playlist, state: state, now: start.addingTimeInterval(3000)))
    }

    @Test func nextChangeIsNeverInThePast() {
        let playlist = sequential([a, b], minutes: 5)
        var state = PlaylistState()
        let now = Date()
        state.lastAdvance = now.addingTimeInterval(-10_000)      // long overdue
        let next = try! #require(PlaylistRotation.nextChange(playlist: playlist, state: state, now: now))
        #expect(next >= now, "an overdue playlist must not schedule a timer in the past")
    }

    @Test func advanceStampsTheAdvanceTime() {
        var gen = SeededGenerator(seed: 3)
        let now = Date()
        let state = PlaylistRotation.advance(playlist: sequential([a, b]), state: PlaylistState(), now: now, using: &gen)
        #expect(abs(state.lastAdvance.timeIntervalSince(now)) < 0.001)
    }

    // MARK: Shuffle

    @Test func shufflePlaysEveryEntryOnceBeforeRepeating() {
        let ids = (0..<6).map { _ in UUID() }
        let playlist = Playlist(name: "S", assetIDs: ids, mode: .shuffle, interval: .minutes(5))
        var gen = SeededGenerator(seed: 42)
        var state = PlaylistState()
        state.shuffledOrder = PlaylistRotation.shuffle(ids, using: &gen)

        var pass: [UUID] = []
        for _ in 0..<ids.count {
            pass.append(try! #require(PlaylistRotation.currentAssetID(playlist: playlist, state: state)))
            state = PlaylistRotation.advance(playlist: playlist, state: state, now: Date(), using: &gen)
        }
        #expect(Set(pass) == Set(ids), "a full pass must cover every wallpaper")
        #expect(pass.count == Set(pass).count, "no repeats within a pass")
    }

    @Test func reshuffleAvoidsImmediatelyRepeatingTheVisibleWallpaper() {
        let ids = (0..<5).map { _ in UUID() }
        let playlist = Playlist(name: "S", assetIDs: ids, mode: .shuffle, interval: .minutes(5))
        // Walk to the last entry of a pass, then advance to force a reshuffle.
        for seed in UInt64(1)...20 {
            var gen = SeededGenerator(seed: seed)
            var state = PlaylistState()
            state.shuffledOrder = PlaylistRotation.shuffle(ids, using: &gen)
            state.index = ids.count - 1
            let showing = PlaylistRotation.currentAssetID(playlist: playlist, state: state)
            let next = PlaylistRotation.advance(playlist: playlist, state: state, now: Date(), using: &gen)
            #expect(PlaylistRotation.currentAssetID(playlist: playlist, state: next) != showing,
                    "reshuffling must not replay the wallpaper already on screen")
        }
    }

    @Test func staleShuffleOrderIsIgnoredAfterAnEdit() {
        let playlist = Playlist(name: "S", assetIDs: [a, b, c], mode: .shuffle, interval: .minutes(5))
        var state = PlaylistState()
        state.shuffledOrder = [a, b]                 // stale: playlist gained an entry
        #expect(PlaylistRotation.needsReshuffle(playlist: playlist, state: state))
        #expect(PlaylistRotation.resolvedOrder(playlist: playlist, state: state) == [a, b, c])

        state.shuffledOrder = [c, a, b]
        #expect(!PlaylistRotation.needsReshuffle(playlist: playlist, state: state))
        #expect(PlaylistRotation.resolvedOrder(playlist: playlist, state: state) == [c, a, b])

        // Same count but a different member is still stale.
        state.shuffledOrder = [c, a, UUID()]
        #expect(PlaylistRotation.needsReshuffle(playlist: playlist, state: state))
    }

    @Test func sequentialModeNeverNeedsAShuffle() {
        var state = PlaylistState(); state.shuffledOrder = [c, a]
        #expect(!PlaylistRotation.needsReshuffle(playlist: sequential([a, b, c]), state: state))
        #expect(PlaylistRotation.resolvedOrder(playlist: sequential([a, b, c]), state: state) == [a, b, c])
    }

    // MARK: Assignment model

    @Test func assignmentDistinguishesAssetsFromPlaylists() {
        let assetAssignment = WallpaperAssignment.asset(a, fitMode: .fit)
        let playlistAssignment = WallpaperAssignment.playlist(b)
        #expect(!assetAssignment.isPlaylist)
        #expect(playlistAssignment.isPlaylist)
        #expect(!assetAssignment.isEmpty)
        #expect(WallpaperAssignment().isEmpty)
        #expect(assetAssignment.fitMode == .fit)
    }

    @Test func oldSingleAssetSettingsStillDecode() throws {
        // Regression: settings.json written before playlists existed must keep working.
        let json = #"{"version":1,"desktop":{"useSameOnAllDisplays":true,"global":{"assetID":"11111111-2222-3333-4444-555555555555","fitMode":"fill"},"perDisplay":{}}}"#
        let settings = try JSONCoding.decoder().decode(AppSettings.self, from: Data(json.utf8))
        let global = try #require(settings.desktop.global)
        #expect(global.assetID == UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        #expect(global.playlistID == nil)
        #expect(global.fitMode == .fill)
        #expect(settings.playlists.isEmpty)
        #expect(settings.playlistStates.isEmpty)
    }

    @Test func removingAPlaylistClearsItsAssignments() {
        var assignments = DesktopAssignments()
        assignments.global = .playlist(a)
        assignments.perDisplay["D1"] = .playlist(a)
        assignments.perDisplay["D2"] = .asset(b)
        #expect(assignments.referencesPlaylist(a))
        assignments.removePlaylist(a)
        #expect(!assignments.referencesPlaylist(a))
        #expect(assignments.global == nil)
        #expect(assignments.perDisplay.count == 1)
        #expect(assignments.perDisplay["D2"]?.assetID == b)
    }
}

/// Coordinator-level behaviour: resolution, persistence and suspend.
@MainActor
@Suite(.serialized)
struct PlaylistCoordinatorTests {

    private func sandbox() throws -> (URL, VideoAssetManager, PreferencesStore) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lc-pl-\(UUID().uuidString)")
        let media = dir.appendingPathComponent("Media"), thumbs = dir.appendingPathComponent("Thumbnails")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbs, withIntermediateDirectories: true)
        return (dir,
                VideoAssetManager(store: LibraryStore(fileURL: dir.appendingPathComponent("library.json")),
                                  mediaDirectory: media, thumbnailDirectory: thumbs),
                PreferencesStore(fileURL: dir.appendingPathComponent("settings.json")))
    }

    /// Imports `count` real videos so the library has resolvable assets.
    private func seed(_ library: VideoAssetManager, count: Int) async throws -> [WallpaperAsset] {
        var assets: [WallpaperAsset] = []
        for i in 0..<count {
            let url = try await SyntheticAerialStore.makeVideo(width: 160 + i * 16, height: 90, frames: 4)
            defer { try? FileManager.default.removeItem(at: url) }
            assets.append(try #require(await library.importFile(url)))
        }
        return assets
    }

    @Test func resolvesAPlaylistToItsCurrentEntry() async throws {
        let (dir, library, prefs) = try sandbox()
        defer { try? FileManager.default.removeItem(at: dir) }
        let assets = try await seed(library, count: 3)
        let playlist = Playlist(name: "P", assetIDs: assets.map(\.id), mode: .sequential, interval: .minutes(5))
        prefs.update { $0.playlists = [playlist]; $0.desktop.global = .playlist(playlist.id) }

        let coordinator = PlaylistCoordinator(preferences: prefs, library: library)
        #expect(coordinator.resolveAsset(for: .playlist(playlist.id))?.id == assets[0].id)

        #expect(coordinator.advanceNow())
        #expect(coordinator.resolveAsset(for: .playlist(playlist.id))?.id == assets[1].id)
        #expect(coordinator.advanceNow())
        #expect(coordinator.resolveAsset(for: .playlist(playlist.id))?.id == assets[2].id)
        #expect(coordinator.advanceNow())
        #expect(coordinator.resolveAsset(for: .playlist(playlist.id))?.id == assets[0].id, "must wrap around")
        coordinator.stop()
    }

    @Test func resolvesAPlainAssetAssignmentUnchanged() async throws {
        let (dir, library, prefs) = try sandbox()
        defer { try? FileManager.default.removeItem(at: dir) }
        let assets = try await seed(library, count: 1)
        let coordinator = PlaylistCoordinator(preferences: prefs, library: library)
        #expect(coordinator.resolveAsset(for: .asset(assets[0].id))?.id == assets[0].id)
        #expect(coordinator.resolveAsset(for: nil) == nil)
        #expect(coordinator.resolveAsset(for: .playlist(UUID())) == nil, "an unknown playlist resolves to nothing")
        coordinator.stop()
    }

    @Test func skipsEntriesWhoseMediaWasDeleted() async throws {
        let (dir, library, prefs) = try sandbox()
        defer { try? FileManager.default.removeItem(at: dir) }
        let assets = try await seed(library, count: 3)
        let playlist = Playlist(name: "P", assetIDs: assets.map(\.id), mode: .sequential, interval: .minutes(5))
        prefs.update { $0.playlists = [playlist]; $0.desktop.global = .playlist(playlist.id) }
        let coordinator = PlaylistCoordinator(preferences: prefs, library: library)

        // Delete the first entry's media; resolution must fall through to a live one.
        library.delete(assets[0])
        let resolved = try #require(coordinator.resolveAsset(for: .playlist(playlist.id)))
        #expect(resolved.id != assets[0].id)
        #expect([assets[1].id, assets[2].id].contains(resolved.id))
        coordinator.stop()
    }

    @Test func rotationStatePersistsAcrossRelaunch() async throws {
        let (dir, library, prefs) = try sandbox()
        defer { try? FileManager.default.removeItem(at: dir) }
        let assets = try await seed(library, count: 3)
        let playlist = Playlist(name: "P", assetIDs: assets.map(\.id), mode: .sequential, interval: .minutes(30))
        prefs.update { $0.playlists = [playlist]; $0.desktop.global = .playlist(playlist.id) }

        let first = PlaylistCoordinator(preferences: prefs, library: library)
        first.advanceNow()
        let expected = try #require(first.resolveAsset(for: .playlist(playlist.id))?.id)
        first.stop()
        prefs.saveNow()

        // Reopen from disk, as a relaunch would.
        let reopened = PreferencesStore(fileURL: dir.appendingPathComponent("settings.json"))
        let second = PlaylistCoordinator(preferences: reopened, library: library)
        #expect(second.resolveAsset(for: .playlist(playlist.id))?.id == expected,
                "a relaunch must resume where the rotation left off")
        second.stop()
    }

    @Test func anOverduePlaylistAdvancesOnStart() async throws {
        let (dir, library, prefs) = try sandbox()
        defer { try? FileManager.default.removeItem(at: dir) }
        let assets = try await seed(library, count: 3)
        let playlist = Playlist(name: "P", assetIDs: assets.map(\.id), mode: .sequential, interval: .minutes(5))
        var state = PlaylistState()
        state.lastAdvance = Date().addingTimeInterval(-3600)     // overdue by an hour
        prefs.update {
            $0.playlists = [playlist]
            $0.desktop.global = .playlist(playlist.id)
            $0.setPlaylistState(state, for: playlist.id)
        }

        let coordinator = PlaylistCoordinator(preferences: prefs, library: library)
        #expect(coordinator.resolveAsset(for: .playlist(playlist.id))?.id == assets[0].id)
        coordinator.start()
        #expect(coordinator.resolveAsset(for: .playlist(playlist.id))?.id == assets[1].id,
                "a rotation that fell due while the app was closed should be applied")
        coordinator.stop()
    }

    @Test func aFreshPlaylistIsNotTreatedAsOverdue() async throws {
        let (dir, library, prefs) = try sandbox()
        defer { try? FileManager.default.removeItem(at: dir) }
        let assets = try await seed(library, count: 3)
        let playlist = Playlist(name: "P", assetIDs: assets.map(\.id), mode: .sequential, interval: .minutes(5))
        prefs.update { $0.playlists = [playlist]; $0.desktop.global = .playlist(playlist.id) }

        let coordinator = PlaylistCoordinator(preferences: prefs, library: library)
        coordinator.start()
        #expect(coordinator.resolveAsset(for: .playlist(playlist.id))?.id == assets[0].id,
                "a new playlist starts at its first entry rather than jumping ahead")
        coordinator.stop()
    }

    @Test func advanceNowReportsWhenNoPlaylistIsAssigned() async throws {
        let (dir, library, prefs) = try sandbox()
        defer { try? FileManager.default.removeItem(at: dir) }
        let assets = try await seed(library, count: 1)
        prefs.update { $0.desktop.global = .asset(assets[0].id) }
        let coordinator = PlaylistCoordinator(preferences: prefs, library: library)
        #expect(!coordinator.advanceNow(), "with no playlist assigned the caller should fall back")
        coordinator.stop()
    }

    @Test func engineFollowsAPlaylistRotation() async throws {
        let (dir, library, prefs) = try sandbox()
        defer { try? FileManager.default.removeItem(at: dir) }
        let assets = try await seed(library, count: 3)
        let playlist = Playlist(name: "P", assetIDs: assets.map(\.id), mode: .sequential, interval: .minutes(5))
        prefs.update { $0.playlists = [playlist]; $0.desktop.global = .playlist(playlist.id) }

        let coordinator = PlaylistCoordinator(preferences: prefs, library: library)
        let engine = WallpaperEngine(library: library, preferences: prefs,
                                     displays: DisplayManager(), playlists: coordinator)
        engine.reconcile()
        #expect(engine.activeAssetIDs == [assets[0].id])

        coordinator.advanceNow()
        engine.reconcile()
        #expect(engine.activeAssetIDs == [assets[1].id], "the wallpaper on screen must follow the playlist")

        engine.stop()
        coordinator.stop()
    }
}

struct SettingsResilienceTests {
    /// Regression: one malformed field used to make the whole settings file fail to
    /// decode, silently discarding every other setting the user had configured.
    @Test func oneBadFieldDoesNotDiscardTheRestOfTheSettings() throws {
        let json = """
        {"version":1,
         "playback":{"allowAudio":true,"quality":"maximum"},
         "startAtLogin":true,
         "lastSection":"displays",
         "playlistStates":"this should be an object, not a string"}
        """
        let settings = try JSONCoding.decoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.playback.allowAudio, "a good field must survive a bad neighbour")
        #expect(settings.playback.quality == .maximum)
        #expect(settings.startAtLogin)
        #expect(settings.lastSection == "displays")
        #expect(settings.playlistStates.isEmpty, "the malformed field falls back to its default")
    }

    @Test func playlistStatesRoundTripAsAJSONObject() throws {
        // A [UUID: …] dictionary encodes as an interleaved array; keying by the UUID
        // string keeps settings.json readable and hand-editable.
        var settings = AppSettings()
        let id = UUID()
        var state = PlaylistState()
        state.index = 2
        settings.setPlaylistState(state, for: id)

        let data = try JSONCoding.encoder().encode(settings)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let states = try #require(object["playlistStates"] as? [String: Any])
        #expect(states[id.uuidString] != nil)

        let back = try JSONCoding.decoder().decode(AppSettings.self, from: data)
        #expect(back.playlistState(id).index == 2)
        #expect(back.playlistState(UUID()).index == 0, "an unknown playlist gets a fresh state")
    }

    @Test func removingAPlaylistStateWorks() {
        var settings = AppSettings()
        let id = UUID()
        settings.setPlaylistState(PlaylistState(), for: id)
        #expect(settings.playlistStates.count == 1)
        settings.removePlaylistState(id)
        #expect(settings.playlistStates.isEmpty)
    }

    @Test func customIntervalRoundTrips() throws {
        let playlist = Playlist(name: "P", assetIDs: [UUID()], mode: .shuffle, interval: .custom(20))
        let data = try JSONCoding.encoder().encode(playlist)
        let back = try JSONCoding.decoder().decode(Playlist.self, from: data)
        #expect(back.interval == .custom(20))
        #expect(back.interval.seconds == 20)
        #expect(back.mode == .shuffle)
    }
}
