#!/bin/bash
# Installs or updates CloudPlayer from the latest GitHub build:
#
#   curl -fsSL https://raw.githubusercontent.com/rzachulec/CloudPlayer/main/install.sh | bash
#
# Picks the build for this Mac (Apple Silicon or Intel), quits a running CloudPlayer, replaces
# it in /Applications, removes the quarantine flag (the build is self-signed, not notarized, see
# the README) and launches it. Your SoundCloud sign-in lives in ~/Library, so it survives updates.
#
# Options (environment variables):
#   CLOUDPLAYER_DIR=~/Applications   install somewhere else (default /Applications)
#   CLOUDPLAYER_NO_LAUNCH=1          don't open the app afterwards
#
# Everything runs inside main(), so a download cut off halfway can't run half a script.

set -euo pipefail

main() {
  local repo="rzachulec/CloudPlayer"
  local dir="${CLOUDPLAYER_DIR:-/Applications}"
  local app="$dir/CloudPlayer.app"

  bold() { printf '\033[1m%s\033[0m\n' "$*"; }
  step() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
  fail() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

  [ "$(uname -s)" = Darwin ] || fail "CloudPlayer is a macOS app."
  local major
  major="$(sw_vers -productVersion | cut -d. -f1)"
  [ "$major" -ge 14 ] || fail "CloudPlayer needs macOS 14 or later (this Mac has $(sw_vers -productVersion))."

  local arch
  case "$(uname -m)" in
    arm64) arch=apple-silicon ;;
    x86_64)
      # Under Rosetta, uname reports x86_64 on Apple Silicon: prefer the native build.
      if [ "$(sysctl -in sysctl.proc_translated 2>/dev/null)" = 1 ]; then arch=apple-silicon; else arch=intel; fi ;;
    *) fail "Unsupported architecture: $(uname -m)" ;;
  esac

  local url="https://github.com/$repo/releases/download/latest/CloudPlayer-macos-$arch.zip"
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/cloudplayer.XXXXXX")"
  # shellcheck disable=SC2064  # expand now: $tmp is local and gone when the trap runs
  trap "rm -rf '$tmp'" EXIT

  step "Downloading CloudPlayer ($arch)"
  curl -fL --progress-bar -o "$tmp/CloudPlayer.zip" "$url" || fail "Download failed: $url"

  step "Unpacking"
  ditto -x -k "$tmp/CloudPlayer.zip" "$tmp/unpacked" || fail "The download isn't a valid zip."
  [ -d "$tmp/unpacked/CloudPlayer.app" ] || fail "The download doesn't contain CloudPlayer.app."

  # Quit the copy being replaced (only that one: a build running from Xcode is left alone).
  local binary="$app/Contents/MacOS/CloudPlayer"
  if pgrep -qf "^$binary" ; then
    step "Quitting the running CloudPlayer"
    # By path, not by name: every CloudPlayer build shares one bundle ID.
    osascript -e "tell application (POSIX file \"$app\" as text) to quit" >/dev/null 2>&1 || true
    local i
    for i in $(seq 1 20); do pgrep -qf "^$binary" || break; sleep 0.5; done
    pgrep -qf "^$binary" && fail "CloudPlayer didn't quit. Quit it and run this again."
  fi

  local sudo=""
  mkdir -p "$dir" 2>/dev/null || true
  if [ ! -w "$dir" ] || { [ -e "$app" ] && [ ! -w "$app" ]; }; then
    step "$dir needs an administrator password"
    sudo="sudo"
  fi

  step "Installing to $app"
  $sudo rm -rf "$app"
  $sudo ditto "$tmp/unpacked/CloudPlayer.app" "$app"
  # Self-signed, not notarized: without this Gatekeeper refuses to open a downloaded copy.
  $sudo xattr -dr com.apple.quarantine "$app" 2>/dev/null || true

  codesign --verify --deep --strict "$app" 2>/dev/null || fail "The installed app's signature doesn't verify."

  if [ -z "${CLOUDPLAYER_NO_LAUNCH:-}" ]; then
    step "Opening CloudPlayer"
    open "$app"
  fi
  bold "CloudPlayer is installed. Run the same command again to update."
}

main "$@"
