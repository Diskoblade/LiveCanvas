# LiveCanvas

A native macOS app that plays your own video as a live Desktop wallpaper, and — on
macOS 26 Tahoe — as the animated Lock Screen wallpaper of your logged-in session.

Swift 6.2 toolchain, SwiftUI + AppKit + AVFoundation. No Electron, no web view, no
network code, no accounts, no telemetry. Everything stays on your Mac.

> **Working name.** The product name lives in one place, `Config/Shared.xcconfig`
> (`LC_PRODUCT_NAME`), and the code reads it from the bundle at runtime.

## What it does

- **Desktop wallpaper.** One hardware-decoded, gaplessly looping video per display,
  in a borderless window at the desktop window level — behind your icons and windows,
  out of Mission Control, out of Cmd-Tab, and transparent to the mouse.
- **Any display.** Layout comes from `NSScreen.frame` and `backingScaleFactor`, so
  16:9, 16:10, 3:2, 21:9, portrait and scaled Retina modes all work. Fill, Fit,
  Stretch and Original fit modes.
- **Multi-monitor.** One wallpaper everywhere, or a different one per display.
  Displays are tracked by their CoreGraphics UUID so assignments survive reconnects.
- **Playlists.** Sequential or shuffle, on a 5 / 15 / 30 / 60 minute or custom
  interval. Rotation state persists, so a relaunch resumes instead of restarting.
- **Energy aware.** Pauses on screen lock, display sleep, Low Power Mode, and
  optionally while another app is full screen. Configurable battery behaviour.
- **Lock Screen (macOS 26).** Installs your video as an Aerial wallpaper behind a
  SHA-256-verified backup, with a one-click restore.

## Requirements

| | |
|---|---|
| macOS | 15.0 to build and run the desktop engine; **26 Tahoe** for the Lock Screen feature |
| Xcode | 26.x (developed against 26.3, macOS 26.2 SDK) |
| Signing | ad-hoc by default; no Developer ID needed to build locally |

## Build and run

```bash
open LiveCanvas.xcodeproj
```

Or from the command line:

```bash
xcodebuild -project LiveCanvas.xcodeproj -scheme LiveCanvas -configuration Debug build
```

## Tests

```bash
./Scripts/runtests.sh test -only-testing:LiveCanvasTests
```

Use the wrapper rather than calling `xcodebuild` directly. Xcode 26's test harness can
hang while symbolicating a failing test through a Spotlight dSYM lookup, and the wrapper
enforces a wall-clock limit so a failure surfaces as a failure instead of a hang.

To generate the synthetic clips used for the resolution and codec matrix (needs `ffmpeg`):

```bash
./Scripts/make-test-media.sh
```

## Supported media

MP4, MOV and M4V containers, with any codec AVFoundation can decode — H.264 and HEVC are
the tested paths. No resolution or aspect-ratio limits. Audio is allowed but muted by
default, and the Lock Screen copy always has its audio stripped. GIF, APNG, WebM and
image sequences are not supported; the ingestion layer has placeholders for them.

Imported files are copied into the app's own storage, so moving or deleting the original
afterwards does not break the wallpaper.

## The Lock Screen feature, and its limits

Apple publishes no API for using an arbitrary video as the Lock Screen wallpaper.
LiveCanvas drives the per-user Aerial store that macOS 26 keeps under
`~/Library/Application Support/com.apple.wallpaper/`. That mechanism is **undocumented
and may change in any macOS update**, so the whole integration sits behind one protocol
(`LockScreenWallpaperInstalling`) and a version gate that disables itself on an OS whose
layout has not been validated. [`docs/TAHOE_AERIAL_FORMAT.md`](docs/TAHOE_AERIAL_FORMAT.md)
documents the format as observed, along with how it was determined.

Safety rules the installer holds to:

- **No Apple media file is ever overwritten.** LiveCanvas appends its own catalogue entry
  and adds its own files. Apple's Aerial videos are 300–600 MB files that exist only on
  disk; overwriting one destroys it with no offline way back.
- Exactly two existing files are modified, `entries.json` and `Store/Index.plist`, and
  both are hashed, copied and re-verified before anything is written.
- Restore replaces both from the verified backup, re-checks their hashes, and removes the
  files LiveCanvas added.
- Any validation failure refuses the operation instead of risking the store.
- It detects when another tool has already modified the store, and declines to add to it.

**What it cannot do:** the FileVault login screen after a restart. That screen runs before
your account is unlocked, so it cannot read your video. LiveCanvas does not attempt to
change it, and treats that as a security boundary rather than an obstacle.

It also never disables SIP, touches FileVault, modifies `loginwindow`, injects code,
requests root, asks for accessibility permission, or installs a system extension.

## Layout

```
LiveCanvas/
  App/          LiveCanvasApp, AppDelegate, AppState, SystemCoordinator
  Models/       Codable value types; no AppKit or AVFoundation
  Services/     library, displays, power/lock/sleep monitors, persistence
    LockScreen/ the undocumented integration, isolated behind a protocol
  Playback/     wallpaper window, player, layer view, fit-mode math
  UI/           SwiftUI views per sidebar section
  Utilities/    logging, atomic writes, hashing, OS version
LiveCanvasTests/
Config/         xcconfigs, entitlements, Info.plist additions
docs/           reverse-engineering notes
Scripts/        test runner, test-media generator
```

Further reading: [`ARCHITECTURE.md`](ARCHITECTURE.md) for the design and concurrency
model, [`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md) for milestone status and the
bugs found along the way.

## Status

The desktop engine, multi-monitor handling, playlists, energy management and the menu bar
are implemented and exercised on real hardware. The Lock Screen install and restore path
is covered by tests against a synthetic replica of the store, including byte-exact
restoration, but **has not yet been run against a real macOS store**. Signing and
notarization are not set up.
