import Foundation

/// Application-owned directories under ~/Library/Application Support/<ProductName>/.
/// All directories are created lazily on first access.
enum AppDirectories {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return ensure(base.appendingPathComponent(AppInfo.name, isDirectory: true))
    }

    static var media: URL { ensure(root.appendingPathComponent("Media", isDirectory: true)) }
    static var thumbnails: URL { ensure(root.appendingPathComponent("Thumbnails", isDirectory: true)) }
    static var lockScreen: URL { ensure(root.appendingPathComponent("LockScreen", isDirectory: true)) }
    static var backups: URL { ensure(root.appendingPathComponent("Backups", isDirectory: true)) }
    static var temp: URL { ensure(root.appendingPathComponent("Temp", isDirectory: true)) }

    static var libraryFile: URL { root.appendingPathComponent("library.json") }
    static var settingsFile: URL { root.appendingPathComponent("settings.json") }

    @discardableResult
    static func ensure(_ url: URL) -> URL {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
}
