<p align="center">
  <img src="CloudPlayer/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" alt="CloudPlayer icon">
</p>

# CloudPlayer

A native macOS player for SoundCloud, built with SwiftUI + WebKit. Requires macOS 14 or later.

> Unofficial. Not affiliated with or endorsed by SoundCloud.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/rzachulec/CloudPlayer/main/install.sh | bash
```

This downloads the right build for your Mac, quits CloudPlayer if it's running, puts it in
`/Applications`, and opens it. Run it again any time to update; you stay signed in, because your
SoundCloud session lives in `~/Library`, not inside the app. Read [`install.sh`](install.sh) first
if you like: it's short. Options go before `bash`, e.g. `… | CLOUDPLAYER_DIR=~/Applications bash`
installs elsewhere, and `CLOUDPLAYER_NO_LAUNCH=1` skips opening the app.

## Download

Every push to `main` builds the app for both Mac architectures, signs it with a self-signed
certificate, and publishes it on the [**latest** release](../../releases/tag/latest):

| Mac | File |
| --- | --- |
| Apple Silicon (M1 and newer) | `CloudPlayer-macos-apple-silicon.zip` |
| Intel | `CloudPlayer-macos-intel.zip` |

## Running a self-signed app from Terminal

The builds are signed with a self-signed certificate, not an Apple Developer ID, and are not
notarized. When you download one in a browser, macOS marks it as quarantined and Gatekeeper
refuses to open it ("CloudPlayer can't be opened because Apple cannot check it for malicious
software"). Removing the quarantine flag lets it run.

The [install command](#install) does this for you. **Step by step**, if you already downloaded the zip in your browser:

```sh
cd ~/Downloads

# 1. Unzip (ditto keeps the code signature intact)
ditto -x -k CloudPlayer-macos-apple-silicon.zip .     # or CloudPlayer-macos-intel.zip

# 2. Remove the quarantine flag macOS added to the download
xattr -dr com.apple.quarantine CloudPlayer.app

# 3. (Optional) move it to Applications
mv CloudPlayer.app /Applications/

# 4. Launch
open /Applications/CloudPlayer.app
```

To check the signature:

```sh
codesign -dvv /Applications/CloudPlayer.app   # shows "Authority=CloudPlayer Self-Signed"
codesign --verify --deep --strict /Applications/CloudPlayer.app && echo "signature OK"
```

> Only remove the quarantine flag from apps whose source you trust. You can read the code in
> this repo and the exact build steps in [`.github/workflows/build.yml`](.github/workflows/build.yml).

## Building locally

```sh
xcodebuild -project CloudPlayer.xcodeproj -scheme CloudPlayer -configuration Release \
  -derivedDataPath build build
open build/Build/Products/Release/CloudPlayer.app
```

Or open `CloudPlayer.xcodeproj` in Xcode and press ⌘R.

### Regenerating the app icon

The icon is drawn in code. To change it, edit `tools/gen_icon.swift` and run:

```sh
swift tools/gen_icon.swift CloudPlayer/Assets.xcassets/AppIcon.appiconset
```
