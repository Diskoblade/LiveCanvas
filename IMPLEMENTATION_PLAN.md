# LiveCanvas — Implementation Plan & Status

Priority order: reliability → safety → native behaviour → performance →
resolution independence → UI polish → extra features.

Status as of 2026-09-12. **126 unit tests, all passing** (`./build/runtests.sh test -only-testing:LiveCanvasTests`).

---

## Milestone 1 — Project + Library ✅
- ✅ Detected macOS 26.3 / Xcode 26.3 / Swift 6.2.4 on this machine
- ✅ Xcode project, folder-synchronised groups, product name in one xcconfig variable
- ✅ ARCHITECTURE.md, IMPLEMENTATION_PLAN.md, docs/TAHOE_AERIAL_FORMAT.md
- ✅ Sidebar window: Library · Displays · Lock Screen · Playlists · Settings
- ✅ Import MP4/MOV/M4V via Add Wallpaper, drag-and-drop, and Finder "Open With"
- ✅ Managed copies in Application Support; JSON library that self-heals missing media
- ✅ Metadata probe: duration, pixel size, frame rate, codec, HDR/SDR, audio, file size
- ✅ Async poster thumbnails with a bounded (300 item / 200 MB) cache
- ✅ Single-player hover preview and a detail sheet
- **Verified live:** 9 test videos imported (720p→4K, H.264/HEVC, portrait, ultrawide,
  with and without audio); every one probed correctly and produced a poster.

## Milestone 2 — Desktop engine ✅
- ✅ Borderless `WallpaperWindow` at `CGWindowLevelForKey(.desktopWindow)`
- ✅ Never key/main, ignores mouse, all Spaces, stationary, out of window cycling
- ✅ `AVQueuePlayer` + `AVPlayerLooper`, muted, hardware decode, gapless
- ✅ Assignments persisted
- **Verified live:** window level `-2147483623`, below the desktop icon layer
  (`-2147483603`) and below normal windows (`0`). 1.3–7 % CPU playing 4K HEVC.

## Milestone 3 — Resolution independence ✅
- ✅ Layout from `NSScreen.frame` / `backingScaleFactor`, no assumed sizes
- ✅ Fill / Fit / Stretch / Original as a pure, unit-tested function (`FitLayout`)
- **Verified live** on a 2560×1440@2x external and an 1800×1169@2x built-in panel, with
  a 21:9 source: Fit letterboxed, Fill cropped, Original centred a 720p clip at exactly
  640×360 points, and Original fell back to Fit when the video exceeded the screen.

## Milestone 4 — Multi-monitor ✅
- ✅ `DisplayManager` keyed on the CoreGraphics display UUID, with a vendor/model/serial
  fallback; coalesced `didChangeScreenParameters` handling, no polling
- ✅ Same-on-all-displays or per-display assignment, with per-display fit modes
- ✅ Reconcile diffs displays: unaffected players are never restarted
- **Verified live:** assigning one display only produced exactly one wallpaper window.

## Milestone 5 — System integration ✅
- ✅ Sleep/wake, display sleep/wake, screen lock/unlock, fullscreen detection
- ✅ `SMAppService` login item (no LaunchAgent plists)
- ✅ Menu bar extra: open, current wallpaper, pause/resume, next, Lock Screen, quit
- ✅ `PlaybackPolicy` as a pure function; battery, Low Power Mode and fullscreen rules
- **Bug found and fixed:** a maximized window on the larger monitor was counted as
  covering the smaller one, pausing wallpapers that were plainly visible. Detection now
  uses `CGDisplayBounds` and requires containment on every edge, so a zoomed window that
  stops below the menu bar no longer qualifies. Five regression tests cover it.

## Milestone 6 — Lock Screen research ✅
- ✅ `BackupManager`: SHA-256 before copy, re-hash after copy, verify before restore,
  permission preservation, added-file tracking, corrupt-backup refusal
- ✅ Read-only store inspection; `docs/TAHOE_AERIAL_FORMAT.md` written from real data
- ✅ `LockScreenCompatibility` gates on the OS major version
- ✅ `TarReader` reads Apple's pristine `entries.json` out of `manifest.tar`, so
  third-party modification is detectable offline
- **Bug found and fixed:** `.iso8601` truncates to whole seconds, so two backups made in
  the same second were indistinguishable and "restore the latest" could pick the wrong
  one. Timestamps now carry fractional seconds, with a legacy-format fallback.

## Milestone 7 — Lock Screen install ✅ (synthetic store) / ⚠️ (real store)
- ✅ `LockScreenWallpaperInstalling` protocol + `TahoeAerialInstaller`
- ✅ Preparation pipeline: remux (no re-encode) when the codec and size already fit,
  otherwise hardware transcode; audio always stripped; never upscales
