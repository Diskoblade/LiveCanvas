import SwiftUI
import AppKit
import AVFoundation

/// Layer-backed NSView hosting an AVPlayerLayer. Shared by previews and wallpaper windows.
final class PlayerLayerHostView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        playerLayer.contentsScale = window?.backingScaleFactor ?? 2
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }
}

/// SwiftUI wrapper for PlayerLayerHostView.
struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspect

    func makeNSView(context: Context) -> PlayerLayerHostView {
        let view = PlayerLayerHostView(frame: .zero)
        view.playerLayer.player = player
        view.playerLayer.videoGravity = gravity
        return view
    }

    func updateNSView(_ nsView: PlayerLayerHostView, context: Context) {
        if nsView.playerLayer.player !== player { nsView.playerLayer.player = player }
        if nsView.playerLayer.videoGravity != gravity { nsView.playerLayer.videoGravity = gravity }
    }

    static func dismantleNSView(_ nsView: PlayerLayerHostView, coordinator: ()) {
        nsView.playerLayer.player = nil
    }
}
