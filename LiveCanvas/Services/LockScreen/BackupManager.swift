import Foundation

/// One backed-up file: where it came from, what it hashed to, and its POSIX mode.
struct BackupEntry: Codable, Equatable, Sendable {
    var originalPath: String
    var storedName: String
    var sha256: String
    var byteSize: Int64
    var posixPermissions: Int
    /// True when the file did not exist at backup time; restoring means deleting it again.
    var wasAbsent: Bool
}

/// Metadata describing one complete backup.
struct BackupManifest: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int = BackupManifest.currentVersion
    var id: UUID
    var createdAt: Date
    var osVersion: String
    var appVersion: String
    var note: String
    var entries: [BackupEntry]
    /// Files LiveCanvas added (not modified). Restoring deletes them.
    var addedPaths: [String] = []
}

/// Creates and restores verified backups. Nothing in LiveCanvas modifies a macOS-owned
/// file except through a backup taken and re-verified by this type first.
struct BackupManager: Sendable {
    var rootDirectory: URL

    init(rootDirectory: URL = AppDirectories.backups) {
        self.rootDirectory = rootDirectory
    }

    func directory(for id: UUID) -> URL {
        rootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func manifestURL(for id: UUID) -> URL {
        directory(for: id).appendingPathComponent("manifest.json")
    }

    // MARK: Create

    /// Copies each URL into a fresh backup directory, hashing before and after the copy.
    /// Throws if any hash fails to match, leaving no partial backup behind.
    func createBackup(of urls: [URL], note: String, addedPaths: [String] = []) throws -> BackupManifest {
        let id = UUID()
        let dir = directory(for: id)
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            var entries: [BackupEntry] = []

            for url in urls {
                let exists = fm.fileExists(atPath: url.path)
                if !exists {
                    entries.append(BackupEntry(originalPath: url.path, storedName: "", sha256: "",
                                               byteSize: 0, posixPermissions: 0, wasAbsent: true))
                    continue
                }

                let sourceHash = try FileUtilities.sha256(of: url)
                let attributes = try fm.attributesOfItem(atPath: url.path)
                let permissions = (attributes[.posixPermissions] as? Int) ?? 0o644
                let size = (attributes[.size] as? Int64) ?? 0

                // Unique stored name so two files with the same basename cannot collide.
                let storedName = "\(entries.count)-\(url.lastPathComponent)"
                let destination = dir.appendingPathComponent(storedName)
                try fm.copyItem(at: url, to: destination)

                // Re-hash the copy: a backup that cannot be proven good is not a backup.
                let copyHash = try FileUtilities.sha256(of: destination)
                guard copyHash == sourceHash else {
                    throw LiveCanvasError.backupFailed("The backup copy of \(url.lastPathComponent) does not match the original.")
                }

                entries.append(BackupEntry(originalPath: url.path, storedName: storedName, sha256: sourceHash,
                                           byteSize: size, posixPermissions: permissions, wasAbsent: false))
            }

            let manifest = BackupManifest(
                id: id,
                createdAt: Date(),
                osVersion: OSVersion.current.description,
                appVersion: "\(AppInfo.version) (\(AppInfo.build))",
                note: note,
                entries: entries,
                addedPaths: addedPaths
            )
            try writeManifest(manifest)
            Log.lockscreen.info("Backup \(id.uuidString, privacy: .public) created with \(entries.count) file(s)")
            return manifest
        } catch {
            try? fm.removeItem(at: dir)
            if let lc = error as? LiveCanvasError { throw lc }
            throw LiveCanvasError.backupFailed(error.localizedDescription)
        }
    }

    func writeManifest(_ manifest: BackupManifest) throws {
        try AtomicFileWriter.write(try JSONCoding.encoder().encode(manifest), to: manifestURL(for: manifest.id))
    }

    // MARK: Read

    func loadManifest(id: UUID) throws -> BackupManifest {
        let url = manifestURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LiveCanvasError.backupFailed("Backup \(id.uuidString) is missing its manifest.")
        }
        return try JSONCoding.decoder().decode(BackupManifest.self, from: try Data(contentsOf: url))
    }

    /// All backups, newest first.
    func listBackups() -> [BackupManifest] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: nil) else { return [] }
        return dirs.compactMap { dir in
            guard let id = UUID(uuidString: dir.lastPathComponent) else { return nil }
            return try? loadManifest(id: id)
        }
        // Deterministic even when two backups share a timestamp.
        .sorted { ($0.createdAt, $0.id.uuidString) > ($1.createdAt, $1.id.uuidString) }
    }

    /// Confirms every stored copy still hashes to what the manifest recorded.
    func verifyBackup(_ manifest: BackupManifest) throws {
        let dir = directory(for: manifest.id)
        for entry in manifest.entries where !entry.wasAbsent {
            let stored = dir.appendingPathComponent(entry.storedName)
            guard FileManager.default.fileExists(atPath: stored.path) else {
                throw LiveCanvasError.backupFailed("Backup file \(entry.storedName) is missing.")
            }
            guard try FileUtilities.sha256(of: stored) == entry.sha256 else {
                throw LiveCanvasError.backupFailed("Backup file \(entry.storedName) is corrupt.")
            }
        }
    }

    /// Reports which backed-up originals have changed on disk since the backup was made.
    func changedSinceBackup(_ manifest: BackupManifest) -> [BackupEntry] {
        manifest.entries.filter { entry in
            guard !entry.wasAbsent else { return false }
            let url = URL(fileURLWithPath: entry.originalPath)
            guard FileManager.default.fileExists(atPath: url.path) else { return true }
            guard let hash = try? FileUtilities.sha256(of: url) else { return true }
            return hash != entry.sha256
        }
    }

    // MARK: Restore

    /// Restores every backed-up file and deletes files the backup recorded as added.
    /// The backup is verified first; a corrupt backup aborts before anything is written.
    func restore(_ manifest: BackupManifest) throws {
        try verifyBackup(manifest)
        let dir = directory(for: manifest.id)
        let fm = FileManager.default

        for entry in manifest.entries {
            let destination = URL(fileURLWithPath: entry.originalPath)
            if entry.wasAbsent {
                // The file did not exist before; put things back by removing it.
                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }
                continue
            }
            let stored = dir.appendingPathComponent(entry.storedName)
            // Stage a copy so the stored backup survives a failed replace and can be retried.
            let staging = destination.deletingLastPathComponent()
                .appendingPathComponent(".\(destination.lastPathComponent).restore-\(UUID().uuidString)")
            try fm.copyItem(at: stored, to: staging)
            do {
                try AtomicFileWriter.replace(destination, with: staging)
            } catch {
                try? fm.removeItem(at: staging)
                throw LiveCanvasError.backupFailed("Could not restore \(destination.lastPathComponent): \(error.localizedDescription)")
            }
            try? fm.setAttributes([.posixPermissions: entry.posixPermissions], ofItemAtPath: destination.path)

            guard try FileUtilities.sha256(of: destination) == entry.sha256 else {
                throw LiveCanvasError.backupFailed("Restored file \(destination.lastPathComponent) does not match the backup.")
            }
        }

        for path in manifest.addedPaths {
            let url = URL(fileURLWithPath: path)
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
            }
        }
        Log.lockscreen.info("Backup \(manifest.id.uuidString, privacy: .public) restored")
    }

    func deleteBackup(id: UUID) {
        try? FileManager.default.removeItem(at: directory(for: id))
    }
}
