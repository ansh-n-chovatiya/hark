#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/bundle.sh "${1:-debug}"
# Launch Services refuses to open the app while the old copy is still exiting.
if pkill -x hark; then sleep 1; fi
open build/Hark.app
