#!/bin/bash
# Installs or updates CloudPlayer from GitHub Releases:
#
#   curl -fsSL https://raw.githubusercontent.com/rzachulec/CloudPlayer/main/install.sh | bash
#
# Install the rolling nightly (staging) build from main:
#
#   curl -fsSL https://raw.githubusercontent.com/rzachulec/CloudPlayer/main/install.sh | bash -s -- --nightly
#
# Picks the build for this Mac (Apple Silicon or Intel), quits a running CloudPlayer, replaces
# it in /Applications, removes the quarantine flag (the build is self-signed, not notarized, see
# the README) and launches it. Your SoundCloud sign-in lives in ~/Library, so it survives updates.
#
# Flags:
#   --nightly                        install the rolling nightly build from main
#   --version <tag>                  install a specific release tag (e.g. v0.2.0)
#   -h, --help                       show usage
#
# Options (environment variables):
#   CLOUDPLAYER_CHANNEL=nightly      same as --nightly (default: stable)
#   CLOUDPLAYER_DIR=~/Applications   install somewhere else (default /Applications)
#   CLOUDPLAYER_NO_LAUNCH=1          don't open the app afterwards
#
# Everything runs inside main(), so a download cut off halfway can't run half a script.

set -euo pipefail

main() {
  local repo="rzachulec/CloudPlayer"
  local dir="${CLOUDPLAYER_DIR:-/Applications}"
  local app="$dir/CloudPlayer.app"
  local channel="${CLOUDPLAYER_CHANNEL:-stable}"
  local version=""

  bold() { printf '\033[1m%s\033[0m\n' "$*"; }
  step() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
  fail() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --nightly)
        channel="nightly"
        shift
        ;;
      --version)
        [ "$#" -ge 2 ] || fail "--version requires a release tag (e.g. v0.2.0)."
        version="$2"
        shift 2
        ;;
      --version=*)
        version="${1#--version=}"
        [ -n "$version" ] || fail "--version requires a release tag (e.g. v0.2.0)."
        shift
        ;;
      -h|--help)
        cat <<'USAGE'
Usage: install.sh [--nightly | --version <tag>]

  --nightly          Install the rolling nightly (staging) build from main
  --version <tag>    Install a specific release tag (e.g. v0.2.0)
  -h, --help         Show this help

Environment variables:
  CLOUDPLAYER_CHANNEL=nightly      Same as --nightly (default: stable)
  CLOUDPLAYER_DIR=~/Applications   Install directory (default: /Applications)
  CLOUDPLAYER_NO_LAUNCH=1          Don't launch the app after installing
USAGE
        exit 0
        ;;
      *)
        fail "Unknown option: $1 (try --help)"
        ;;
    esac
  done

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

  local url label
  if [ -n "$version" ]; then
    label="$version"
    url="https://github.com/$repo/releases/download/$version/CloudPlayer-macos-$arch.zip"
  elif [ "$channel" = "nightly" ]; then
    label="nightly"
    url="https://github.com/$repo/releases/download/nightly/CloudPlayer-macos-$arch.zip"
  elif [ "$channel" = "stable" ]; then
    label="latest stable"
    url="https://github.com/$repo/releases/latest/download/CloudPlayer-macos-$arch.zip"
  else
    fail "Unknown CLOUDPLAYER_CHANNEL: '$channel' (expected 'stable' or 'nightly')."
  fi

  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/cloudplayer.XXXXXX")"
  # shellcheck disable=SC2064  # expand now: $tmp is local and gone when the trap runs
  trap "rm -rf '$tmp'" EXIT

  step "Downloading CloudPlayer ($label, $arch)"
  curl -fL --progress-bar -o "$tmp/CloudPlayer.zip" "$url" || fail "Download failed: $url"

  step "Unpacking"
  ditto -x -k "$tmp/CloudPlayer.zip" "$tmp/unpacked" || fail "The download isn't a valid zip."
  [ -d "$tmp/unpacked/CloudPlayer.app" ] || fail "The download doesn't contain CloudPlayer.app."

  # Quit the copy being replaced in the current user's session
  # (leaves any Xcode Debug build or another macOS user's session alone).
  local uid binary="$app/Contents/MacOS/CloudPlayer"
  uid="$(id -u)"
  if pgrep -u "$uid" -qf "^$binary" ; then
    step "Quitting the running CloudPlayer"
    # Try graceful AppleScript quit first, then SIGTERM/SIGKILL to that exact binary path.
    osascript -e "tell application (POSIX file \"$app\" as text) to quit" >/dev/null 2>&1 || true
    local i
    for i in $(seq 1 6); do pgrep -u "$uid" -qf "^$binary" || break; sleep 0.25; done
    if pgrep -u "$uid" -qf "^$binary"; then
      pkill -u "$uid" -TERM -f "^$binary" 2>/dev/null || true
      for i in $(seq 1 12); do pgrep -u "$uid" -qf "^$binary" || break; sleep 0.25; done
    fi
    if pgrep -u "$uid" -qf "^$binary"; then
      pkill -u "$uid" -KILL -f "^$binary" 2>/dev/null || true
      sleep 0.5
    fi
    pgrep -u "$uid" -qf "^$binary" && fail "CloudPlayer didn't quit. Quit it and run this again."
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
