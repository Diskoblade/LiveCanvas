import Foundation

/// Builds the `entries.json` asset object for a LiveCanvas wallpaper.
/// The shape mirrors what macOS 26 itself stores (see docs/TAHOE_AERIAL_FORMAT.md);
/// the media and preview URLs are local `file://` URLs rather than Apple CDN URLs.
enum AerialAssetFactory {
    /// Every entry LiveCanvas writes is tagged with this prefix in `shotID`, so the app can
    /// always tell its own entries apart from Apple's and from other tools'.
    static let shotIDPrefix = "LIVECANVAS_"

    /// Stable category UUIDs for the group LiveCanvas entries appear under.
    static let categoryID = "8E8A5C1D-9E4F-4C2B-9A7E-1C0F5B2D3A41"
    static let subcategoryID = "8E8A5C1D-9E4F-4C2B-9A7E-1C0F5B2D3A42"

    static func isLiveCanvasAsset(_ asset: AerialAsset) -> Bool {
        (asset.shotID ?? "").hasPrefix(shotIDPrefix)
    }

    /// - Parameters:
    ///   - id: the asset UUID (also the video and thumbnail file name)
    ///   - name: what the user sees in System Settings
    ///   - mediaKey: the key discovered from the live manifest, e.g. "url-4K-SDR-240FPS"
    static func makeAsset(id: String, name: String, mediaKey: String, videoURL: URL, thumbnailURL: URL?) -> AerialAsset {
        var raw: [String: Any] = [
            "id": id,
            "accessibilityLabel": name,
            "localizedNameKey": name,               // no loctable entry: shown verbatim
            "shotID": shotIDPrefix + String(id.prefix(8)),
            "categories": [categoryID],
            "subcategories": [subcategoryID],
            "preferredOrder": 0,
            "showInTopLevel": true,
            "includeInShuffle": false,              // a custom wallpaper should not join shuffle
            "pointsOfInterest": [String: String](),
            mediaKey: fileURLString(videoURL),
        ]
        if let thumbnailURL {
            raw["previewImage"] = fileURLString(thumbnailURL)
        }
        return AerialAsset(
            raw: raw,
            id: id,
            name: name,
            mediaURLString: fileURLString(videoURL),
            previewImageString: thumbnailURL.map(fileURLString),
            shotID: raw["shotID"] as? String
        )
    }

    /// Percent-encoded absolute file URL string, matching how macOS writes these values.
    static func fileURLString(_ url: URL) -> String {
        url.absoluteString
    }
}
