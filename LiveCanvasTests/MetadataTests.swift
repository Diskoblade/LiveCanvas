import Testing
import Foundation
import AVFoundation
@testable import LiveCanvas

/// Generates a tiny real H.264 file with AVAssetWriter so the probe and thumbnail
/// pipeline are exercised end-to-end without shipping fixtures.
enum TestMedia {
    static func makeVideo(width: Int, height: Int, frames: Int = 12, fps: Int32 = 24) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lc-test-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? LiveCanvasError.importFailed("startWriting") }
        writer.startSession(atSourceTime: .zero)
        for i in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
            guard let buffer = pb else { throw LiveCanvasError.importFailed("pixel buffer") }
            CVPixelBufferLockBaseAddress(buffer, [])
            let base = CVPixelBufferGetBaseAddress(buffer)!
            memset(base, Int32(40 + i * 10), CVPixelBufferGetBytesPerRow(buffer) * height)
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? LiveCanvasError.importFailed("finishWriting") }
        return url
    }
}

struct MetadataTests {
    @Test func probeReadsDimensionsCodecAndDuration() async throws {
        let url = try await TestMedia.makeVideo(width: 320, height: 180, frames: 24, fps: 24)
        defer { try? FileManager.default.removeItem(at: url) }
        let probe = try await VideoMetadataService().probe(url)
        #expect(probe.pixelWidth == 320)
        #expect(probe.pixelHeight == 180)
        #expect(probe.codec == .h264)
        #expect(probe.codecFourCC == "avc1")
        #expect(abs(probe.duration - 1.0) < 0.05)
        #expect(probe.hasAudio == false)
        #expect(probe.isPlayable)
    }

    @Test func thumbnailIsWritten() async throws {
        let url = try await TestMedia.makeVideo(width: 160, height: 90)
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("lc-thumb-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: out) }
        try await ThumbnailGenerator().generatePoster(for: url, duration: 0.5, to: out)
        #expect(FileManager.default.fileExists(atPath: out.path))
        #expect(FileUtilities.fileSize(of: out) > 100)
    }

    @Test @MainActor func importIntoTemporaryLibrary() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lc-lib-\(UUID().uuidString)")
        let media = dir.appendingPathComponent("Media"), thumbs = dir.appendingPathComponent("Thumbnails")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try await TestMedia.makeVideo(width: 256, height: 144)
        defer { try? FileManager.default.removeItem(at: source) }

        let manager = VideoAssetManager(store: LibraryStore(fileURL: dir.appendingPathComponent("library.json")),
                                        mediaDirectory: media, thumbnailDirectory: thumbs)
        let asset = await manager.importFile(source)
        #expect(asset != nil)
        #expect(manager.assets.count == 1)
        #expect(manager.assets[0].thumbnailFileName != nil)
        #expect(FileManager.default.fileExists(atPath: manager.mediaURL(for: manager.assets[0]).path))

        let bogus = dir.appendingPathComponent("notes.txt")
        try Data("hi".utf8).write(to: bogus)
        let rejected = await manager.importFile(bogus)
        #expect(rejected == nil)
        #expect(manager.lastError != nil)

        manager.delete(manager.assets[0])
        #expect(manager.assets.isEmpty)
    }
}
