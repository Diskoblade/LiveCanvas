import Testing
import Foundation
@testable import LiveCanvas

struct BackupManagerTests {
    private func sandbox() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lc-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test func backupRecordsHashesSizesAndPermissions() throws {
        let box = try sandbox(); defer { try? FileManager.default.removeItem(at: box) }
        let a = box.appendingPathComponent("a.json")
        try write("alpha", to: a)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: a.path)

        let manager = BackupManager(rootDirectory: box.appendingPathComponent("Backups"))
        let manifest = try manager.createBackup(of: [a], note: "test")

        #expect(manifest.entries.count == 1)
        let entry = manifest.entries[0]
        #expect(entry.sha256 == (try FileUtilities.sha256(of: a)))
        #expect(entry.byteSize == 5)
        #expect(entry.posixPermissions == 0o640)
        #expect(!entry.wasAbsent)
        #expect(manifest.osVersion == OSVersion.current.description)
        try manager.verifyBackup(manifest)
    }

    @Test func restoreReturnsExactBytesAndPermissions() throws {
        let box = try sandbox(); defer { try? FileManager.default.removeItem(at: box) }
        let a = box.appendingPathComponent("a.json")
        try write("original contents", to: a)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: a.path)
        let originalHash = try FileUtilities.sha256(of: a)

        let manager = BackupManager(rootDirectory: box.appendingPathComponent("Backups"))
        let manifest = try manager.createBackup(of: [a], note: "test")

        try write("CLOBBERED", to: a)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: a.path)
        #expect(try FileUtilities.sha256(of: a) != originalHash)

        try manager.restore(manifest)
        #expect(try FileUtilities.sha256(of: a) == originalHash)
        let perms = try FileManager.default.attributesOfItem(atPath: a.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
    }

    @Test func restoreDeletesFilesTheBackupRecordedAsAdded() throws {
        let box = try sandbox(); defer { try? FileManager.default.removeItem(at: box) }
        let existing = box.appendingPathComponent("keep.json")
        try write("keep", to: existing)
        let added = box.appendingPathComponent("added.mov")

        let manager = BackupManager(rootDirectory: box.appendingPathComponent("Backups"))
        let manifest = try manager.createBackup(of: [existing], note: "t", addedPaths: [added.path])
        try write("new file", to: added)
        #expect(FileManager.default.fileExists(atPath: added.path))

        try manager.restore(manifest)
        #expect(!FileManager.default.fileExists(atPath: added.path))
        #expect(FileManager.default.fileExists(atPath: existing.path))
    }

    @Test func absentFileIsRecordedAndRemovedOnRestore() throws {
        let box = try sandbox(); defer { try? FileManager.default.removeItem(at: box) }
        let missing = box.appendingPathComponent("later.json")
        let manager = BackupManager(rootDirectory: box.appendingPathComponent("Backups"))
        let manifest = try manager.createBackup(of: [missing], note: "t")
        #expect(manifest.entries[0].wasAbsent)

        try write("created after backup", to: missing)
        try manager.restore(manifest)
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }

    @Test func corruptBackupIsDetectedAndRestoreRefuses() throws {
        let box = try sandbox(); defer { try? FileManager.default.removeItem(at: box) }
        let a = box.appendingPathComponent("a.json")
        try write("good", to: a)
        let root = box.appendingPathComponent("Backups")
        let manager = BackupManager(rootDirectory: root)
        let manifest = try manager.createBackup(of: [a], note: "t")

        // Tamper with the stored copy.
        let stored = manager.directory(for: manifest.id).appendingPathComponent(manifest.entries[0].storedName)
        try Data("tampered".utf8).write(to: stored)

        #expect(throws: LiveCanvasError.self) { try manager.verifyBackup(manifest) }
        #expect(throws: LiveCanvasError.self) { try manager.restore(manifest) }
        // The live file must be untouched by the refused restore.
        #expect(String(data: try Data(contentsOf: a), encoding: .utf8) == "good")
    }

    @Test func changedSinceBackupDetectsExternalEdits() throws {
        let box = try sandbox(); defer { try? FileManager.default.removeItem(at: box) }
        let a = box.appendingPathComponent("a.json"), b = box.appendingPathComponent("b.json")
        try write("a", to: a); try write("b", to: b)
        let manager = BackupManager(rootDirectory: box.appendingPathComponent("Backups"))
        let manifest = try manager.createBackup(of: [a, b], note: "t")
        #expect(manager.changedSinceBackup(manifest).isEmpty)

        try write("a changed", to: a)
        let changed = manager.changedSinceBackup(manifest)
        #expect(changed.count == 1)
        #expect(changed[0].originalPath == a.path)

        try FileManager.default.removeItem(at: b)
        #expect(manager.changedSinceBackup(manifest).count == 2)   // deletion counts as changed
    }

    @Test func backupsAreListedNewestFirstAndRoundTrip() throws {
        let box = try sandbox(); defer { try? FileManager.default.removeItem(at: box) }
        let a = box.appendingPathComponent("a.json")
        try write("x", to: a)
        let manager = BackupManager(rootDirectory: box.appendingPathComponent("Backups"))
        let first = try manager.createBackup(of: [a], note: "first")
        Thread.sleep(forTimeInterval: 0.02)
        let second = try manager.createBackup(of: [a], note: "second")

        let list = manager.listBackups()
        #expect(list.count == 2)
        #expect(list[0].id == second.id)
        #expect(list[1].id == first.id)
        #expect(try manager.loadManifest(id: first.id).note == "first")

        manager.deleteBackup(id: first.id)
        #expect(manager.listBackups().count == 1)
    }

    @Test func failedBackupLeavesNoPartialDirectory() throws {
        let box = try sandbox(); defer { try? FileManager.default.removeItem(at: box) }
        let root = box.appendingPathComponent("Backups")
        let manager = BackupManager(rootDirectory: root)
        // A directory cannot be copied by copyItem into a file destination path; use an
        // unreadable source to force failure.
        let unreadable = box.appendingPathComponent("nope")
        try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: unreadable.appendingPathComponent("inner"))
        // Backing up a directory succeeds for copyItem but sha256 of a directory fails.
        #expect(throws: (any Error).self) { _ = try manager.createBackup(of: [unreadable], note: "t") }
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        #expect(leftovers.isEmpty)
    }
}

