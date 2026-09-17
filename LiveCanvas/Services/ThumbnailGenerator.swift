import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Produces poster frames with AVAssetImageGenerator (hardware decode, no per-frame work).
struct ThumbnailGenerator: Sendable {
    var maximumSize = CGSize(width: 800, height: 800)

    /// Writes a JPEG poster for `videoURL` to `destination`. Picks a frame ~10% in
    /// (min 0.5s, max 3s) to avoid black lead-in frames.
    func generatePoster(for videoURL: URL, duration: TimeInterval, to destination: URL) async throws {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maximumSize
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

        let offset = min(max(duration * 0.1, 0.5), 3.0)
        let time = CMTime(seconds: min(offset, max(duration - 0.1, 0)), preferredTimescale: 600)

        let cgImage: CGImage
        do {
            (cgImage, _) = try await generator.image(at: time)
        } catch {
            // Retry at time zero for very short or oddly keyed files.
            do {
                (cgImage, _) = try await generator.image(at: .zero)
            } catch {
                throw LiveCanvasError.thumbnailFailed(error.localizedDescription)
            }
        }

        guard let dest = CGImageDestinationCreateWithURL(destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw LiveCanvasError.thumbnailFailed("Could not create image destination.")
        }
        CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw LiveCanvasError.thumbnailFailed("Could not write thumbnail file.")
        }
    }
}
