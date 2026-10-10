#!/bin/zsh
# Removes Hark from this Mac.
#   scripts/uninstall.sh          removes the app and keeps your settings and what Hark learned
#   scripts/uninstall.sh --purge  removes everything: settings, learned data, clipboard memory, the model key
#                                 in the Keychain, and the permissions macOS granted to Hark
set -euo pipefail

if pkill -x hark; then sleep 1; fi
rm -rf "$HOME/Applications/Hark.app"
echo "Removed the app."

if [ "${1:-}" = "--purge" ]; then
  rm -rf "$HOME/.config/hark" "$HOME/Library/Application Support/Hark" "$HOME/Library/Caches/Hark"
  rm -rf "${TMPDIR:-/tmp}/hark-cli"
  security delete-generic-password -s dev.hark.app -a model-key >/dev/null 2>&1 || true
  defaults delete dev.hark.app >/dev/null 2>&1 || true
  tccutil reset All dev.hark.app >/dev/null 2>&1 || true
  echo "Removed your settings, learned data, clipboard memory, model key and permissions."
else
  echo "Your settings and what Hark learned are still in ~/.config/hark and ~/Library/Application Support/Hark."
  echo "Run it again with --purge to remove those too."
fi
echo "If Hark was set to start at login, its entry disappears from System Settings > General > Login Items."
