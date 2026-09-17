import Foundation

/// A decoded `entries.json`. Decoding is deliberately permissive about unknown keys and
/// preserves the original JSON so a write can round-trip untouched fields byte-for-byte.
struct AerialManifest: @unchecked Sendable {
    /// The raw top-level object exactly as parsed, so unknown keys survive a re-write.
    var raw: [String: Any]
    var version: Int
    var assets: [AerialAsset]

    /// The media key actually used by this manifest (e.g. "url-4K-SDR-240FPS").
    /// Discovered from the data — never hard-coded.
    var mediaKey: String

    static let mediaKeyPrefix = "url-"
}

/// One asset entry. `raw` keeps every field so nothing is lost on re-encode.
struct AerialAsset: @unchecked Sendable, Identifiable, Equatable {
    var raw: [String: Any]
    var id: String
    var name: String
    var mediaURLString: String
    var previewImageString: String?
    var shotID: String?

    /// True when the media URL points at a local file rather than Apple's CDN.
    var isLocalMedia: Bool { mediaURLString.hasPrefix("file:") }

    var localMediaURL: URL? {
        guard isLocalMedia else { return nil }
        return URL(string: mediaURLString)
    }

    static func == (lhs: AerialAsset, rhs: AerialAsset) -> Bool {
        lhs.id == rhs.id && lhs.mediaURLString == rhs.mediaURLString && lhs.name == rhs.name
    }
}

enum AerialManifestParser {
    /// Parses entries.json. Throws `LiveCanvasError.wallpaperStoreNotInitialized` when the
    /// document is not the shape LiveCanvas validated against macOS 26.
    static func parse(_ data: Data) throws -> AerialManifest {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LiveCanvasError.wallpaperStoreNotInitialized("entries.json is not a JSON object.")
        }
        guard let version = root["version"] as? Int else {
            throw LiveCanvasError.wallpaperStoreNotInitialized("entries.json has no 'version' field.")
        }
        guard let rawAssets = root["assets"] as? [[String: Any]], !rawAssets.isEmpty else {
            throw LiveCanvasError.wallpaperStoreNotInitialized("entries.json has no 'assets' array.")
        }

        // Discover the media key from the data itself.
        var keyCounts: [String: Int] = [:]
        for asset in rawAssets {
            for key in asset.keys where key.hasPrefix(AerialManifest.mediaKeyPrefix) {
                keyCounts[key, default: 0] += 1
            }
        }
        guard let mediaKey = keyCounts.max(by: { $0.value < $1.value })?.key else {
            throw LiveCanvasError.wallpaperStoreNotInitialized("No 'url-*' media key found on any asset in entries.json.")
        }

        var assets: [AerialAsset] = []
        assets.reserveCapacity(rawAssets.count)
        for raw in rawAssets {
            guard let id = raw["id"] as? String, !id.isEmpty else {
                throw LiveCanvasError.wallpaperStoreNotInitialized("An asset in entries.json has no 'id'.")
            }
            guard let media = raw[mediaKey] as? String else { continue }   // variant-only entries are skipped
            assets.append(AerialAsset(
                raw: raw,
                id: id,
                name: (raw["accessibilityLabel"] as? String) ?? (raw["localizedNameKey"] as? String) ?? id,
                mediaURLString: media,
                previewImageString: raw["previewImage"] as? String,
                shotID: raw["shotID"] as? String
            ))
        }
        guard !assets.isEmpty else {
            throw LiveCanvasError.wallpaperStoreNotInitialized("No asset in entries.json carries the '\(mediaKey)' media key.")
        }
        return AerialManifest(raw: root, version: version, assets: assets, mediaKey: mediaKey)
    }

    /// Re-encodes a manifest, preserving every untouched key. Sorted keys keep diffs stable.
    static func encode(_ manifest: AerialManifest, assets: [AerialAsset]) throws -> Data {
        var root = manifest.raw
        root["assets"] = assets.map(\.raw)
        guard JSONSerialization.isValidJSONObject(root) else {
            throw LiveCanvasError.preparationFailed("Refusing to write a manifest that is not valid JSON.")
        }
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}
