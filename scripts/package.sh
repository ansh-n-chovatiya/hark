#!/bin/zsh
# Makes a zip of the project's own files, ready to copy to another Mac or publish. Build output
# and local planning notes are left out.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
archive="$PWD/build/hark-source.zip"
rm -f "$archive"
zip -qr "$archive" . \
  -x './.build/*' './build/*' './.ctx/*' './.swiftpm/*' './graphify-out/*' './.git/*' \
  -x '*.DS_Store' './.vscode/*' './.idea/*'
echo "wrote $archive ($(du -h "$archive" | cut -f1))"
