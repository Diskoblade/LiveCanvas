import Testing
import Foundation
@testable import LiveCanvas

/// Install / verify / restore against a synthetic store. The real macOS store is never
/// touched by anything in this file.
struct LockScreenInstallTests {

    private func makeInstaller(_ store: SyntheticAerialStore, sandbox: URL) -> TahoeAerialInstaller {
        TahoeAerialInstaller(
            locator: store.locator,
            backups: BackupManager(rootDirectory: sandbox.appendingPathComponent("Backups")),
            compatibility: LockScreenCompatibility(osVersion: OSVersion(major: 26, minor: 3, patch: 0)),
            preparer: LockScreenVideoPreparer(),
            recordURL: sandbox.appendingPathComponent("installation.json"))
    }

    private func sandbox() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lc-install-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func request(video: URL, name: String = "Ocean") async throws -> LockScreenInstallRequest {
        let probe = try await VideoMetadataService().probe(video)
        return LockScreenInstallRequest(assetID: UUID(), displayName: name, videoURL: video, probe: probe, posterURL: nil)
    }

    // MARK: Status

    @Test func statusIsReadyOnAValidStore() async throws {
        let store = try SyntheticAerialStore(); defer { store.tearDown() }
        let box = try sandbox(); defer { try? FileManager.default.removeItem(at: box) }
        let status = await makeInstaller(store, sandbox: box).status()
        #expect(status.isReady)
        #expect(status.message == nil)
    }

    @Test func statusRefusesOnAnUnvalidatedOS() async throws {
        let store = try SyntheticAerialStore(); defer { store.tearDown() }
        let box = try sandbox(); defer { try? FileManager.default.removeItem(at: box) }
        var installer = makeInstaller(store, sandbox: box)
        installer.compatibility = LockScreenCompatibility(osVersion: OSVersion(major: 27, minor: 0, patch: 0))
        let status = await installer.status()
        #expect(!status.isReady)
        #expect(status.message?.contains("27") == true)
    }

    @Test func statusRefusesWhenNoDisplayUsesAnAerial() async throws {
        let store = try SyntheticAerialStore(); defer { store.tearDown() }
        let box = try sandbox(); defer { try? FileManager.default.removeItem(at: box) }
        try store.writeIndexPlistWithoutAerial()
        let status = await makeInstaller(store, sandbox: box).status()
        #expect(!status.isReady)
        #expect(status.message?.contains("System Settings") == true)
    }

    @Test func statusRefusesWhenEntriesJSONIsCorrupt() async throws {
        let store = try SyntheticAerialStore(); defer { store.tearDown() }
        let box = try sandbox(); defer { try? FileManager.default.removeItem(at: box) }
        try Data("{ not json".utf8).write(to: store.locator.entriesFile)
        let status = await makeInstaller(store, sandbox: box).status()
        #expect(!status.isReady)
    }

    // MARK: Install

    @Test func installAddsAnEntryAndRepointsTheLockScreen() async throws {
        let store = try SyntheticAerialStore(); defer { store.tearDown() }
        let box = try sandbox(); defer { try? FileManager.default.removeItem(at: box) }
        let video = try await SyntheticAerialStore.makeVideo(); defer { try? FileManager.default.removeItem(at: video) }
        let installer = makeInstaller(store, sandbox: box)

        let installation = try await installer.install(request: try await request(video: video))

        // The manifest gained exactly one entry, and Apple's two survive untouched.
        let manifest = try AerialManifestParser.parse(try Data(contentsOf: store.locator.entriesFile))
        #expect(manifest.assets.count == 3)
        #expect(manifest.assets.contains { $0.id == SyntheticAerialStore.appleAssetID })
        #expect(manifest.assets.contains { $0.id == SyntheticAerialStore.secondAppleAssetID })
        let ours = try #require(manifest.assets.first { $0.id == installation.aerialAssetID })
        #expect(ours.name == "Ocean")
        #expect(ours.isLocalMedia)
        #expect(AerialAssetFactory.isLiveCanvasAsset(ours))
        #expect(ours.raw[SyntheticAerialStore.mediaKey] != nil)

        // The video landed in the store and is a real, playable, silent file.
        let installedVideo = store.locator.videoURL(for: installation.aerialAssetID)
        #expect(FileManager.default.fileExists(atPath: installedVideo.path))
        let probe = try await VideoMetadataService().probe(installedVideo)
        #expect(probe.isPlayable)
        #expect(!probe.hasAudio)

        // Index.plist now points at our asset.
        let snapshot = try AerialIndexStore(indexFile: store.locator.indexFile).snapshot()
        #expect(snapshot.assetIDs == [installation.aerialAssetID])
        #expect(installation.previousAssetIDsByDisplay[store.displayID] == SyntheticAerialStore.appleAssetID)
    }

