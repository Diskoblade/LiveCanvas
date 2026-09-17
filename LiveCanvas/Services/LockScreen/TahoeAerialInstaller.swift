import Foundation

/// macOS 26 Tahoe implementation. See `docs/TAHOE_AERIAL_FORMAT.md` for the discovered
/// format and the reasoning behind this approach.
///
/// Design commitments:
/// * **No Apple media file is ever overwritten.** LiveCanvas appends its own asset entry
///   and adds its own video/poster files. Apple's multi-hundred-megabyte originals, which
///   exist only on disk, are left untouched.
/// * Exactly two existing files are modified: `manifest/entries.json` and
///   `Store/Index.plist`. Both are hash-backed-up and verified before any write.
/// * Any validation failure refuses the operation instead of risking the store.
struct TahoeAerialInstaller: LockScreenWallpaperInstalling {
    var locator: AerialStoreLocator
    var backups: BackupManager
    var compatibility: LockScreenCompatibility
    var preparer: LockScreenVideoPreparer
    /// Where the installation record is kept so Restore survives relaunches.
    var recordURL: URL

    init(locator: AerialStoreLocator = .userDefault,
         backups: BackupManager = BackupManager(),
         compatibility: LockScreenCompatibility = .current,
         preparer: LockScreenVideoPreparer = LockScreenVideoPreparer(),
         recordURL: URL = AppDirectories.root.appendingPathComponent("lockscreen-installation.json")) {
        self.locator = locator
        self.backups = backups
        self.compatibility = compatibility
        self.preparer = preparer
        self.recordURL = recordURL
    }

    private var validator: AerialStoreValidator { AerialStoreValidator(locator: locator) }
    private var indexStore: AerialIndexStore { AerialIndexStore(indexFile: locator.indexFile) }

    // MARK: Status

    func status() async -> LockScreenInstallerStatus {
        if let reason = compatibility.explanation {
            return .unsupportedOS(reason)
        }
        let report = validator.inspect()
        guard report.isUsable else {
            return .storeUnavailable(report.reason ?? "The Aerial wallpaper store cannot be used.")
        }
        guard FileManager.default.fileExists(atPath: locator.indexFile.path) else {
            return .storeUnavailable("macOS has not written a wallpaper index yet. Open System Settings › Wallpaper and pick any Lock Screen wallpaper once.")
        }
        // A Lock Screen that is not currently on an Aerial cannot be redirected.
        if let snapshot = try? indexStore.snapshot(), snapshot.assetIDsByDisplay.isEmpty {
            return .storeUnavailable("No display is using an Aerial Lock Screen wallpaper. In System Settings › Wallpaper, choose any Aerial for the Lock Screen, then come back.")
        }

        var warnings: [String] = []
        if !report.modifiedAppleAssetIDs.isEmpty {
            let phrase = Pluralize.count(report.modifiedAppleAssetIDs.count, "of Apple's own Aerial wallpapers", "of Apple's own Aerial wallpapers")
            warnings.append("\(phrase) already point at local files, so another app has modified this store. \(AppInfo.name) will not touch those entries.")
        }
        let foreign = Set(report.injectedAssetIDs).subtracting(report.liveCanvasAssetIDs)
        if !foreign.isEmpty {
            let verb = foreign.count == 1 ? "was" : "were"
            warnings.append("\(Pluralize.count(foreign.count, "wallpaper entry", "wallpaper entries")) in the macOS list \(verb) added by another app.")
        }
        return .ready(warning: warnings.isEmpty ? nil : warnings.joined(separator: " "))
    }

    // MARK: Install

