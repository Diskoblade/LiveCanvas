import AVFoundation

/// Gapless looping player for one wallpaper. Wraps AVQueuePlayer + AVPlayerLooper.
/// Decoding is hardware accelerated by AVFoundation; nothing here touches frames.
@MainActor
final class WallpaperPlayer {
    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private(set) var currentURL: URL?
    private(set) var isPaused = false

    /// Whether a looper is currently installed. Used by tests to prove tear-down releases it.
    var hasLooper: Bool { looper != nil }

    init() {
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.automaticallyWaitsToMinimizeStalling = false
        player.allowsExternalPlayback = false
        player.actionAtItemEnd = .advance
    }

    func load(url: URL) {
        guard url != currentURL else { return }
        tearDownLooper()
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: player, templateItem: item)
        currentURL = url
        Log.playback.info("Loaded \(url.lastPathComponent, privacy: .public)")
        if !isPaused { player.play() }
    }

    var isMuted: Bool {
        get { player.isMuted }
        set { player.isMuted = newValue }
    }

    func play() {
        isPaused = false
        if currentURL != nil { player.play() }
    }

    func pause() {
        isPaused = true
        player.pause()
    }

    func tearDown() {
        tearDownLooper()
        currentURL = nil
    }

    private func tearDownLooper() {
        player.pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
    }
}
