# LiveCanvas — Architecture

LiveCanvas is a native macOS application (Swift 6.2 toolchain, Swift 5 language mode,
SwiftUI + AppKit + AVFoundation) that plays a user's own video as a live Desktop
wallpaper and, on macOS 26 Tahoe, as the animated Lock Screen wallpaper of the
logged-in user session.

Working name: **LiveCanvas**. The product name lives in one place
(`Config/Shared.xcconfig` → `LC_PRODUCT_NAME`); code reads it from the bundle via
`AppInfo`. Bundle identifier prefix is likewise a single xcconfig variable.

## Development environment (detected 2026-09-12)

| Item | Value |
|---|---|
| macOS | 26.3 (25D5101c) |
| Xcode | 26.3 (17C529), macOS 26.2 SDK |
| Swift | 6.2.4 |
| Hardware | Apple M4, built-in 3024×1964 Retina + 5120×2880 external (2560×1440 @2x) |
| Displays used for testing | 2560×1440@2x external, 1800×1169@2x built-in |
| Signing | no Developer ID identity on this machine → ad-hoc signing for now |

## Layering

```
UI (SwiftUI, AppKit hosting)        MainWindow · Library · Displays · LockScreen · Playlists · Settings · Components
        │  observes
App     AppState (@Observable, @MainActor) · AppDelegate · LiveCanvasApp
        │  owns
Services
   Library      VideoAssetManager · VideoMetadataService · ThumbnailGenerator · VideoTranscoder (M7)
   Desktop      WallpaperEngine · DisplayManager · PlayerCoordinator
   System       PowerMonitor · ScreenLockMonitor · SleepWakeMonitor · FullScreenMonitor · LoginItemManager
   LockScreen   LockScreenWallpaperInstalling (protocol) · TahoeAerialInstaller · AerialManifestStore · BackupManager · LockScreenCompatibility
   Persistence  PreferencesStore · LibraryStore (JSON, Codable)
Playback        WallpaperWindow · WallpaperPlayer · WallpaperPlayerView · PreviewPlayer
Utilities       AppInfo · AppDirectories · AtomicFileWriter · FileUtilities · Log · OSVersion · LiveCanvasError
Models          WallpaperAsset · DisplayConfiguration · WallpaperAssignment · PlaybackSettings · LockScreenState · Playlist
```

Rules:

* Models are plain `Codable` value types. No AppKit/AVFoundation types in models.
* Services never touch SwiftUI. UI never touches the filesystem or AVFoundation directly.
* Everything that mutates macOS-owned files goes through `LockScreenWallpaperInstalling`
  and `BackupManager`. Nothing else in the app writes outside the app's own
  Application Support directory.
* No network code exists in the project. No telemetry, no analytics, no accounts.

## Concurrency model

* `AppState`, the engine, display manager, monitors and all AppKit window code are
  `@MainActor`.
* Media probing, thumbnail generation, hashing, copying and transcoding run off the
  main actor (`async` functions or dedicated actors) and report back to the main actor.
* Language mode is Swift 5 with the Swift 6.2 compiler so that AppKit/AVFoundation
  delegate and KVO code compiles without a wall of Sendable annotations. Types are still
  annotated with `@MainActor`/`Sendable` where the isolation is real, so a later switch
  to Swift 6 mode is incremental.

## Persistence

All state is local JSON under
`~/Library/Application Support/<ProductName>/`:

```
library.json            WallpaperAsset records
settings.json           PlaybackSettings, assignments, lock screen prefs, login item flag
Media/<uuid>.<ext>      managed copies of imported videos
Thumbnails/<uuid>.jpg   poster frames
LockScreen/             prepared (audio-stripped) lock screen copies
Backups/<timestamp>/    BackupManager snapshots + manifest.json
```

Writes go through `AtomicFileWriter` (write to a temp file in the same directory,
then `FileManager.replaceItemAt`).

## Desktop wallpaper engine

One `WallpaperWindow` (NSWindow subclass) per active `NSScreen`:

* `styleMask = .borderless`, `level = CGWindowLevelForKey(.desktopWindowLevel)` so the
  window sits above Finder's desktop picture and below the desktop icon layer.
* `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]`
* `ignoresMouseEvents = true`, `canBecomeKey/Main = false`, excluded from the Windows
  menu; the app itself is a regular app so the Dock icon belongs to the main window,
  not to the wallpaper windows (which are never listed in Cmd-Tab because they are not
  key-able, titled windows).
