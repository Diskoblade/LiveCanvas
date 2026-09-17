import Testing
import Foundation
@testable import LiveCanvas

struct PersistenceTests {
    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LiveCanvasTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func atomicWriterCreatesAndReplacesPreservingPermissions() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.json")
        try AtomicFileWriter.write(Data("one".utf8), to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        try AtomicFileWriter.write(Data("two".utf8), to: file)
        #expect(String(data: try Data(contentsOf: file), encoding: .utf8) == "two")
        let perms = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix(".") }
        #expect(leftovers.isEmpty)
    }

    @Test func sha256MatchesKnownVector() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("abc.txt")
        try Data("abc".utf8).write(to: file)
        #expect(try FileUtilities.sha256(of: file) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func libraryStoreRoundTrip() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LibraryStore(fileURL: dir.appendingPathComponent("library.json"))
        #expect(try store.load().assets.isEmpty)
        let asset = WallpaperAsset(id: UUID(), displayName: "Ocean", sourceURL: nil, managedFileName: "o.mov", thumbnailFileName: "o.jpg",
                                   kind: .video, duration: 9, pixelWidth: 1920, pixelHeight: 1080, frameRate: 59.94, codec: .h264,
                                   codecFourCC: "avc1", dynamicRange: .sdr, hasAudio: true, fileSize: 10, dateImported: Date())
        try store.save(LibraryDocument(assets: [asset]))
        let loaded = try store.load()
        #expect(loaded.assets == [asset].map { var a = $0; a.dateImported = loaded.assets[0].dateImported; return a })
    }

    @Test @MainActor func preferencesStorePersistsUpdates() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")
        let store = PreferencesStore(fileURL: url)
        store.update { $0.playback.quality = .batterySaver; $0.startAtLogin = true }
        store.saveNow()
        let reloaded = PreferencesStore(fileURL: url)
        #expect(reloaded.settings.playback.quality == .batterySaver)
        #expect(reloaded.settings.startAtLogin)
    }
}
