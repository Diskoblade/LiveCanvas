import Foundation
import AVFoundation
import Observation

/// One shared, muted, looping player used for hover previews and the detail sheet.
/// Only a single AVPlayer (and AVPlayerLayer) exists for previews at any time.
@MainActor
@Observable
final class PreviewPlayer {
    let player = AVQueuePlayer()
    private(set) var currentAssetID: UUID?
    private var looper: AVPlayerLooper?

    init() {
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.automaticallyWaitsToMinimizeStalling = false
    }

    func play(asset: WallpaperAsset, url: URL) {
        if currentAssetID == asset.id {
            player.play()
            return
        }
        stop()
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: player, templateItem: item)
        currentAssetID = asset.id
        player.play()
    }

    func pause() {
        player.pause()
    }

    func stop(if assetID: UUID? = nil) {
        if let assetID, assetID != currentAssetID { return }
        player.pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        currentAssetID = nil
    }
}
