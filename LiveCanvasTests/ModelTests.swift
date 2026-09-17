import Testing
import Foundation
@testable import LiveCanvas

struct ModelTests {
    private func sample(w: Int, h: Int) -> WallpaperAsset {
        WallpaperAsset(id: UUID(), displayName: "x", sourceURL: nil, managedFileName: "x.mov", thumbnailFileName: nil,
                       kind: .video, duration: 12.4, pixelWidth: w, pixelHeight: h, frameRate: 30, codec: .hevc,
                       codecFourCC: "hvc1", dynamicRange: .sdr, hasAudio: false, fileSize: 1_048_576, dateImported: Date())
    }

    @Test func qualityLabels() {
        #expect(sample(w: 1280, h: 720).qualityLabel == "720p")
        #expect(sample(w: 1920, h: 1080).qualityLabel == "1080p")
        #expect(sample(w: 2560, h: 1440).qualityLabel == "1440p")
        #expect(sample(w: 3840, h: 2160).qualityLabel == "4K")
        #expect(sample(w: 5120, h: 2880).qualityLabel == "5K")
        #expect(sample(w: 6016, h: 3384).qualityLabel == "6K")
        #expect(sample(w: 7680, h: 4320).qualityLabel == "8K")
        #expect(sample(w: 1080, h: 1920).qualityLabel == "1080p")   // portrait uses longer edge
    }

    @Test func aspectAndPortrait() {
        #expect(sample(w: 1080, h: 1920).isPortrait)
        #expect(abs(sample(w: 3440, h: 1440).aspectRatio - 2.388) < 0.01)
    }

    @Test func durationFormatting() {
        #expect(FileUtilities.formattedDuration(5) == "5.0s")
        #expect(FileUtilities.formattedDuration(65) == "1:05")
        #expect(FileUtilities.formattedDuration(3661) == "1:01:01")
        #expect(FileUtilities.formattedDuration(.nan) == "–")
    }

    @Test func assetRoundTripsThroughJSON() throws {
        let a = sample(w: 3840, h: 2160)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let data = try enc.encode(LibraryDocument(assets: [a]))
        let back = try dec.decode(LibraryDocument.self, from: data)
        #expect(back.assets.count == 1)
        #expect(back.assets[0].id == a.id)
        #expect(back.assets[0].codec == .hevc)
    }

    @Test func settingsDecodeTolerantOfMissingKeys() throws {
        let json = #"{"version":1,"playback":{"allowAudio":true}}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(AppSettings.self, from: json)
        #expect(s.playback.allowAudio)
        #expect(s.playback.defaultFitMode == .fill)
        #expect(s.desktop.useSameOnAllDisplays)
        #expect(s.lockScreen.enabled == false)
    }

    @Test func desktopAssignmentsResolveAndRemove() {
        var d = DesktopAssignments()
        let a = UUID(), b = UUID()
        d.global = WallpaperAssignment(assetID: a, fitMode: nil)
        d.perDisplay["D1"] = WallpaperAssignment(assetID: b, fitMode: .fit)
        #expect(d.assignment(for: "D1")?.assetID == a)         // same-on-all wins
        d.useSameOnAllDisplays = false
        #expect(d.assignment(for: "D1")?.assetID == b)
        #expect(d.assignment(for: "D2")?.assetID == a)         // falls back to global
        #expect(d.references(b))
        d.remove(assetID: b)
        #expect(!d.references(b))
        #expect(d.perDisplay.isEmpty)
    }
}
