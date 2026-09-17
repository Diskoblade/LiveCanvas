import Foundation

/// The result of inspecting the Aerial store without modifying anything.
struct AerialStoreReport: Sendable {
    enum Health: Equatable, Sendable {
        case usable
        case notInitialized(String)
        case unreadable(String)
    }

    var health: Health
    var locator: AerialStoreLocator
    var mediaKey: String?
    var assetCount: Int
    var downloadedAssetIDs: [String]
    /// Assets present in the live manifest but not in Apple's pristine manifest.tar copy.
    var injectedAssetIDs: [String]
    /// Assets LiveCanvas itself added (a subset of `injectedAssetIDs`).
    var liveCanvasAssetIDs: [String]
    /// Apple assets whose local video no longer matches the manifest (overwritten by some tool).
    var modifiedAppleAssetIDs: [String]
    var manifestSource: String?
    var isWritable: Bool

    var isUsable: Bool { health == .usable }

    var reason: String? {
        switch health {
        case .usable: return nil
        case .notInitialized(let s), .unreadable(let s): return s
        }
    }

    /// True when something other than LiveCanvas has edited the store.
    var hasForeignModifications: Bool {
        !modifiedAppleAssetIDs.isEmpty || !Set(injectedAssetIDs).subtracting(liveCanvasAssetIDs).isEmpty
    }
}

/// Read-only inspection and validation of the Aerial store. Writes nothing, ever.
struct AerialStoreValidator: Sendable {
    var locator: AerialStoreLocator

    init(locator: AerialStoreLocator = .userDefault) {
        self.locator = locator
    }

    func inspect() -> AerialStoreReport {
        let fm = FileManager.default
        var report = AerialStoreReport(
            health: .usable, locator: locator, mediaKey: nil, assetCount: 0,
            downloadedAssetIDs: [], injectedAssetIDs: [], liveCanvasAssetIDs: [],
            modifiedAppleAssetIDs: [], manifestSource: nil, isWritable: false)

        // 1. Required structure.
        let required: [(URL, String)] = [
            (locator.aerials, "the aerials folder"),
            (locator.manifestDirectory, "the manifest folder"),
            (locator.entriesFile, "entries.json"),
            (locator.videosDirectory, "the videos folder"),
            (locator.thumbnailsDirectory, "the thumbnails folder"),
        ]
        for (url, label) in required where !fm.fileExists(atPath: url.path) {
            report.health = .notInitialized("The macOS Aerial wallpaper store is missing \(label). Open System Settings › Wallpaper and choose any Aerial wallpaper once, then try again.")
            return report
        }

        // 2. Parse the live manifest.
        let manifest: AerialManifest
        do {
            manifest = try AerialManifestParser.parse(try Data(contentsOf: locator.entriesFile))
        } catch {
            report.health = .unreadable((error as? LiveCanvasError)?.failureReason ?? error.localizedDescription)
            return report
        }
        report.mediaKey = manifest.mediaKey
        report.assetCount = manifest.assets.count
        report.manifestSource = try? String(contentsOf: locator.manifestSourceFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 3. Which assets have a local video file.
        report.downloadedAssetIDs = manifest.assets
            .filter { fm.fileExists(atPath: locator.videoURL(for: $0.id).path) }
            .map(\.id)

        // 4. Compare against Apple's pristine copy inside manifest.tar (offline, no network).
        if let pristine = try? pristineAssetIDs() {
            report.injectedAssetIDs = manifest.assets.map(\.id).filter { !pristine.contains($0) }
            // Apple assets whose media URL now points at a local file have been redirected.
            report.modifiedAppleAssetIDs = manifest.assets
                .filter { pristine.contains($0.id) && $0.isLocalMedia }
                .map(\.id)
        }
        report.liveCanvasAssetIDs = manifest.assets
            .filter { ($0.shotID ?? "").hasPrefix(AerialAssetFactory.shotIDPrefix) }
            .map(\.id)

        // 5. Writability — checked without creating anything permanent.
        report.isWritable = fm.isWritableFile(atPath: locator.entriesFile.path)
            && fm.isWritableFile(atPath: locator.videosDirectory.path)
            && fm.isWritableFile(atPath: locator.thumbnailsDirectory.path)
        if !report.isWritable {
            report.health = .notInitialized("The Aerial wallpaper store is not writable by your user account.")
        }

        return report
    }

    /// Asset IDs from the untouched `entries.json` inside `manifest.tar`.
    /// Apple ships this tar on disk, so the comparison needs no network access.
    func pristineAssetIDs() throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: locator.manifestTar.path) else {
            throw LiveCanvasError.wallpaperStoreNotInitialized("manifest.tar is not present.")
        }
        let data = try TarReader.extractFile(named: "entries.json", from: locator.manifestTar)
        let manifest = try AerialManifestParser.parse(data)
        return Set(manifest.assets.map(\.id))
    }

    func loadManifest() throws -> AerialManifest {
        try AerialManifestParser.parse(try Data(contentsOf: locator.entriesFile))
    }
}
