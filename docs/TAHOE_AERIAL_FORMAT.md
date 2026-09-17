# macOS 26 Tahoe — Aerial (Lock Screen) wallpaper store

**Status:** reverse-engineered by read-only inspection on 2026-09-12.
**Environment:** macOS 26.3 (25D5101c), Apple M4.
**This is undocumented Apple behaviour.** Nothing here is a public API. It can change in
any macOS update, including a minor one. Everything LiveCanvas does with this store is
gated behind `LockScreenCompatibility` and a verified backup.

---

## 1. Layout

```
~/Library/Application Support/com.apple.wallpaper/
├── Store/
│   └── Index.plist                  binary plist — which wallpaper each display/space uses
└── aerials/
    ├── manifest.tar                 pristine bundle as downloaded from Apple's CDN
    ├── manifest/
    │   ├── manifest.source          CDN path the tar came from
    │   ├── entries.json             the live asset catalogue (mutable)
    │   └── TVIdleScreenStrings.bundle  localized names (signed bundle)
    ├── videos/<assetID>.mov         downloaded / installed videos
    └── thumbnails/<assetID>.png     214 × 130 PNG posters
```

`manifest.source` on this machine:
`/itunes-assets/Aerials126/v4/82/2e/34/822e344c-.../resources-26-4-1.tar`

`manifest.tar` contains a pristine `entries.json` plus the strings bundle. **This is the
single most useful artefact for safety**: it is Apple's own untouched copy of the
catalogue, sitting on disk, and can be diffed against the live `entries.json` to detect
third-party modification without any network access.

## 2. `entries.json`

```jsonc
{
  "version": 1,
  "localizationVersion": "22L-1",
  "initialAssetCount": 157,
  "categories": [ /* 5 categories, each with subcategories */ ],
  "assets": [ /* 156 Apple assets on this machine */ ]
}
```

A genuine Apple asset:

```jsonc
{
  "id": "F390FE3B-FA61-483D-BADC-2447F89951BA",
  "accessibilityLabel": "California Wildflowers",
  "localizedNameKey": "W014_C018_F01_NAME",      // looked up in TVIdleScreenStrings
  "shotID": "W014_C018_F01",
  "group": "21J-1",
  "categories":    ["A33A55D9-…"],                // Landscape
  "subcategories": ["7C6A4BFE-…"],                // Superbloom
  "preferredOrder": 7,
  "showInTopLevel": true,
  "includeInShuffle": true,
  "pointsOfInterest": { "0": "W014_C018_0" },
  "previewImage": "https://sylvan.apple.com/…/W014_C018_F01@2x.png",
  "url-4K-SDR-240FPS": "https://sylvan.apple.com/…/W014_C018_F01_FRC_sdr_4k_…_t2160_….mov"
}
```

Every asset in the current manifest carries exactly one media key,
**`url-4K-SDR-240FPS`**. The key is the only variant present on this OS version; older
macOS releases used several (`url-4K-SDR-240FPS`, `url-1080-SDR-…`, HDR variants). Code
must therefore treat the media key as *discovered*, never hard-coded.

The value may be an `https://` CDN URL (not yet downloaded, or streamed) **or a
`file://` URL** pointing inside the store. That is the hook a custom wallpaper uses.

### Apple's downloaded videos

| Asset | Codec | Size | Rate | Pixel format |
|---|---|---|---|---|
| Tahoe Day | HEVC Main 10, `hvc1` | 3840 × 2160 | 240/1 | yuv420p10le |
| Sequoia Sunrise | HEVC Main 10 | 3840 × 2160 | 240/1 | yuv420p10le |
| Sonoma from Above | HEVC Main 10 | 3840 × 2160 | 59.94 | yuv420p10le |

So Apple ships 4K HEVC Main 10, BT.709 SDR, no audio track. A replacement does **not**
have to match this: a plain H.264 file plays fine (see §5). LiveCanvas still prefers
HEVC 4K-or-smaller to stay close to what the system expects.

## 3. `Store/Index.plist`

Binary plist, ~725 KB on this machine.

```
AllSpacesAndDisplays : "$null"
SystemDefault        : { Type, Desktop, Idle }
Spaces               : { <spaceUUID> : { … } }        ~1000 entries
Displays             : { <displayUUID> : { Desktop, Idle, Type } }
```

Each `Desktop` / `Idle` node:

```
Content:
  Choices: [ { Provider: String, Configuration: <binary plist Data>, Files: [] } ]
  EncodedOptionValues: <binary plist Data>
  Shuffle: "$null"
LastSet: Date
LastUse: Date
```

