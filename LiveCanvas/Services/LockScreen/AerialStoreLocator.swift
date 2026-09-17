import Foundation

/// Filesystem locations of the per-user Aerial store. Injectable so tests can run against
/// a synthetic store instead of the real one.
struct AerialStoreLocator: Sendable, Equatable {
    var root: URL

    init(root: URL) { self.root = root }

    static var userDefault: AerialStoreLocator {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return AerialStoreLocator(root: base.appendingPathComponent("com.apple.wallpaper", isDirectory: true))
    }

    var aerials: URL { root.appendingPathComponent("aerials", isDirectory: true) }
    var manifestDirectory: URL { aerials.appendingPathComponent("manifest", isDirectory: true) }
    var entriesFile: URL { manifestDirectory.appendingPathComponent("entries.json") }
    var manifestSourceFile: URL { manifestDirectory.appendingPathComponent("manifest.source") }
    var manifestTar: URL { aerials.appendingPathComponent("manifest.tar") }
    var videosDirectory: URL { aerials.appendingPathComponent("videos", isDirectory: true) }
    var thumbnailsDirectory: URL { aerials.appendingPathComponent("thumbnails", isDirectory: true) }
    var storeDirectory: URL { root.appendingPathComponent("Store", isDirectory: true) }
    var indexFile: URL { storeDirectory.appendingPathComponent("Index.plist") }

    func videoURL(for assetID: String) -> URL { videosDirectory.appendingPathComponent("\(assetID).mov") }
    func thumbnailURL(for assetID: String) -> URL { thumbnailsDirectory.appendingPathComponent("\(assetID).png") }
}
