# Changelog

All notable changes are written here, newest first. Versions follow
[Semantic Versioning](https://semver.org); while Hark is below 1.0, a minor bump may change
behaviour.

## Unreleased

- Window layout by rule: "put Chrome on the left and VS Code on the right", "make this window full size".
- "Open a new window in Chrome" and "create a note in Notes" by rule.
- Rules-only evaluation: 46 of 55 (84 percent); CI now fails below 83.

## 0.2.0 — 2026-10-10

Hark now works with no model for far more commands, keeps going when a model fails, and learns your habits.

**Understanding**
- Rules for web search ("search for X on Google", "open Chrome and search X"), for the volume, mute, dark
  mode and the lock screen, for short lists ("open Slack and Linear", "hide Safari and Notes"), for "hide
  everything except X", and for "this tab", "this window" and "this app".
- "Open Notes and create a new note": opens the app and chooses the matching item from its menu bar.
- "New window", "print this" and "click send" act on the app in front, first through its menus and then
  through the buttons, tabs and list items of its window. Sending, posting and paying ask first.
- On the built-in evaluation, the rules alone now settle 39 of 51 commands (up from 29), with no model.

**Models**
- An ordered chain: your online model, then an AI tool already on the Mac (Claude Code is found
  automatically, text only, Haiku by default), then the model on this Mac. A model that fails, such as one
  out of quota, rests for a while instead of making every command wait. Each can be turned off or moved.
- Pick the service and the models from lists read from the service itself, for the online model, the model
  on this Mac and Claude Code. Several online models can be asked at once.
- The model key is kept in the macOS Keychain, not in `config.json`.
- Offline, models that need the internet are skipped.

**Dictation**
- Hold a key and speak: your words are typed into any app, using the speech model on this Mac.
- Double-tap the key for hands-free; one tap or the stop button finishes.
- With no text box to type into, the words are copied to the clipboard instead of being lost.

**Learning**
- Hark offers names, saved web pages and routines from how you use your Mac, on this Mac only; on by
  default, with one switch. First run finds your project folders. A name you remove stays removed.

**Interface**
- A new menu-bar menu, one reusable list control used across Settings, a small draggable dictation pill with
  a live waveform, and a Learning tab.

**Fixes**
- Hark no longer presses its own buttons. A refused thinking-level setting no longer hides every online
  answer. Chrome's permission says "open Chrome to check" while Chrome is closed instead of "Needed".

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
