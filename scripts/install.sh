#!/bin/zsh
# Builds Hark from source, signs it with a certificate made on this Mac, and installs it.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v swift >/dev/null; then
  echo "Hark needs the Swift toolchain. Install it with: xcode-select --install"
  exit 1
fi

scripts/bundle.sh release

destination="$HOME/Applications"
mkdir -p "$destination"
if pkill -x hark; then sleep 1; fi
rm -rf "$destination/Hark.app"
cp -R build/Hark.app "$destination/Hark.app"
# One Hark on the Mac, not two: the copy left in the build folder would show up beside the
# installed one in Spotlight and Launchpad.
rm -rf build/Hark.app

settings="$HOME/.config/hark/config.json"
if [ ! -e "$settings" ]; then
  mkdir -p "$(dirname "$settings")"
  cp examples/config.json "$settings"
  chmod 600 "$settings"
  echo "Created $settings. Edit it to list your own folders, nicknames and model key."
fi

open "$destination/Hark.app"
echo "Hark is installed in $destination and running. Look for the waveform icon in the menu bar."