    @Test func installNeverOverwritesAnApplesVideoFile() async throws {
        let store = try SyntheticAerialStore(); defer { store.tearDown() }
        let box = try sandbox(); defer { try? FileManager.default.removeItem(at: box) }
        let video = try await SyntheticAerialStore.makeVideo(); defer { try? FileManager.default.removeItem(at: video) }

        let appleVideo = store.locator.videoURL(for: SyntheticAerialStore.appleAssetID)
        let before = try FileUtilities.sha256(of: appleVideo)
        _ = try await makeInstaller(store, sandbox: box).install(request: try await request(video: video))
        #expect(try FileUtilities.sha256(of: appleVideo) == before, "Apple's media must never be modified")
    }

    @Test func installStripsAudio() async throws {
        let store = try SyntheticAerialStore(); defer { store.tearDown() }
        let box = try sandbox(); defer { try? FileManager.default.removeItem(at: box) }
        let video = try await SyntheticAerialStore.makeVideo(withAudio: true)
        defer { try? FileManager.default.removeItem(at: video) }

        let sourceProbe = try await VideoMetadataService().probe(video)
        #expect(sourceProbe.hasAudio, "fixture should have audio to begin with")

        let installer = makeInstaller(store, sandbox: box)
        let installation = try await installer.install(request: try await request(video: video))
        let installed = try await VideoMetadataService().probe(store.locator.videoURL(for: installation.aerialAssetID))
        #expect(!installed.hasAudio)
    }

    @Test func repeatedInstallsDoNotAccumulateEntries() async throws {
        let store = try SyntheticAerialStore(); defer { store.tearDown() }
        let box = try sandbox(); defer { try? FileManager.default.removeItem(at: box) }
        let video = try await SyntheticAerialStore.makeVideo(); defer { try? FileManager.default.removeItem(at: video) }
        let installer = makeInstaller(store, sandbox: box)

        for i in 0..<3 {
            _ = try await installer.install(request: try await request(video: video, name: "Take \(i)"))
            let manifest = try AerialManifestParser.parse(try Data(contentsOf: store.locator.entriesFile))
            #expect(manifest.assets.count == 3, "one LiveCanvas entry plus Apple's two")
            #expect(manifest.assets.filter(AerialAssetFactory.isLiveCanvasAsset).count == 1)
        }
    }

    // MARK: Restore

    @Test func restoreReturnsTheStoreToItsExactOriginalBytes() async throws {
        let store = try SyntheticAerialStore(); defer { store.tearDown() }
        let box = try sandbox(); defer { try? FileManager.default.removeItem(at: box) }
        let video = try await SyntheticAerialStore.makeVideo(); defer { try? FileManager.default.removeItem(at: video) }
        let installer = makeInstaller(store, sandbox: box)

        let entriesBefore = try FileUtilities.sha256(of: store.locator.entriesFile)
        let indexBefore = try FileUtilities.sha256(of: store.locator.indexFile)

        let installation = try await installer.install(request: try await request(video: video))
        #expect(try FileUtilities.sha256(of: store.locator.entriesFile) != entriesBefore)

        try await installer.restore(installation)

        #expect(try FileUtilities.sha256(of: store.locator.entriesFile) == entriesBefore)
        #expect(try FileUtilities.sha256(of: store.locator.indexFile) == indexBefore)
        #expect(!FileManager.default.fileExists(atPath: store.locator.videoURL(for: installation.aerialAssetID).path))
        let snapshot = try AerialIndexStore(indexFile: store.locator.indexFile).snapshot()
        #expect(snapshot.assetIDs == [SyntheticAerialStore.appleAssetID])
        #expect(installer.loadRecord() == nil)
    }

