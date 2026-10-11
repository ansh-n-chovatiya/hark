# Changelog

All notable changes are written here, newest first. Versions follow
[Semantic Versioning](https://semver.org); while Hark is below 1.0, a minor bump may change
behaviour.

## 0.2.19 — 2026-10-11

- Local servers, answered from the system's own tables with no terminal: "what's on 3000", "what's running", "open localhost
  5173" (switches to the tab if one is open), and "tell me when 3000 is up" (watches for up to 30 minutes).
- Routines can use `{here}`: the project folder of the window in front (one of your listed folders whose name is in the
  window title). A routine that uses it says so when no single project fits.

## 0.2.18 — 2026-10-11

- Buttons in Settings are clear brand-edged pills that fill when pressed (they were pale text on a faint box).
- The menu's first line is short ("Hold right Option to speak"); the other keys sit on a quieter second line.
- New menu entries: What can I say?, History…, Pause Hark / Resume Hark (Hark ignores its keys while paused), and Check
  for updates….

## 0.2.17 — 2026-10-11

- The menu-bar menu shows the same app icon as the Dock and Settings (one HarkMark view used in all of them).

## 0.2.16 — 2026-10-11

- Back to the original deep-blue app icon, used as the one brand colour across Settings, the menu and the overlay.

## 0.2.15 — 2026-10-11

- The installer finds the newest version's own address instead of the "latest" link, which can serve a stale checksum for a few
  minutes after a release ("The download is damaged").
- General: the punctuation switch no longer crowds the one below it.

## 0.2.14 — 2026-10-11

- The brand colour is now a calm deep teal (icon, Settings, menu, overlay, banner), replacing the orange.

## 0.2.13 — 2026-10-11

- Every text box in Settings now has the same fill, edge and height as the select boxes (and a kesri edge when focused).

## 0.2.12 — 2026-10-11

- The brand colour is kesri, a deep saffron orange (icon, Settings, menu, overlay, banner).
- Dictation can be edited by voice. Said alone: "scratch that" removes what Hark just typed; "change their to there" and
  "correct that to Priya" fix words in it; "select last word", "select line", "select all", "go to the start/end", and
  "delete selection" (only when something is selected). They act only on text Hark typed that is still right before the
  cursor (checked first), or on the selection, and never press Return.
- Spoken punctuation while dictating: "comma", "full stop", "question mark", "exclamation mark", "colon", "semicolon",
  "open quote ... close quote", "capital x", "all caps x", "no space", and "literal x" to type the word itself. A switch in
  General turns it off.
- "Learn the word <name>" adds it to what the speech recogniser expects.

## 0.2.11 — 2026-10-11

- The brand colour is now saffron (icon, Settings, menu, overlay, banner), replacing violet.
- Say "why did you do that" for what was heard, which part of Hark decided, what happened and how long it took; "what did
  you hear"; "that was wrong" (adds it to the problems list); "remember that as <name>" (teaches the last thing you said
  as a name); "what can I say" (examples filled in from your open apps and folders).
- A failure now ends with what to do next in plain words (allow it in Permissions, wait and try again, the next model
  will be used, check the connection).
- A switch, Settings, Understanding, "Keep everything on this Mac": no online model, no AI tool, no review of failed
  commands and no fetching of a site's search page.

## 0.2.10 — 2026-10-11

- One brand colour everywhere. The app icon, the mark and headers in Settings, the selection, toggles and buttons, the
  menu-bar menu and the overlay all use the same violet-to-indigo (HarkBrand), instead of seven section colours and the
  system blue. Sidebar icons are calm glass tiles until chosen; green, orange and red are kept for status only, with an
  icon and words. The README banner matches.

## 0.2.9 — 2026-10-11

- A new look for Settings: a glass sidebar with a colour-coded icon for each section, a large header with a soft glow
  in the section's colour, frosted cards, status shown as chips (icon and words), and a "Ready to listen / Needs a
  permission" indicator that takes you to Permissions. Works in light and dark and respects Reduce Motion; the
  window is wider (900 pt) and text stays at 12 pt or larger.
- `hark --show-settings <section>` opens the real window with sample data, for taking screenshots.

## 0.2.8 — 2026-10-11

- Terminal commands. For tasks only the terminal can do ("what is using port 3000", "what changed in this repo"), Hark
  can run one command: it shows the exact command and runs it only after you say yes, in a macOS sandbox that cannot
  delete, move or rename and, by default, cannot write files or use the network. What it prints is shown to you and
  never goes back to a model. A switch in Settings, Understanding, turns it off; a second switch lets commands create
  files and use the network (git pull, installs).

