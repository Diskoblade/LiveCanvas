import Foundation

/// Media categories the ingestion layer knows about. Only `.video` is implemented today;
/// the others exist so GIF/APNG/WebM/image sequences can be added without a schema change.
enum MediaKind: String, Codable, Sendable {
    case video
    case animatedImage
    case imageSequence
}

enum VideoCodec: String, Codable, Sendable {
    case h264
    case hevc
    case proRes
    case other

    var displayName: String {
        switch self {
        case .h264: return "H.264"
        case .hevc: return "HEVC"
        case .proRes: return "ProRes"
        case .other: return "Other"
        }
    }
}

enum DynamicRange: String, Codable, Sendable {
    case sdr
    case hdr
    case unknown

    var displayName: String {
        switch self {
        case .sdr: return "SDR"
        case .hdr: return "HDR"
        case .unknown: return "Unknown"
        }
    }
}

/// One wallpaper in the user's library. File locations are stored relative to the
/// application's Media / Thumbnails directories so the library survives a rename or move
/// of the Application Support folder.
struct WallpaperAsset: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var displayName: String
    var sourceURL: URL?
    var managedFileName: String
    var thumbnailFileName: String?
    var kind: MediaKind
    var duration: TimeInterval
    var pixelWidth: Int
    var pixelHeight: Int
    var frameRate: Double
    var codec: VideoCodec
    var codecFourCC: String
    var dynamicRange: DynamicRange
    var hasAudio: Bool
    var fileSize: Int64
    var dateImported: Date

    var aspectRatio: Double {
        guard pixelHeight > 0 else { return 16.0 / 9.0 }
        return Double(pixelWidth) / Double(pixelHeight)
    }

    var isPortrait: Bool { pixelHeight > pixelWidth }

    var resolutionLabel: String { "\(pixelWidth) × \(pixelHeight)" }

    /// Marketing-style shorthand based on the longer edge.
    var qualityLabel: String {
        let long = max(pixelWidth, pixelHeight)
        switch long {
        case 7600...: return "8K"
        case 5900...: return "6K"
        case 5000...: return "5K"
        case 3800...: return "4K"
        case 2500...: return "1440p"
        case 1900...: return "1080p"
        case 1200...: return "720p"
        default: return "\(pixelHeight)p"
        }
    }

    var durationLabel: String { FileUtilities.formattedDuration(duration) }
    var fileSizeLabel: String { FileUtilities.formattedSize(fileSize) }
    var frameRateLabel: String { String(format: frameRate.rounded() == frameRate ? "%.0f fps" : "%.2f fps", frameRate) }
}
