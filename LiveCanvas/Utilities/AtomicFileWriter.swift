import Foundation

/// Writes data by staging to a temporary file in the destination directory and then
/// replacing the destination in one filesystem operation. Preserves the destination's
/// POSIX permissions when it already exists.
enum AtomicFileWriter {
    static func write(_ data: Data, to destination: URL) throws {
        let fm = FileManager.default
        let dir = destination.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let temp = dir.appendingPathComponent(".\(destination.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: temp, options: .atomic)
        try replace(destination, with: temp)
    }

    /// Atomically moves `source` over `destination`, keeping the destination's permissions
    /// and extended attributes if it exists. `source` is consumed.
    static func replace(_ destination: URL, with source: URL) throws {
        let fm = FileManager.default
        var originalPermissions: Int?
        if fm.fileExists(atPath: destination.path) {
            originalPermissions = try? fm.attributesOfItem(atPath: destination.path)[.posixPermissions] as? Int
            // Keep the destination's identity (permissions/xattrs) rather than the temp file's.
            _ = try fm.replaceItemAt(destination, withItemAt: source, backupItemName: nil, options: [.usingNewMetadataOnly])
        } else {
            try fm.moveItem(at: source, to: destination)
        }
        if let perms = originalPermissions {
            try? fm.setAttributes([.posixPermissions: perms], ofItemAtPath: destination.path)
        }
    }
}