* Content is a layer-backed `NSView` hosting an `AVPlayerLayer` driven by
  `AVQueuePlayer` + `AVPlayerLooper` (gapless looping, hardware decode via VideoToolbox).
* Layout uses `screen.frame` in points; the layer's `contentsScale` follows
  `backingScaleFactor`. Fit modes map to `AVLayerVideoGravity` (Fill → aspectFill,
  Fit → aspect, Stretch → resize) and *Original* sizes the layer to the natural size in
  points, centred.
* `DisplayManager` listens to `NSApplication.didChangeScreenParametersNotification`
  and diffs screens by a stable identifier (display UUID from CoreGraphics, falling back
  to vendor/model/serial). Only windows for added/removed/resized screens are touched;
  unaffected players keep running.

## Lock Screen (macOS 26 Tahoe) — discovered format

Inspected read-only on this machine on 2026-09-12. **This is undocumented Apple
behaviour and may change in any macOS update.** See `docs/TAHOE_AERIAL_FORMAT.md`
for the full write-up.

```
~/Library/Application Support/com.apple.wallpaper/
  Store/Index.plist                    per-display + per-space wallpaper choices
  aerials/
    manifest.tar                       downloaded bundle (entries.json + strings bundle)
    manifest/manifest.source           CDN path of the manifest tar
    manifest/entries.json              {"version":1, "assets":[...156], "categories":[...]}
    manifest/TVIdleScreenStrings.bundle localized names
    videos/<assetID>.mov               downloaded Aerial videos (HEVC 4K SDR)
    thumbnails/<assetID>.png           214×130 PNG per asset
```

`Store/Index.plist` → `Displays[<displayUUID>].Idle.Content.Choices[0]` has
`Provider = com.apple.wallpaper.choice.aerials` and a binary-plist `Configuration`
blob decoding to `{"assetID": "<UUID>"}`. The Lock Screen ("Idle") plays
`aerials/videos/<assetID>.mov`.

Strategy (least destructive): LiveCanvas **appends its own asset entry** to
`entries.json` with `file://` media URLs, drops its own `<uuid>.mov` and `<uuid>.png`
alongside Apple's, and repoints the `Idle` choice at it.

Only two existing files are ever modified — `entries.json` and `Store/Index.plist` —
both SHA-256 backed up and verified first. **No Apple media file is ever overwritten.**
That matters: Apple's Aerial videos are 300–600 MB files that exist only on disk, and
overwriting one destroys it with no offline way back. (The store on this development
machine already has one such casualty from a different tool; see the format doc.)

Restore replaces both files from the verified backup, re-checks their hashes, and deletes
the files LiveCanvas added. Any validation failure refuses the operation outright.

Isolation: `protocol LockScreenWallpaperInstalling` + `TahoeAerialInstaller`.
`LockScreenCompatibility.current` gates the feature on major OS version and on the
validated store layout, so a future macOS is disabled by default with an explanation.

### What the Lock Screen integration can and cannot do

* **Can**: animate the normal Lock Screen of the logged-in user (screen lock, screen
  saver → lock, wake from sleep while logged in).
* **Cannot**: the FileVault / pre-login screen after a cold boot. That screen runs
  before the user session exists and reads system assets; LiveCanvas does not and will
  not try to touch it.

## Security posture

No SIP changes, no FileVault changes, no `loginwindow` edits, no code injection, no
root, no accessibility permission, no kernel/system extensions, no patching of
protected OS binaries. The only macOS-owned files the app writes are inside the
per-user Aerial store, and only after a verified backup.

## Testing

The app is its own unit-test host. Under the test runner it deliberately stays inert
(`AppInfo.isRunningTests`): it builds no UI, starts no wallpaper engine and reads no
Aerial store, so tests neither disturb the desktop nor contend for video decoders.

`build/runtests.sh` wraps `xcodebuild` with a wall-clock limit, because a failing test
can make the Xcode harness hang while symbolicating the failure through Spotlight.

Lock Screen write paths are tested against `SyntheticAerialStore`, a throwaway replica of
the real layout. A live test against the real store exists but is opt-in via
`LIVECANVAS_LIVE_LOCKSCREEN_TEST=1`.

## Logging

`OSLog` via `Log.<category>` with categories `app`, `playback`, `displays`, `media`,
`lockscreen`, `power`, `persistence`. File *paths* may be logged; file *contents* are
never logged.