    @Test func applyLockApplyLockRestoreCycle() async throws {
        // Mirrors the manual test matrix: apply, apply another, then restore Apple's.
        let store = try SyntheticAerialStore(); defer { store.tearDown() }
        let box = try sandbox(); defer { try? FileManager.default.removeItem(at: box) }
        let first = try await SyntheticAerialStore.makeVideo(width: 320, height: 180)
        let second = try await SyntheticAerialStore.makeVideo(width: 640, height: 360)
        defer { try? FileManager.default.removeItem(at: first); try? FileManager.default.removeItem(at: second) }
        let installer = makeInstaller(store, sandbox: box)

        let entriesBefore = try FileUtilities.sha256(of: store.locator.entriesFile)
        let indexBefore = try FileUtilities.sha256(of: store.locator.indexFile)

        let a = try await installer.install(request: try await request(video: first, name: "Ocean"))
        #expect(installer.isInstallationLive(a))

        let b = try await installer.install(request: try await request(video: second, name: "Forest"))
        #expect(installer.isInstallationLive(b))
        #expect(!installer.isInstallationLive(a))
        // The first install's video is cleaned up by the second install's manifest rewrite,
        // but its file remains until that backup is restored; both are tracked.
        #expect(FileManager.default.fileExists(atPath: store.locator.videoURL(for: b.aerialAssetID).path))

        // Restoring the FIRST installation returns the store to its pre-LiveCanvas state.
        try await installer.restore(a)
        #expect(try FileUtilities.sha256(of: store.locator.entriesFile) == entriesBefore)
        #expect(try FileUtilities.sha256(of: store.locator.indexFile) == indexBefore)
    }

    @Test func restoreLatestUsesThePersistedRecord() async throws {
        let store = try SyntheticAerialStore(); defer { store.tearDown() }
        let box = try sandbox(); defer { try? FileManager.default.removeItem(at: box) }
        let video = try await SyntheticAerialStore.makeVideo(); defer { try? FileManager.default.removeItem(at: video) }

        let entriesBefore = try FileUtilities.sha256(of: store.locator.entriesFile)
        // A fresh installer instance reads the record from disk, as it would after relaunch.
        _ = try await makeInstaller(store, sandbox: box).install(request: try await request(video: video))
        let reopened = makeInstaller(store, sandbox: box)
        #expect(reopened.loadRecord() != nil)
        try await reopened.restoreLatest()
        #expect(try FileUtilities.sha256(of: store.locator.entriesFile) == entriesBefore)
    }

