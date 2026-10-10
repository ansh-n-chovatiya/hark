#!/bin/zsh
# Installs the latest prebuilt Hark. No Xcode or Swift needed:
#   curl -fsSL https://raw.githubusercontent.com/ansh-n-chovatiya/hark/main/scripts/get.sh | zsh
set -euo pipefail
repo="ansh-n-chovatiya/hark"
if [ "$(uname -m)" != "arm64" ]; then
  echo "Hark needs a Mac with Apple silicon (M1 or newer)."
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
base="https://github.com/$repo/releases/latest/download"
curl -fsSL "$base/Hark-macos-arm64.zip" -o "$work/Hark.zip"
curl -fsSL "$base/Hark-macos-arm64.zip.sha256" -o "$work/Hark.zip.sha256"
[ "$(shasum -a 256 "$work/Hark.zip" | cut -d' ' -f1)" = "$(cut -d' ' -f1 "$work/Hark.zip.sha256")" ] \
  || { echo "The download is damaged. Try again."; exit 1; }

destination="$HOME/Applications"
mkdir -p "$destination"
if pkill -x hark; then sleep 1; fi
rm -rf "$destination/Hark.app"
ditto -x -k "$work/Hark.zip" "$destination"
xattr -dr com.apple.quarantine "$destination/Hark.app" 2>/dev/null || true
open "$destination/Hark.app"
echo "Hark is installed in $destination and running. Look for the waveform icon in the menu bar."
