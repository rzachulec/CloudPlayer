<p align="center">
  <img src="CloudPlayer/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" alt="CloudPlayer icon">
</p>

# CloudPlayer

A native macOS player for SoundCloud, built in **100% SwiftUI + `AVFoundation` + SoundCloud `api-v2`** (zero persistent WebKit). Requires macOS 14 or later, optimized for macOS 26 Liquid Glass.

> Unofficial. Not affiliated with or endorsed by SoundCloud.

## Highlights

- **Zero WebKit during listening:** A disposable `WKWebView` login sheet is instantiated *only* when signed out to handle SoundCloud's sign-in and OAuth providers, captures the session token, and is immediately torn down and deallocated.
- **Native audio & system integration:** Hardware-accelerated HLS/MP3 streaming via `AVPlayer`, custom value-type queue (`PlaybackQueue`) with Up Next, reversible shuffle, repeat modes, autoplay, macOS media keys, Control Center Now Playing, Menu Bar controls, and a floating Mini Player (`⇧⌘M`).
- **Perceived performance:** Stale-while-revalidate memory + disk API caching, Nuke image caching, shimmering skeleton placeholders, 30fps sub-pixel `Canvas` waveforms, and timed waveform comments.
- **Native screens:** Home/Discover carousels, Likes (Tiles / Compact / Waveform modes + full-library instant filter), Playlists, Albums, Saved Stations, Following, History, Search (Tracks / Playlists / Albums / People + live tag facets and track filters), Track Detail, and Apple Music–style Artist Profiles.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/rzachulec/CloudPlayer/main/install.sh | bash
```

This downloads the right build for your Mac, quits CloudPlayer if it's running, puts it in `/Applications`, and opens it. Options go before `bash`, e.g. `… | CLOUDPLAYER_DIR=~/Applications bash` installs elsewhere, and `CLOUDPLAYER_NO_LAUNCH=1` skips opening the app.

## Building locally

```sh
xcodebuild -project CloudPlayer.xcodeproj -scheme CloudPlayer -configuration Release \
  -derivedDataPath build build
open build/Build/Products/Release/CloudPlayer.app
```

Running the unit test suite:

```sh
xcodebuild -project CloudPlayer.xcodeproj -scheme CloudPlayer -configuration Debug \
  -derivedDataPath build test
```

Or open `CloudPlayer.xcodeproj` in Xcode and press `⌘R` (`⌘U` for tests).

### Regenerating the app icon

The icon is drawn in code. To change it, edit `tools/gen_icon.swift` and run:

```sh
swift tools/gen_icon.swift CloudPlayer/Assets.xcassets/AppIcon.appiconset
```
