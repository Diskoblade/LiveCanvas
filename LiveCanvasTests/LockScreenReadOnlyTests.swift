import Testing
import Foundation
@testable import LiveCanvas

/// Milestone 6: everything here is READ-ONLY. No test in this file writes to the real
/// Aerial store. Write paths are exercised against synthetic stores in LockScreenInstallTests.
struct LockScreenReadOnlyTests {

    // MARK: Compatibility gate

    @Test func compatibilityAcceptsOnlyTheValidatedMajorVersion() {
        #expect(LockScreenCompatibility(osVersion: OSVersion(major: 26, minor: 0, patch: 0)).isSupported)
        #expect(LockScreenCompatibility(osVersion: OSVersion(major: 26, minor: 3, patch: 1)).isSupported)
        #expect(!LockScreenCompatibility(osVersion: OSVersion(major: 15, minor: 5, patch: 0)).isSupported)
        #expect(!LockScreenCompatibility(osVersion: OSVersion(major: 27, minor: 0, patch: 0)).isSupported)
    }

    @Test func futureOSExplainsWhyItIsDisabled() {
        let c = LockScreenCompatibility(osVersion: OSVersion(major: 27, minor: 0, patch: 0))
        let reason = try! #require(c.explanation)
        #expect(reason.contains("27"))
        #expect(reason.lowercased().contains("desktop wallpapers are unaffected"))
    }

    @Test func thisMachineIsTahoe() {
        // Documents the environment the store findings were made on.
        #expect(OSVersion.current.major == 26)
        #expect(LockScreenCompatibility.current.isSupported)
    }

    // MARK: Manifest parsing

    private func manifestJSON(mediaKey: String = "url-4K-SDR-240FPS", extraAsset: String = "") -> Data {
        Data("""
        {"version":1,"localizationVersion":"22L-1","initialAssetCount":2,
         "categories":[{"id":"C1","localizedNameKey":"Landscapes"}],
         "assets":[
           {"id":"A-1","accessibilityLabel":"Tahoe Day","shotID":"TA_L_002",
            "previewImage":"https://example.invalid/a.png","\(mediaKey)":"https://example.invalid/a.mov"},
           {"id":"A-2","accessibilityLabel":"Sequoia","shotID":"A007",
            "\(mediaKey)":"https://example.invalid/b.mov"}\(extraAsset)
         ]}
        """.utf8)
    }

    @Test func parsesTheApplePublishedShape() throws {
        let m = try AerialManifestParser.parse(manifestJSON())
        #expect(m.version == 1)
        #expect(m.assets.count == 2)
        #expect(m.mediaKey == "url-4K-SDR-240FPS")
        #expect(m.assets[0].name == "Tahoe Day")
        #expect(!m.assets[0].isLocalMedia)
    }

    @Test func mediaKeyIsDiscoveredNotHardCoded() throws {
        // A future macOS could rename the key; parsing must still work.
        let m = try AerialManifestParser.parse(manifestJSON(mediaKey: "url-8K-HDR-120FPS"))
        #expect(m.mediaKey == "url-8K-HDR-120FPS")
        #expect(m.assets.count == 2)
    }

