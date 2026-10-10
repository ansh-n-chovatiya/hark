#!/bin/zsh
# Builds the app, zips it and publishes it as a GitHub release: scripts/release.sh v0.1.0
# Built on the maintainer's Mac so every release carries the same signing identity; macOS then
# keeps the permissions users already gave Hark when they update.
set -euo pipefail
cd "$(dirname "$0")/.."
tag=${1:?usage: scripts/release.sh vX.Y.Z}

scripts/bundle.sh release
archive="build/Hark-macos-arm64.zip"
rm -f "$archive"
ditto -c -k --keepParent build/Hark.app "$archive"
(cd build && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")

gh release create "$tag" "$archive" "$archive.sha256" --title "Hark $tag" --generate-notes
echo "published $tag"