- "Open Warp's settings" no longer stops with "Hark can't use a terminal's menus" when a model chooses the item: in a
  terminal a model may choose a new tab or window and items in the app's own first menu (settings, about), the same as
  the rules.

## 0.2.7 — 2026-10-11

- No browser, app or website is named in Hark's rules any more; they are read from the Mac:
  - Browsers: any app that opens web addresses and has tabs. Tabs are read in every Chromium-based browser installed
    (Brave tabs now work), and "open Brave and search ...", "search ... in Brave", a bare "new tab" and the place a new
    tab opens use the browser you named, the one in front, or your default.
  - Other ways to say an app's name ("visual studio code", "vs code", "vscode") come from the installed apps; a name the
    recogniser splits in two ("you tube") is joined when that one-word name is open or installed.
  - The editor for a project folder is an installed developer app that opens folders (the one running, else used most
    recently). Setups remember the editor you used.
  - Terminals are recognised by declaring shell scripts and programs among what they open, so a terminal Hark has never
    heard of is still protected. Add others as `terminalApps` in the settings file.
- A terminal in front can be sent "new tab" or "new window", and its own settings, by menu click (no keys).

## 0.2.6 — 2026-10-11

- Site search no longer uses a built-in list of sites (0.2.5 had one). It reads each site's own search page instead; see
  the 0.2.5 notes below for how.

## 0.2.5 — 2026-10-11

- Vague requests are judged against what is open first. "Open settings" with Warp in front chooses Warp's own Settings
  (its menu), not the Mac's System Settings; naming the app ("open System Settings") still goes there. The model is
  now told the front app's menu items, so "open preferences" or "show the about box" resolve against that app.
- A search that names a site is searched on that site: "open YouTube and search Imran Hashmi", "search swift on GitHub".
  No site is listed in Hark: it reads the site's own published search page (OpenSearch) the first time and remembers it
  in ~/.config/hark/site-search.json. A site open in a tab is always searchable (through Google limited to it if it
  has no search page); a name that is an app, or a site without a search page, never turns into a web search.
- In a terminal Hark may choose a new tab or window and the terminal app's own menu (settings, about); nothing else.
- Rules-only evaluation: 47 of 55 (85 percent).

## 0.2.4 — 2026-10-11

- "New tab" and "open new Warp tab" now act in the app in front or the app named (File > New Terminal Tab), not always in
  Chrome. In a terminal only a new tab or window is chosen from the menus (no keys are sent). A greyed-out best match
  ("New Agent Tab") no longer hides the enabled one that fits ("New Terminal Tab").

## 0.2.3 — 2026-10-10

- Dictation now asks the app in front what has the keyboard (asking the whole system failed on some Macs, sending every
  dictation to the clipboard). It types only into text boxes, editable web content and terminals; otherwise it copies.
  Checked on TextEdit, Warp, VS Code, Brave and Finder; Terminal.app by rule only.
- `hark --typing-check` says what dictation would do in the app in front, typing nothing.
- "Open the standup file in TextEdit" and "open the projects folder in VS Code" by rule when the file or folder and
  the app each match clearly.
- "Copy the address of this tab" (also name or path of this window or file) by rule, for the item in front. Not yet
  seen working on a live Chrome tab.
- Rules-only evaluation: 47 of 55 (85 percent); CI now fails below 84.

## 0.2.2 — 2026-10-10

- Fixed a crash when removing a name from the Names list (a row removed while still in use read past the end of the
  list).
- The AI tool is only started when a model before it is resting, instead of on every key press.
- Settings: "via Claude Code" and the like are shown in History for each command a model answered.

## 0.2.1 — 2026-10-10

- Claude Code as a backup model is now a running process, started when you press the key: about 1.9 s per
  command once warm, against 7 to 10 s before.
- Fixes from an independent code review: menu items about sending, posting, paying, replacing and renaming ask
  first on every path; dictation types only into text boxes; an unreadable settings file is kept aside and an
  unread Keychain never deletes your key; a cancelled model is not marked as failed; several races and hangs.
- A software bill of materials and build provenance for releases; `scripts/uninstall.sh`.
- Names Hark suggests keep only the thing named and are proven to help before they are offered.

**Window layout and more rules**

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