    @Test func rejectsMalformedManifests() {
        #expect(throws: LiveCanvasError.self) { try AerialManifestParser.parse(Data("not json".utf8)) }
        #expect(throws: LiveCanvasError.self) { try AerialManifestParser.parse(Data(#"{"assets":[]}"#.utf8)) }
        #expect(throws: LiveCanvasError.self) { try AerialManifestParser.parse(Data(#"{"version":1,"assets":[]}"#.utf8)) }
        // Assets with no url-* key at all.
        #expect(throws: LiveCanvasError.self) {
            try AerialManifestParser.parse(Data(#"{"version":1,"assets":[{"id":"X"}]}"#.utf8))
        }
        // An asset missing its id.
        #expect(throws: LiveCanvasError.self) {
            try AerialManifestParser.parse(Data(#"{"version":1,"assets":[{"url-x":"y"}]}"#.utf8))
        }
    }

    @Test func reEncodePreservesUnknownTopLevelKeys() throws {
        let m = try AerialManifestParser.parse(manifestJSON())
        let data = try AerialManifestParser.encode(m, assets: m.assets)
        let round = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(round["localizationVersion"] as? String == "22L-1")
        #expect(round["initialAssetCount"] as? Int == 2)
        #expect((round["categories"] as? [[String: Any]])?.count == 1)
        #expect((round["assets"] as? [[String: Any]])?.count == 2)
    }

    @Test func reEncodeDoesNotEscapeSlashesInFileURLs() throws {
        let m = try AerialManifestParser.parse(manifestJSON())
        let asset = AerialAssetFactory.makeAsset(
            id: "NEW", name: "Ocean", mediaKey: m.mediaKey,
            videoURL: URL(fileURLWithPath: "/tmp/x/NEW.mov"),
            thumbnailURL: URL(fileURLWithPath: "/tmp/x/NEW.png"))
        let data = try AerialManifestParser.encode(m, assets: m.assets + [asset])
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("file:///tmp/x/NEW.mov"))
        #expect(!text.contains("\\/"))
    }

    // MARK: Asset factory

    @Test func factoryProducesTheDiscoveredMediaKeyAndIsIdentifiable() {
        let asset = AerialAssetFactory.makeAsset(
            id: "11111111-2222-3333-4444-555555555555", name: "Ocean", mediaKey: "url-4K-SDR-240FPS",
            videoURL: URL(fileURLWithPath: "/tmp/v.mov"), thumbnailURL: URL(fileURLWithPath: "/tmp/t.png"))
        #expect(asset.raw["url-4K-SDR-240FPS"] != nil)
        #expect(asset.isLocalMedia)
        #expect(AerialAssetFactory.isLiveCanvasAsset(asset))
        #expect(asset.raw["includeInShuffle"] as? Bool == false)
        #expect(asset.raw["localizedNameKey"] as? String == "Ocean")
    }

    // MARK: Tar reader

    @Test func tarReaderExtractsAKnownFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tar-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let payload = Data(#"{"version":1,"assets":[{"id":"Z","url-a":"b"}]}"#.utf8)
        try payload.write(to: dir.appendingPathComponent("entries.json"))
        try Data(repeating: 0x41, count: 3000).write(to: dir.appendingPathComponent("other.bin"))

        let tar = dir.appendingPathComponent("m.tar")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        p.arguments = ["-cf", tar.path, "-C", dir.path, "other.bin", "entries.json"]
        try p.run(); p.waitUntilExit()
        #expect(p.terminationStatus == 0)

        let extracted = try TarReader.extractFile(named: "entries.json", from: tar)
        #expect(extracted == payload)
        #expect(throws: LiveCanvasError.self) { try TarReader.extractFile(named: "missing.json", from: tar) }
    }

    // MARK: The real store on this machine (read-only)

    @Test func realStoreInspectionIsReadOnlyAndConsistent() throws {
        let locator = AerialStoreLocator.userDefault
        try #require(FileManager.default.fileExists(atPath: locator.entriesFile.path),
                     "No Aerial store on this machine; skipping.")

        let before = try FileUtilities.sha256(of: locator.entriesFile)
        let report = AerialStoreValidator(locator: locator).inspect()
        let after = try FileUtilities.sha256(of: locator.entriesFile)

        #expect(before == after, "inspect() must never modify entries.json")
        #expect(report.isUsable)
        #expect(report.assetCount > 0)
        #expect(report.mediaKey?.hasPrefix("url-") == true)
        #expect(report.isWritable)
        // Every asset reported as downloaded really has a file on disk.
        for id in report.downloadedAssetIDs {
            #expect(FileManager.default.fileExists(atPath: locator.videoURL(for: id).path))
        }
    }

    @Test func pristineManifestTarParsesAndIsASupersetBaseline() throws {
        let validator = AerialStoreValidator()
        try #require(FileManager.default.fileExists(atPath: validator.locator.manifestTar.path),
                     "No manifest.tar on this machine; skipping.")
        let pristine = try validator.pristineAssetIDs()
        #expect(pristine.count > 100)
        let live = try validator.loadManifest()
        // Apple's own assets must all still be present in the live manifest.
        let liveIDs = Set(live.assets.map(\.id))
        #expect(pristine.subtracting(liveIDs).isEmpty, "Live manifest is missing Apple assets")
    }
}

struct MediaAuditTests {
    @Test func resolutionClassIsParsedFromTheMediaKey() {
        #expect(AerialMediaAudit.declaredLongEdge(fromMediaKey: "url-4K-SDR-240FPS") == 3840)
        #expect(AerialMediaAudit.declaredLongEdge(fromMediaKey: "url-8K-HDR-120FPS") == 7680)
        #expect(AerialMediaAudit.declaredLongEdge(fromMediaKey: "url-1080-SDR-60FPS") == 1920)
        #expect(AerialMediaAudit.declaredLongEdge(fromMediaKey: "url-720-SDR") == 1280)
        #expect(AerialMediaAudit.declaredLongEdge(fromMediaKey: "url-something-new") == nil)
    }