    func install(request: LockScreenInstallRequest) async throws -> LockScreenInstallation {
        // 1. Refuse early on anything unsafe.
        if let reason = compatibility.explanation { throw LiveCanvasError.unsupportedOS(reason) }
        let report = validator.inspect()
        guard report.isUsable else {
            throw LiveCanvasError.wallpaperStoreNotInitialized(report.reason ?? "The Aerial wallpaper store cannot be used.")
        }
        guard report.isWritable else {
            throw LiveCanvasError.lockScreenUnavailable("The Aerial wallpaper store is not writable by your user account.")
        }
        let manifest = try validator.loadManifest()
        let snapshotBefore = try indexStore.snapshot()
        guard !snapshotBefore.assetIDsByDisplay.isEmpty else {
            throw LiveCanvasError.lockScreenUnavailable("No display is using an Aerial Lock Screen wallpaper. In System Settings › Wallpaper, choose any Aerial for the Lock Screen, then apply again.")
        }

        // 2. Prepare the media first, outside the store, so a failure changes nothing.
        let aerialAssetID = UUID().uuidString.uppercased()
        let stagingDirectory = AppDirectories.lockScreen
        let stagedVideo = stagingDirectory.appendingPathComponent("\(aerialAssetID).mov")
        try await preparer.prepare(source: request.videoURL, probe: request.probe, destination: stagedVideo)

        var stagedPoster: URL?
        if let poster = request.posterURL, FileManager.default.fileExists(atPath: poster.path) {
            let destination = stagingDirectory.appendingPathComponent("\(aerialAssetID).png")
            try? FileManager.default.removeItem(at: destination)
            if (try? PosterConverter.writePNG(from: poster, to: destination)) != nil {
                stagedPoster = destination
            }
        }

        // 3. Back up the two files that will change, plus record what will be added.
        let installedVideo = locator.videoURL(for: aerialAssetID)
        let installedPoster = locator.thumbnailURL(for: aerialAssetID)
        var addedPaths = [installedVideo.path]
        if stagedPoster != nil { addedPaths.append(installedPoster.path) }

        let backup = try backups.createBackup(
            of: [locator.entriesFile, locator.indexFile],
            note: "Before installing “\(request.displayName)” as the Lock Screen wallpaper",
            addedPaths: addedPaths)
        try backups.verifyBackup(backup)

        // 4. Copy the media in. These are new paths, so nothing is overwritten.
        do {
            try FileManager.default.copyItem(at: stagedVideo, to: installedVideo)
            if let stagedPoster {
                try FileManager.default.copyItem(at: stagedPoster, to: installedPoster)
            }
        } catch {
            try? FileManager.default.removeItem(at: installedVideo)
            try? FileManager.default.removeItem(at: installedPoster)
            backups.deleteBackup(id: backup.id)
            throw LiveCanvasError.lockScreenUnavailable("Could not copy the prepared wallpaper into the macOS store: \(error.localizedDescription)")
        }

        // 5. Append our entry to entries.json and repoint the Idle choice.
        do {
            let newAsset = AerialAssetFactory.makeAsset(
                id: aerialAssetID,
                name: request.displayName,
                mediaKey: manifest.mediaKey,
                videoURL: installedVideo,
                thumbnailURL: stagedPoster != nil ? installedPoster : nil)

            // Drop any stale LiveCanvas entries so the list does not grow without bound.
            let kept = manifest.assets.filter { !AerialAssetFactory.isLiveCanvasAsset($0) }
            let data = try AerialManifestParser.encode(manifest, assets: kept + [newAsset])
            // Sanity-check our own output before it replaces a working file.
            let reparsed = try AerialManifestParser.parse(data)
            guard reparsed.assets.contains(where: { $0.id == aerialAssetID }) else {
                throw LiveCanvasError.preparationFailed("The rewritten manifest did not contain the new wallpaper.")
            }
            try AtomicFileWriter.write(data, to: locator.entriesFile)

            try indexStore.setLockScreenAsset(aerialAssetID)
        } catch {
            // Roll all the way back using the verified backup.
            Log.lockscreen.error("Install failed, rolling back: \(error.localizedDescription, privacy: .public)")
            try? backups.restore(backup)
            throw error is LiveCanvasError ? error : LiveCanvasError.lockScreenUnavailable(error.localizedDescription)
        }

        WallpaperAgentController.reload()

        let installation = LockScreenInstallation(
            backupID: backup.id,
            aerialAssetID: aerialAssetID,
            libraryAssetID: request.assetID,
            displayName: request.displayName,
            installedAt: Date(),
            osVersion: OSVersion.current.description,
            previousAssetIDsByDisplay: snapshotBefore.assetIDsByDisplay,
            addedFilePaths: addedPaths)
        try saveRecord(installation)
        try? FileManager.default.removeItem(at: stagedVideo)
        if let stagedPoster { try? FileManager.default.removeItem(at: stagedPoster) }
        Log.lockscreen.info("Installed Lock Screen wallpaper \(aerialAssetID, privacy: .public)")
        return installation
    }

    // MARK: Restore

    func restore(_ installation: LockScreenInstallation) async throws {
        let backup = try backups.loadManifest(id: installation.backupID)
        try backups.verifyBackup(backup)
        try backups.restore(backup)
        WallpaperAgentController.reload()
        clearRecord()
        Log.lockscreen.info("Restored Lock Screen from backup \(backup.id.uuidString, privacy: .public)")
    }

    func restoreLatest() async throws {
        guard let installation = loadRecord() else {
            throw LiveCanvasError.lockScreenUnavailable("There is no LiveCanvas Lock Screen installation to undo.")
        }
        try await restore(installation)
    }

    // MARK: Installation record

    func loadRecord() -> LockScreenInstallation? {
        guard let data = try? Data(contentsOf: recordURL) else { return nil }
        return try? JSONCoding.decoder().decode(LockScreenInstallation.self, from: data)
    }

    func saveRecord(_ installation: LockScreenInstallation) throws {
        try AtomicFileWriter.write(try JSONCoding.encoder().encode(installation), to: recordURL)
    }

    func clearRecord() {
        try? FileManager.default.removeItem(at: recordURL)
    }

    /// True when the store still reflects the recorded installation.
    func isInstallationLive(_ installation: LockScreenInstallation) -> Bool {
        guard let snapshot = try? indexStore.snapshot() else { return false }
        return snapshot.assetIDs.contains(installation.aerialAssetID)
    }
}
