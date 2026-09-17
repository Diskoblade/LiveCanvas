import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Converts a library poster (JPEG) into the PNG the Aerial store expects.
enum PosterConverter {
    static func writePNG(from source: URL, to destination: URL) throws {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw LiveCanvasError.thumbnailFailed("Could not read the poster image.")
        }
        guard let dest = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw LiveCanvasError.thumbnailFailed("Could not create the poster file.")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw LiveCanvasError.thumbnailFailed("Could not write the poster file.")
        }
    }
}