    @Test func restoreLatestWithNothingInstalledThrows() async throws {
        let store = try SyntheticAerialStore(); defer { store.tearDown() }
        let box = try sandbox(); defer { try? FileManager.default.removeItem(at: box) }
        await #expect(throws: LiveCanvasError.self) {
            try await makeInstaller(store, sandbox: box).restoreLatest()
        }
    }

    // MARK: Refusal paths

    @Test func installRefusesOnAnUnvalidatedOSAndChangesNothing() async throws {
        let store = try SyntheticAerialStore(); defer { store.tearDown() }
        let box = try sandbox(); defer { try? FileManager.default.removeItem(at: box) }
        let video = try await SyntheticAerialStore.makeVideo(); defer { try? FileManager.default.removeItem(at: video) }
        var installer = makeInstaller(store, sandbox: box)
        installer.compatibility = LockScreenCompatibility(osVersion: OSVersion(major: 27, minor: 0, patch: 0))

        let before = try FileUtilities.sha256(of: store.locator.entriesFile)
        await #expect(throws: LiveCanvasError.self) {
            _ = try await installer.install(request: try await request(video: video))
        }
        #expect(try FileUtilities.sha256(of: store.locator.entriesFile) == before)
    }

    @Test func installRefusesWhenNoAerialIdleChoiceExists() async throws {
        let store = try SyntheticAerialStore(); defer { store.tearDown() }
        let box = try sandbox(); defer { try? FileManager.default.removeItem(at: box) }
        let video = try await SyntheticAerialStore.makeVideo(); defer { try? FileManager.default.removeItem(at: video) }
        try store.writeIndexPlistWithoutAerial()

        let before = try FileUtilities.sha256(of: store.locator.entriesFile)
        await #expect(throws: LiveCanvasError.self) {
            _ = try await makeInstaller(store, sandbox: box).install(request: try await request(video: video))
        }
        #expect(try FileUtilities.sha256(of: store.locator.entriesFile) == before)
    }

    @Test func installRefusesWhenTheStoreIsNotInitialised() async throws {
        let box = try sandbox(); defer { try? FileManager.default.removeItem(at: box) }
        let video = try await SyntheticAerialStore.makeVideo(); defer { try? FileManager.default.removeItem(at: video) }
        let empty = AerialStoreLocator(root: box.appendingPathComponent("nothing-here"))
        let installer = TahoeAerialInstaller(
            locator: empty,
            backups: BackupManager(rootDirectory: box.appendingPathComponent("B")),
            compatibility: LockScreenCompatibility(osVersion: OSVersion(major: 26, minor: 0, patch: 0)),
            recordURL: box.appendingPathComponent("r.json"))
        await #expect(throws: LiveCanvasError.self) {
            _ = try await installer.install(request: try await request(video: video))
        }
    }

    // MARK: Detection of third-party modification

    @Test func validatorFlagsEntriesInjectedByOtherTools() async throws {
        let store = try SyntheticAerialStore(); defer { store.tearDown() }
        // Simulate what another wallpaper app does: inject an entry and redirect an Apple
        // asset's media URL at a local file. Both must be reported.
        var manifest = try AerialManifestParser.parse(try Data(contentsOf: store.locator.entriesFile))
        var assets = manifest.assets
        let foreign = AerialAsset(
            raw: ["id": "FOREIGN-1", "accessibilityLabel": "8K Something", "shotID": "CUSTOM_X",
                  SyntheticAerialStore.mediaKey: "file:///tmp/foreign.mov"],
            id: "FOREIGN-1", name: "8K Something",
            mediaURLString: "file:///tmp/foreign.mov", previewImageString: nil, shotID: "CUSTOM_X")
        assets.append(foreign)
        var hijacked = assets[0]
        hijacked.raw[SyntheticAerialStore.mediaKey] = "file:///tmp/hijacked.mov"
        hijacked.mediaURLString = "file:///tmp/hijacked.mov"
        assets[0] = hijacked
        try AerialManifestParser.encode(manifest, assets: assets).write(to: store.locator.entriesFile)
        manifest.assets = assets

        let report = AerialStoreValidator(locator: store.locator).inspect()
        #expect(report.injectedAssetIDs.contains("FOREIGN-1"))
        #expect(report.modifiedAppleAssetIDs.contains(SyntheticAerialStore.appleAssetID))
        #expect(report.hasForeignModifications)
        #expect(report.liveCanvasAssetIDs.isEmpty)

        // The installer stays usable but warns.
        let box = try sandbox(); defer { try? FileManager.default.removeItem(at: box) }
        let status = await makeInstaller(store, sandbox: box).status()
        #expect(status.isReady)
        #expect(status.message?.isEmpty == false)
    }

    @Test func liveCanvasOwnEntriesAreNotReportedAsForeign() async throws {
        let store = try SyntheticAerialStore(); defer { store.tearDown() }
        let box = try sandbox(); defer { try? FileManager.default.removeItem(at: box) }
        let video = try await SyntheticAerialStore.makeVideo(); defer { try? FileManager.default.removeItem(at: video) }
        _ = try await makeInstaller(store, sandbox: box).install(request: try await request(video: video))

        let report = AerialStoreValidator(locator: store.locator).inspect()
        #expect(report.liveCanvasAssetIDs.count == 1)
        #expect(report.modifiedAppleAssetIDs.isEmpty)
        #expect(!report.hasForeignModifications, "our own entry must not look like someone else's")
    }
}
