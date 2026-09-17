import CoreGraphics
import AVFoundation

/// Pure layout math for fit modes so it can be unit-tested without windows.
enum FitLayout {
    struct Result: Equatable {
        var gravity: AVLayerVideoGravity
        var frame: CGRect
    }

    /// - Parameters:
    ///   - bounds: view bounds in points
    ///   - videoPixelSize: natural size of the video in pixels (after orientation)
    ///   - scale: backing scale factor of the screen the view is on
    static func layout(mode: FitMode, bounds: CGRect, videoPixelSize: CGSize, scale: CGFloat) -> Result {
        switch mode {
        case .fill:
            return Result(gravity: .resizeAspectFill, frame: bounds)
        case .fit:
            return Result(gravity: .resizeAspect, frame: bounds)
        case .stretch:
            return Result(gravity: .resize, frame: bounds)
        case .original:
            // One video pixel → one device pixel; expressed in points for the layer.
            let s = max(scale, 1)
            let natural = CGSize(width: videoPixelSize.width / s, height: videoPixelSize.height / s)
            guard natural.width > 0, natural.height > 0,
                  natural.width <= bounds.width, natural.height <= bounds.height else {
                // Larger than the screen: fall back to Fit rather than cropping silently.
                return Result(gravity: .resizeAspect, frame: bounds)
            }
            let frame = CGRect(
                x: bounds.minX + ((bounds.width - natural.width) / 2).rounded(),
                y: bounds.minY + ((bounds.height - natural.height) / 2).rounded(),
                width: natural.width, height: natural.height)
            return Result(gravity: .resize, frame: frame)
        }
    }

    /// The rectangle (in points) the video content actually occupies for a given result.
    /// Useful for previews and tests; mirrors AVPlayerLayer.videoRect semantics.
    static func contentRect(for result: Result, videoPixelSize: CGSize) -> CGRect {
        let f = result.frame
        guard videoPixelSize.width > 0, videoPixelSize.height > 0, f.width > 0, f.height > 0 else { return f }
        let va = videoPixelSize.width / videoPixelSize.height
        let fa = f.width / f.height
        switch result.gravity {
        case .resize:
            return f
        case .resizeAspect:
            if va > fa { let h = f.width / va; return CGRect(x: f.minX, y: f.midY - h / 2, width: f.width, height: h) }
            else { let w = f.height * va; return CGRect(x: f.midX - w / 2, y: f.minY, width: w, height: f.height) }
        case .resizeAspectFill:
            if va > fa { let w = f.height * va; return CGRect(x: f.midX - w / 2, y: f.minY, width: w, height: f.height) }
            else { let h = f.width / va; return CGRect(x: f.minX, y: f.midY - h / 2, width: f.width, height: h) }
        default:
            return f
        }
    }
}
