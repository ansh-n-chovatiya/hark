#!/bin/zsh
# Plain `swift test` cannot find the Testing module with only the Command Line Tools installed.
set -euo pipefail
cd "$(dirname "$0")/.."
tools=/Library/Developer/CommandLineTools/Library/Developer
exec swift test \
  -Xswiftc -F"$tools/Frameworks" \
  -Xlinker -F"$tools/Frameworks" \
  -Xlinker -rpath -Xlinker "$tools/Frameworks" \
  -Xlinker -rpath -Xlinker "$tools/usr/lib" \
  "$@"
