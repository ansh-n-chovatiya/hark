# Changelog

All notable changes are written here, newest first. Versions follow
[Semantic Versioning](https://semver.org); while Hark is below 1.0, a minor bump may change
behaviour.

## Unreleased

- Repository scaffolding: CI, contribution and security policy, issue and pull request templates,
  architecture notes, Makefile.

## 0.1.0 — 2026-10-10

First working version.

- Hold-to-speak and tap-to-type command bar in the menu bar.
- Rules-first command parsing; a model is asked only when the rules are unsure.
- Switch, open, hide, close and quit for apps, windows, Chrome tabs and files.
- Menu items, keyboard shortcuts and in-app buttons, with deletion blocked and risky actions
  confirmed first.
- Saved setups, routines, window arrangement, clipboard memory (encrypted, never sent to a model),
  system settings (volume, appearance, lock).
- Parakeet speech model through FluidAudio, with Apple's recogniser as a fallback.
- Settings window, history with "This was wrong" marking, 43-command evaluation set.