struct BackupOrderingTests {
    @Test func timestampsSurviveSubSecondRoundTrip() throws {
        // Regression: plain .iso8601 truncates to whole seconds, which made two backups
        // created in the same second indistinguishable after a reload.
        let box = FileManager.default.temporaryDirectory.appendingPathComponent("lc-order-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: box, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: box) }
        let file = box.appendingPathComponent("f.json")
        try Data("x".utf8).write(to: file)

        let manager = BackupManager(rootDirectory: box.appendingPathComponent("B"))
        var created: [BackupManifest] = []
        for _ in 0..<5 { created.append(try manager.createBackup(of: [file], note: "n")) }

        // All five land inside the same second. Ordering must be a stable total order,
        // and the newest must come first — neither is true with whole-second timestamps.
        let listed = manager.listBackups()
        #expect(listed.count == 5)
        #expect(listed.map(\.id) == manager.listBackups().map(\.id), "ordering must be stable")
        let newest = listed.map(\.createdAt)
        #expect(newest == newest.sorted(by: >), "listBackups must return newest first")
        #expect(Set(listed.map(\.createdAt)).count > 1, "sub-second timestamps must be distinguishable")

        // Sub-second component must survive the encode/decode round trip.
        let reloaded = try manager.loadManifest(id: created[0].id)
        #expect(abs(reloaded.createdAt.timeIntervalSince(created[0].createdAt)) < 0.002)

        // And the whole-second formatter of earlier builds must still decode.
        let legacy = Data(#"{"version":1,"id":"\#(UUID().uuidString)","createdAt":"2026-01-02T03:04:05Z","osVersion":"26.0.0","appVersion":"1","note":"n","entries":[],"addedPaths":[]}"#.utf8)
        #expect(throws: Never.self) { try JSONCoding.decoder().decode(BackupManifest.self, from: legacy) }
    }
}
