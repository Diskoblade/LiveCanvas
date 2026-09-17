import AppKit
import AVFoundation

/// Layer-backed view that lays out an AVPlayerLayer according to a FitMode.
/// Fill/Fit/Stretch map to AVLayerVideoGravity over the full bounds; Original sizes the
/// layer to the video's natural pixel size at 1:1 device pixels, centred, falling back to
/// Fit when the video is larger than the screen.
final class WallpaperPlayerView: NSView {
    let playerLayer = AVPlayerLayer()
    var fitMode: FitMode = .fill { didSet { needsLayout = true } }
    var videoPixelSize: CGSize = .zero { didSet { needsLayout = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isOpaque: Bool { true }

    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.contentsScale = scale

        let result = FitLayout.layout(mode: fitMode, bounds: bounds, videoPixelSize: videoPixelSize, scale: scale)
        playerLayer.videoGravity = result.gravity
        playerLayer.frame = result.frame
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }
}