For the **Lock Screen** the node is `Idle`, and on this machine every display uses:

* `Provider` = `com.apple.wallpaper.choice.aerials`
* `Configuration` → nested binary plist → `{ "assetID": "<UUID>" }`
* `EncodedOptionValues` → `{ values: { aerialShuffleFrequency: { picker: { _0: { id: "shuffle_every_12_hours" } } } } }`

The Desktop node uses `com.apple.wallpaper.choice.image` with
`{ type: "imageFile", url: { relative: "file:///…jpg" } }`.

So: **the Lock Screen plays `aerials/videos/<assetID>.mov` where `assetID` comes from the
`Idle` choice's nested `Configuration` plist.**

`WallpaperAgent` owns this file and rewrites it. Any write must be treated as advisory,
and the agent may need restarting for a change to take effect.

## 4. Two ways to install a custom Lock Screen video

### (a) Overwrite an existing Apple asset's `.mov` — rejected

Replace `videos/<appleAssetID>.mov` in place. No manifest edit needed, because the Idle
choice already points there.

**LiveCanvas does not do this.** Apple's original is a 300–600 MB file that only exists
on disk; overwriting it destroys it, and the only recovery is re-downloading from Apple's
CDN, which an offline app cannot promise.

*Evidence this happens in the wild:* on this development machine the asset
`F390FE3B-…` ("California Wildflowers") **had already been overwritten before LiveCanvas
existed** — the file on disk is 7680 × 4320 H.264 with `encoder=Lavf61.1.100` (FFmpeg),
while the manifest declares a 4K SDR Apple asset. Some other tool did this, and Apple's
original is gone. LiveCanvas detects exactly this condition and reports it rather than
pretending a backup of that file is "Apple's original".

### (b) Add a new asset entry — what LiveCanvas implements

Append one object to `entries.json` → `assets`, with `file://` media URLs:

```jsonc
{
  "id": "<fresh UUID>",
  "accessibilityLabel": "Ocean",
  "localizedNameKey": "Ocean",            // shown verbatim when not in the loctable
  "shotID": "LIVECANVAS_<short>",
  "categories":    ["<LiveCanvas category UUID>"],
  "subcategories": ["<LiveCanvas subcategory UUID>"],
  "preferredOrder": 0,
  "showInTopLevel": true,
  "includeInShuffle": false,
  "pointsOfInterest": {},
  "previewImage":      "file:///…/aerials/thumbnails/<id>.png",
  "url-4K-SDR-240FPS": "file:///…/aerials/videos/<id>.mov"
}
```

…drop the video and poster next to Apple's, then point the `Idle` choice at the new
`assetID`.

Only **two** existing files are ever modified — `entries.json` and `Store/Index.plist` —
both backed up and SHA-256 verified first. Everything else is a pure addition that can be
deleted on restore. No Apple media file is ever touched.

*Evidence this shape works:* the same third-party tool also injected an entry of exactly
this form (`5DCC483C-…`, `file://` URLs, category `BD000000-0000-4000-8000-000000000001`)
into the live `entries.json`, and it is absent from the pristine `manifest.tar` copy.

## 5. Media requirements observed

* Container `.mov`, video track only. Apple ships no audio; LiveCanvas strips it.
* H.264 `avc1` and HEVC `hvc1` both play. 8-bit and 10-bit both play.
* Resolution is not constrained to 4K — an 8K file is in use on this machine.
* `previewImage` PNGs are 214 × 130 for Apple assets; other sizes render fine.

## 6. What this cannot do

The **FileVault / pre-login screen** after a cold boot is out of reach, and LiveCanvas
does not attempt it. That screen is drawn before the user's session (and therefore before
`~/Library/Application Support`) is available. Only the Lock Screen of an already
logged-in session is affected. This is a security boundary and LiveCanvas treats it as one.

## 7. Safety checks LiveCanvas performs before writing

1. macOS major version is 26. Anything else disables the feature with an explanation.
2. `aerials/`, `manifest/entries.json`, `videos/`, `thumbnails/` and `Store/Index.plist`
   all exist and are writable by the user.
3. `entries.json` parses and has `version == 1`, a non-empty `assets` array, and every
   asset has an `id` plus at least one `url-*` media key.
4. The media key name is read from the data, never assumed.
5. `manifest.tar` is compared against the live `entries.json` to report third-party
   modification and identify which assets are not Apple's.
6. Each downloaded video is compared against its manifest declaration; a mismatch marks
   that asset as already modified.
7. SHA-256 of every file to be changed is recorded, copied to the backup directory, and
   the copy is re-hashed before any write happens.
