import Foundation
import Observation
import UniformTypeIdentifiers

/// The wallpaper library: imports files into the managed Media directory, probes
/// metadata, generates posters, and persists everything to library.json.
@MainActor
@Observable
final class VideoAssetManager {
    private(set) var assets: [WallpaperAsset] = []
    private(set) var importsInProgress: Int = 0
    var lastError: PresentableError?

    /// Called after an asset is deleted so dependants (assignments, engine) can react.
    var onAssetDeleted: ((WallpaperAsset) -> Void)?

    private let store: LibraryStore
    private let mediaDirectory: URL
    private let thumbnailDirectory: URL
    private let metadata = VideoMetadataService()
    private let thumbnails = ThumbnailGenerator()

    static let supportedTypes: [UTType] = [.mpeg4Movie, .quickTimeMovie, UTType("com.apple.m4v-video") ?? .movie]
    static let supportedExtensions: Set<String> = ["mp4", "mov", "m4v"]

    init(store: LibraryStore = LibraryStore(),
         mediaDirectory: URL = AppDirectories.media,
         thumbnailDirectory: URL = AppDirectories.thumbnails) {
        self.store = store
        self.mediaDirectory = mediaDirectory
        self.thumbnailDirectory = thumbnailDirectory
        load()
    }

    // MARK: Lookup

    func asset(id: UUID?) -> WallpaperAsset? {
        guard let id else { return nil }
        return assets.first { $0.id == id }
    }

    func mediaURL(for asset: WallpaperAsset) -> URL {
        mediaDirectory.appendingPathComponent(asset.managedFileName)
    }

    func thumbnailURL(for asset: WallpaperAsset) -> URL? {
        guard let name = asset.thumbnailFileName else { return nil }
        return thumbnailDirectory.appendingPathComponent(name)
    }

    static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: Import

    /// Imports files sequentially. Unsupported or broken files are reported via `lastError`
    /// and skipped; successful ones are added as they complete.
    func importFiles(_ urls: [URL]) async {
        for url in urls {
            await importFile(url)
        }
    }

    @discardableResult
    func importFile(_ url: URL) async -> WallpaperAsset? {
        importsInProgress += 1
        defer { importsInProgress -= 1 }

        guard Self.isSupported(url) else {
            report(LiveCanvasError.unsupportedFileType("\(url.lastPathComponent) is not an MP4, MOV or M4V file."))
            return nil
        }

        let id = UUID()
        let ext = url.pathExtension.lowercased()
        let managedName = "\(id.uuidString).\(ext)"
        let managedURL = mediaDirectory.appendingPathComponent(managedName)

        do {
            let probe = try await metadata.probe(url)
            guard probe.isPlayable else {
                throw LiveCanvasError.videoUndecodable("\(url.lastPathComponent) is not playable by AVFoundation (\(probe.codecFourCC)).")
            }

            try await Self.copy(from: url, to: managedURL)

            var asset = WallpaperAsset(
                id: id,
                displayName: url.deletingPathExtension().lastPathComponent,
                sourceURL: url,
                managedFileName: managedName,
                thumbnailFileName: nil,
                kind: .video,
                duration: probe.duration,
                pixelWidth: probe.pixelWidth,
                pixelHeight: probe.pixelHeight,
                frameRate: probe.frameRate,
                codec: probe.codec,
                codecFourCC: probe.codecFourCC,
                dynamicRange: probe.dynamicRange,
                hasAudio: probe.hasAudio,
                fileSize: FileUtilities.fileSize(of: managedURL),
                dateImported: Date()
            )

            assets.append(asset)
            persist()
            Log.media.info("Imported \(url.lastPathComponent, privacy: .public) as \(id.uuidString, privacy: .public) \(probe.pixelWidth)x\(probe.pixelHeight) \(probe.codecFourCC, privacy: .public)")

            // Poster generation is best-effort and does not block the import.
            let thumbName = "\(id.uuidString).jpg"
            let thumbURL = thumbnailDirectory.appendingPathComponent(thumbName)
            do {
                try await thumbnails.generatePoster(for: managedURL, duration: probe.duration, to: thumbURL)
                asset.thumbnailFileName = thumbName
                replace(asset)
            } catch {
                Log.media.error("Thumbnail failed for \(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            return asset
        } catch {
            try? FileManager.default.removeItem(at: managedURL)
            report(error is LiveCanvasError ? error : LiveCanvasError.importFailed(error.localizedDescription))
            return nil
        }
    }

    private nonisolated static func copy(from source: URL, to destination: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        }.value
    }

    // MARK: Mutation

    func rename(_ asset: WallpaperAsset, to name: String) {
        var copy = asset
        copy.displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !copy.displayName.isEmpty else { return }
        replace(copy)
    }

    func delete(_ asset: WallpaperAsset) {
        assets.removeAll { $0.id == asset.id }
        persist()
        onAssetDeleted?(asset)
        let media = mediaURL(for: asset)
        let thumb = thumbnailURL(for: asset)
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: media)
            if let thumb { try? FileManager.default.removeItem(at: thumb) }
        }
        Log.media.info("Deleted asset \(asset.id.uuidString, privacy: .public)")
    }

    private func replace(_ asset: WallpaperAsset) {
        guard let idx = assets.firstIndex(where: { $0.id == asset.id }) else { return }
        assets[idx] = asset
        persist()
    }

    // MARK: Persistence

    private func load() {
        do {
            let doc = try store.load()
            // Drop records whose media vanished (e.g. user deleted the folder).
            assets = doc.assets.filter { FileManager.default.fileExists(atPath: mediaDirectory.appendingPathComponent($0.managedFileName).path) }
            if assets.count != doc.assets.count { persist() }
        } catch {
            Log.persistence.error("Library unreadable: \(error.localizedDescription, privacy: .public)")
            lastError = PresentableError(LiveCanvasError.persistenceFailed("The wallpaper library file could not be read."))
        }
    }

    private func persist() {
        do {
            try store.save(LibraryDocument(assets: assets))
        } catch {
            Log.persistence.error("Library save failed: \(error.localizedDescription, privacy: .public)")
            lastError = PresentableError(LiveCanvasError.persistenceFailed(error.localizedDescription))
        }
    }

    private func report(_ error: Error) {
        Log.media.error("\(error.localizedDescription, privacy: .public)")
        lastError = PresentableError(error)
    }
}
