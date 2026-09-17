import SwiftUI
import AppKit
import Observation

/// Bounded in-memory poster cache. Decoding happens off the main thread.
@MainActor
final class ThumbnailLoader {
    static let shared = ThumbnailLoader()

    private let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 300
        c.totalCostLimit = 200 * 1024 * 1024
        return c
    }()

    func cached(_ url: URL) -> NSImage? {
        cache.object(forKey: url.path as NSString)
    }

    func load(_ url: URL) async -> NSImage? {
        if let hit = cached(url) { return hit }
        let image: NSImage? = await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url), let img = NSImage(data: data) else { return nil }
            return img
        }.value
        if let image {
            let cost = Int(image.size.width * image.size.height * 4)
            cache.setObject(image, forKey: url.path as NSString, cost: cost)
        }
        return image
    }

    func evict(_ url: URL) {
        cache.removeObject(forKey: url.path as NSString)
    }
}

/// Async poster image with a placeholder. `mode` mirrors the wallpaper fit modes so a
/// display card can show what the real wallpaper will look like.
struct PosterImage: View {
    enum Mode { case fill, fit, stretch }

    let url: URL?
    var mode: Mode = .fill
    var naturalAspect: Double?

    @State private var image: NSImage?

    init(url: URL?, contentMode: Mode = .fill, naturalAspect: Double? = nil) {
        self.url = url
        self.mode = contentMode
        self.naturalAspect = naturalAspect
    }

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                // Color.clear keeps the image from driving the container's size; the
                // overlay then fills, fits or stretches inside whatever space we were given.
                Color.clear.overlay {
                    switch mode {
                    case .fill:
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    case .fit:
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    case .stretch:
                        Image(nsImage: image).resizable()
                    }
                }
                .clipped()
            } else {
                Image(systemName: "film")
                    .font(.title)
                    .foregroundStyle(.tertiary)
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            if let hit = ThumbnailLoader.shared.cached(url) { image = hit; return }
            image = await ThumbnailLoader.shared.load(url)
        }
    }
}
