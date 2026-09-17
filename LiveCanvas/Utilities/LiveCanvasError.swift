import Foundation

/// User-facing errors. Every failure path in the app surfaces one of these; nothing fails silently.
enum LiveCanvasError: LocalizedError, Equatable {
    case unsupportedOS(String)
    case unsupportedFileType(String)
    case videoUndecodable(String)
    case importFailed(String)
    case thumbnailFailed(String)
    case lockScreenUnavailable(String)
    case wallpaperStoreNotInitialized(String)
    case backupFailed(String)
    case preparationFailed(String)
    case displayDisconnected(String)
    case originalAssetChanged(String)
    case persistenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedOS: return "Unsupported macOS version"
        case .unsupportedFileType: return "Unsupported file type"
        case .videoUndecodable: return "Video could not be decoded"
        case .importFailed: return "Import failed"
        case .thumbnailFailed: return "Thumbnail could not be generated"
        case .lockScreenUnavailable: return "Lock Screen integration unavailable"
        case .wallpaperStoreNotInitialized: return "Wallpaper store not initialized"
        case .backupFailed: return "Backup failed"
        case .preparationFailed: return "Wallpaper preparation failed"
        case .displayDisconnected: return "Display disconnected"
        case .originalAssetChanged: return "Original Lock Screen asset changed since backup"
        case .persistenceFailed: return "Could not save settings"
        }
    }

    var failureReason: String? {
        switch self {
        case .unsupportedOS(let s), .unsupportedFileType(let s), .videoUndecodable(let s),
             .importFailed(let s), .thumbnailFailed(let s), .lockScreenUnavailable(let s),
             .wallpaperStoreNotInitialized(let s), .backupFailed(let s), .preparationFailed(let s),
             .displayDisconnected(let s), .originalAssetChanged(let s), .persistenceFailed(let s):
            return s
        }
    }
}

/// Wrapper so any `Error` can drive a SwiftUI alert.
struct PresentableError: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    init(_ error: Error) {
        if let lc = error as? LiveCanvasError {
            title = lc.errorDescription ?? "Error"
            message = lc.failureReason ?? ""
        } else {
            title = "Error"
            message = error.localizedDescription
        }
    }

    init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}