- ✅ Apply / verify / restore, with rollback from the verified backup on any failure
- ✅ **Apple's own media files are never overwritten** — LiveCanvas only appends its own
  entry and its own files
- ✅ Refuses on: unvalidated OS, corrupt manifest, unwritable store, no Aerial selected
- ✅ 17 install/restore tests against a synthetic replica, including byte-exact restore
  and an apply → apply → restore cycle
- ⚠️ **Not yet executed against the real macOS store.** The live test exists
  (`RealStoreInstallTest`, gated behind `LIVECANVAS_LIVE_LOCKSCREEN_TEST=1`) but has not
  been run, so the end-to-end behaviour on a real Lock Screen is unverified. See
  "Remaining work" below.

## Milestone 8 — Production polish ◐
- ✅ Typed errors surfaced in the UI; nothing fails silently
- ✅ Lifecycle/leak tests: looper release, queue draining, no duplicate players on
  reconcile, window tear-down, single preview player
- ✅ Deep media audit detects Apple videos replaced in place by other tools
- ✅ Settings decoding is per-field lenient
- ☐ Instruments passes for GPU and memory profiling

## Playlists ✅ (was "second phase")
- ✅ Create, rename, delete, reorder; add and remove wallpapers
- ✅ Sequential and shuffle; 5 / 15 / 30 / 60 minute and custom intervals
- ✅ `PlaylistRotation` is a pure function: wrap-around, stale-shuffle detection,
  full-pass coverage, and a reshuffle that avoids replaying the visible wallpaper
- ✅ Rotation state persists, so a relaunch resumes instead of restarting
- ✅ A rotation that fell due while the app was closed is applied on launch
- ✅ Rotation is suspended whenever playback is, so a paused wallpaper does not cycle
  through the playlist unseen
- ✅ Entries whose media was deleted are skipped rather than showing nothing
- **Verified live:** a three-item playlist on a 20 second interval advanced at exactly
  20 second intervals (0 → 1 → 2 → 0) and the engine loaded the matching video on both
  displays each time.

## Milestone 9 — Distribution ☐
- Developer ID signing and notarization. **Blocked:** no signing identity on this Mac
  (`security find-identity -p codesigning` → 0 valid identities). Builds are ad-hoc
  signed; `Config/Shared.xcconfig` is the single place to switch this.

---

## What the development machine's store revealed

Two things worth knowing, both discovered by inspection rather than assumption. They are
the reason the installer is built the way it is.

1. **Another wallpaper app had already modified the Aerial store.** It injected a
   catalogue entry that is absent from Apple's pristine `manifest.tar`, which is exactly
   what the manifest comparison is there to detect.
2. **One of Apple's own Aerial videos had been overwritten in place** with an
   FFmpeg-encoded 8K H.264 file, while the catalogue still described it as a 4K Apple
   asset. Apple's original was gone, and only a re-download would bring it back.

LiveCanvas detects and reports both, and refuses to add to the damage: it never
overwrites an Apple media file and never touches entries it did not create.

## Bugs found by live testing (all fixed, all with regression tests)

1. **Maximized window mistaken for fullscreen.** A zoomed window on the larger monitor
   was counted as covering the smaller one, pausing wallpapers that were plainly visible.
   Detection now uses `CGDisplayBounds` and requires containment on every edge.
2. **Backup ordering was non-deterministic.** `.iso8601` truncates to whole seconds, so
   two backups made in the same second were indistinguishable and "restore the latest"
   could pick the wrong one. Timestamps now carry fractional seconds.
3. **One bad settings field discarded every setting.** A malformed value made the whole
   of settings.json fail to decode and silently fall back to defaults. Each field now
   decodes independently and logs what it ignored.
4. **Video decoded to a dark screen.** The sleep and lock monitors only observed
   *transitions*, so an app launched while the display was already off believed it was
   awake and kept decoding. Measured at 3–5 % CPU indefinitely; now 0 %. Both monitors
   read the live state at init (`SystemStateProbe`), re-read it on wake, and a slow
   30 second check catches any missed notification. This is the one that would have hurt
   most in practice, since a login item starts exactly in that situation.
5. **Unit tests ran the real app.** The app is its own test host, so the suite was
   booting the full UI, starting the wallpaper engine and auditing the user's 2 GB Aerial
   store on every run. The host is now inert under the test runner.

## Remaining work

1. **Run the live Lock Screen test** on the real store, then lock and unlock to confirm
   the wallpaper plays, and restore. This needs explicit authorization because it writes
   to the real macOS wallpaper files. Everything else about that path is tested against a
   synthetic replica.
2. Instruments passes for GPU and memory.
3. Signing and notarization once an identity is available.
4. Hardware not available here: a 1080p monitor, a rotated portrait display, and a
   three-monitor arrangement remain untested.