    @Test func twelveKIsNotMatchedByTheTwoKToken() {
        // Ordering matters: a naive scan would match "2K" inside "12K".
        #expect(AerialMediaAudit.declaredLongEdge(fromMediaKey: "url-12K-SDR") == 12288)
        #expect(AerialMediaAudit.declaredLongEdge(fromMediaKey: "url-16K-SDR") == 15360)
    }

    @Test func auditFlagsAnOversizeFileForAFourKAsset() async throws {
        let store = try SyntheticAerialStore(); defer { store.tearDown() }
        // Replace the "4K" Apple asset's file with an obviously larger video, the way an
        // in-place overwrite by another tool would.
        let big = try await SyntheticAerialStore.makeVideo(width: 5120, height: 2880, frames: 4)
        defer { try? FileManager.default.removeItem(at: big) }
        let target = store.locator.videoURL(for: SyntheticAerialStore.appleAssetID)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: big, to: target)

        let validator = AerialStoreValidator(locator: store.locator)
        let manifest = try validator.loadManifest()
        let pristine = try validator.pristineAssetIDs()
        let findings = await AerialMediaAudit(locator: store.locator)
            .auditAppleAssets(manifest: manifest, pristineIDs: pristine)

        #expect(findings.count == 1)
        #expect(findings[0].assetID == SyntheticAerialStore.appleAssetID)
        #expect(findings[0].reason == .resolutionExceedsDeclaredClass)
        #expect(findings[0].actual.contains("5120"))
    }

    @Test func auditStaysSilentForAConformingFile() async throws {
        let store = try SyntheticAerialStore(); defer { store.tearDown() }
        let ok = try await SyntheticAerialStore.makeVideo(width: 1920, height: 1080, frames: 4)
        defer { try? FileManager.default.removeItem(at: ok) }
        let target = store.locator.videoURL(for: SyntheticAerialStore.appleAssetID)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: ok, to: target)

        let validator = AerialStoreValidator(locator: store.locator)
        let findings = await AerialMediaAudit(locator: store.locator)
            .auditAppleAssets(manifest: try validator.loadManifest(), pristineIDs: try validator.pristineAssetIDs())
        #expect(findings.isEmpty)
    }

    @Test func pluralisationReadsNaturally() {
        #expect(Pluralize.count(1, "wallpaper entry", "wallpaper entries") == "1 wallpaper entry")
        #expect(Pluralize.count(3, "wallpaper entry", "wallpaper entries") == "3 wallpaper entries")
        #expect(Pluralize.count(1, "video") == "1 video")
        #expect(Pluralize.count(0, "video") == "0 videos")
    }
}

struct WarningGrammarTests {
    @Test func singularAndPluralWarningsAgree() async throws {
        // Regression: "1 wallpaper entry … were added" read wrong.
        let store = try SyntheticAerialStore(); defer { store.tearDown() }
        let box = FileManager.default.temporaryDirectory.appendingPathComponent("lc-gram-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: box, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: box) }

        func statusMessage(foreignCount: Int) async throws -> String {
            let manifest = try AerialManifestParser.parse(try Data(contentsOf: store.locator.entriesFile))
            var assets = manifest.assets.filter { !$0.id.hasPrefix("FOREIGN") }
            for i in 0..<foreignCount {
                assets.append(AerialAsset(
                    raw: ["id": "FOREIGN-\(i)", "accessibilityLabel": "X", "shotID": "CUSTOM",
                          SyntheticAerialStore.mediaKey: "file:///tmp/x.mov"],
                    id: "FOREIGN-\(i)", name: "X", mediaURLString: "file:///tmp/x.mov",
                    previewImageString: nil, shotID: "CUSTOM"))
            }
            try AerialManifestParser.encode(manifest, assets: assets).write(to: store.locator.entriesFile)
            let installer = TahoeAerialInstaller(
                locator: store.locator,
                backups: BackupManager(rootDirectory: box.appendingPathComponent("B")),
                compatibility: LockScreenCompatibility(osVersion: OSVersion(major: 26, minor: 0, patch: 0)),
                recordURL: box.appendingPathComponent("r.json"))
            return await installer.status().message ?? ""
        }

        let one = try await statusMessage(foreignCount: 1)
        #expect(one.contains("1 wallpaper entry"))
        #expect(one.contains("was added"))
        #expect(!one.contains("were added"))

        let many = try await statusMessage(foreignCount: 3)
        #expect(many.contains("3 wallpaper entries"))
        #expect(many.contains("were added"))
    }
}
