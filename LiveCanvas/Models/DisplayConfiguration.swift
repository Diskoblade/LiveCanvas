import Foundation

/// A snapshot of one connected display, expressed in the terms the engine needs.
/// `id` is stable across reconnects where macOS allows (CoreGraphics display UUID).
struct DisplayConfiguration: Identifiable, Hashable, Sendable {
    let id: String
    let directDisplayID: UInt32
    let name: String
    let frame: CGRect            // logical points, global coordinate space
    let visibleFrame: CGRect
    let backingScaleFactor: CGFloat
    let isBuiltIn: Bool
    let isMain: Bool

    var pointSize: CGSize { frame.size }
    var pixelSize: CGSize { CGSize(width: frame.width * backingScaleFactor, height: frame.height * backingScaleFactor) }
    var aspectRatio: Double { frame.height > 0 ? Double(frame.width / frame.height) : 16.0 / 9.0 }
    var isPortrait: Bool { frame.height > frame.width }

    var pixelResolutionLabel: String { "\(Int(pixelSize.width)) × \(Int(pixelSize.height))" }
    var pointResolutionLabel: String { "\(Int(frame.width)) × \(Int(frame.height)) points" }
    var scaleLabel: String { String(format: backingScaleFactor.rounded() == backingScaleFactor ? "%.0fx" : "%.2fx", backingScaleFactor) }
}
