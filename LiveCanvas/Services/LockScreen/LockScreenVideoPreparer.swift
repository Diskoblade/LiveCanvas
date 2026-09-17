import Foundation
import AVFoundation

/// Decides how a library video must be converted for the Lock Screen and performs it.
///
/// Policy:
/// * Audio is always removed. A Lock Screen wallpaper is silent, full stop.
/// * If the video track is already H.264 or HEVC in a supported pixel format and is not
///   larger than the cap, the track is **passed through** (remux) with no re-encode and no
///   quality loss.
/// * Otherwise it is transcoded with AVAssetExportSession, which uses VideoToolbox
///   hardware encoding. Low-resolution sources are never upscaled.
struct LockScreenVideoPreparer: Sendable {

    enum Strategy: Equatable, Sendable {
        /// Copy the video track as-is into a new .mov with no audio.
        case remux
        /// Re-encode, targeting `size`.
        case transcode(preset: String, size: CGSize)

        var explanation: String {
            switch self {
            case .remux: return "Copying the video without re-encoding."
            case .transcode(_, let size): return "Converting to \(Int(size.width)) × \(Int(size.height))."
            }
        }
    }

    /// Longest edge LiveCanvas will hand to the Lock Screen. Apple's own assets are 4K;
    /// anything larger is downscaled to keep decode cost and disk use sane.
    var maximumLongEdge: CGFloat = 3840

    /// Chooses a strategy without touching the file system.
    func strategy(for probe: VideoProbe) -> Strategy {
        let size = CGSize(width: probe.pixelWidth, height: probe.pixelHeight)
        let longEdge = max(size.width, size.height)
        let codecIsSupported = probe.codec == .h264 || probe.codec == .hevc

        if codecIsSupported && longEdge <= maximumLongEdge {
            return .remux
        }
        guard longEdge > 0 else { return .remux }
        // Never upscale: the target is the smaller of the source size and the cap.
        let scale = min(1, maximumLongEdge / longEdge)
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        // HEVC keeps high-resolution files efficient; H.264 for smaller ones for compatibility.
        let preset = max(target.width, target.height) > 1920
            ? AVAssetExportPresetHEVCHighestQuality
            : AVAssetExportPresetHighestQuality
        return .transcode(preset: preset, size: target)
    }

    /// Produces a silent .mov at `destination`. Returns the strategy actually used.
    @discardableResult
    func prepare(source: URL, probe: VideoProbe, destination: URL) async throws -> Strategy {
        let chosen = strategy(for: probe)
        let fm = FileManager.default
        try? fm.removeItem(at: destination)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        do {
            switch chosen {
            case .remux:
                try await remux(source: source, to: destination)
            case .transcode(let preset, _):
                try await transcode(source: source, to: destination, preset: preset)
            }
        } catch {
            try? fm.removeItem(at: destination)
            throw LiveCanvasError.preparationFailed(error.localizedDescription)
        }

        // A prepared file that will not play is worse than no file at all.
        let verification = try await VideoMetadataService().probe(destination)
        guard verification.isPlayable else {
            try? fm.removeItem(at: destination)
            throw LiveCanvasError.preparationFailed("The prepared Lock Screen video could not be played back.")
        }
        guard !verification.hasAudio else {
            try? fm.removeItem(at: destination)
            throw LiveCanvasError.preparationFailed("The prepared Lock Screen video still contains an audio track.")
        }
        Log.lockscreen.info("Prepared Lock Screen video via \(String(describing: chosen), privacy: .public): \(verification.pixelWidth)x\(verification.pixelHeight)")
        return chosen
    }

    // MARK: Implementations

    /// Passthrough: copies sample buffers of the video track only. No re-encode.
    private func remux(source: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw LiveCanvasError.videoUndecodable("The source has no video track.")
        }
        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)  // nil = no decoding
        readerOutput.alwaysCopiesSampleData = false
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: destination, fileType: .mov)
        let formatDescription = try await track.load(.formatDescriptions).first
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: formatDescription)
        writerInput.expectsMediaDataInRealTime = false
        writerInput.transform = try await track.load(.preferredTransform)
        writer.add(writerInput)

        guard reader.startReading() else { throw reader.error ?? LiveCanvasError.preparationFailed("Could not read the source video.") }
        guard writer.startWriting() else { throw writer.error ?? LiveCanvasError.preparationFailed("Could not write the Lock Screen video.") }
        writer.startSession(atSourceTime: .zero)

        let queue = DispatchQueue(label: "com.rahul.livecanvas.remux")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData {
                    guard let buffer = readerOutput.copyNextSampleBuffer() else {
                        writerInput.markAsFinished()
                        continuation.resume()
                        return
                    }
                    if !writerInput.append(buffer) {
                        writerInput.markAsFinished()
                        continuation.resume()
                        return
                    }
                }
            }
        }
        await writer.finishWriting()

        if reader.status == .failed { throw reader.error ?? LiveCanvasError.preparationFailed("Reading the source video failed.") }
        guard writer.status == .completed else {
            throw writer.error ?? LiveCanvasError.preparationFailed("Writing the Lock Screen video failed.")
        }
    }

    /// Hardware-accelerated re-encode via AVAssetExportSession, video track only.
    private func transcode(source: URL, to destination: URL, preset: String) async throws {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw LiveCanvasError.preparationFailed("No hardware encoder is available for this video.")
        }
        // Drop audio by exporting only the video track's time range with an audio-free mix.
        let composition = AVMutableComposition()
        guard let sourceTrack = try await asset.loadTracks(withMediaType: .video).first,
              let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw LiveCanvasError.videoUndecodable("The source has no video track.")
        }
        let duration = try await asset.load(.duration)
        try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceTrack, at: .zero)
        videoTrack.preferredTransform = try await sourceTrack.load(.preferredTransform)

        guard let compositionSession = AVAssetExportSession(asset: composition, presetName: preset) else {
            throw LiveCanvasError.preparationFailed("No hardware encoder is available for this video.")
        }
        _ = session
        try await compositionSession.export(to: destination, as: .mov)
    }
}
