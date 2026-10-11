#!/bin/bash
# Hark's promise is that some abilities do not exist. This lists every tool a model can call, as
# written in Sources/HarkMac/Agent, and fails if one is not in docs/capabilities.txt or if its name
# suggests deleting, moving, overwriting or running commands. Adding a tool means editing the list
# in the same change, where a reviewer will see it.
set -euo pipefail
cd "$(dirname "$0")/.."
found=$(grep -rhoE '(^|[ (])name: "[a-z_]+", *(verb|description|kind)|ToolSpec\(name: "[a-z_]+"|^ *name: "[a-z_]+",$' Sources/HarkMac/Agent \
  | grep -oE '"[a-z_]+"' | tr -d '"' | sort -u)
status=0
# The one tool allowed to run a command: it asks first, runs in a macOS sandbox that blocks deleting, moving and
# renaming, and is switched off in Settings (SAFETY.md, "Terminal commands"). Naming another here is a decision to
# review, not a formality.
sandboxed="run_command"
while read -r tool; do
  [ -z "$tool" ] && continue
  if [ "$tool" != "$sandboxed" ] && echo "$tool" | grep -qiE 'delete|remove|trash|erase|wipe|move|rename|overwrite|write|exec|shell|script|command'; then
    echo "forbidden capability name: $tool"; status=1
  fi
  if ! grep -qx "$tool" docs/capabilities.txt; then
    echo "tool not in docs/capabilities.txt: $tool"; status=1
  fi
done <<< "$found"
while read -r listed; do
  [ -z "$listed" ] && continue
  echo "$found" | grep -qx "$listed" || { echo "listed but not found in the source: $listed"; status=1; }
done < docs/capabilities.txt
echo "$found" | tr '\n' ' '; echo
exit $status
