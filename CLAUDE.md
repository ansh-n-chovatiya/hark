# Hark

A macOS menu bar app: hold one key, say a command, release, and it acts. It finds and switches
tabs, windows, apps and files, remembers the clipboard, and saves and restores workspaces.
Doing the right thing comes first, speed second: waiting two seconds is better than doing the
wrong task.

## Read first
1. `README.md` and `SAFETY.md` for what Hark does and never does.
2. `docs/ARCHITECTURE.md` for the layout and key decisions.
3. `.ctx/` (local, not committed, if present): spec, plan and decisions 0006-0009 referred to below.

## Rules
- Use the Karpathy guidelines skill and the Context Ledger (`/ctx:status`, `/ctx:next`,
  `/ctx:start`) in every session on this project.
- Hark is meant to be shared: anyone should be able to clone the repo and install it with
  `scripts/install.sh`. Keep the project free of anything personal: no real names, client or
  employer names, home paths, keys or machine-specific settings in sources, tests, examples or
  scripts. Personal settings live in `~/.config/hark/config.json`.
- This folder is the git repository (`~/Desktop/Personal/Hark`). Never commit `.ctx/`, build
  output or anything personal. `scripts/package.sh` still makes a clean source zip.
- Native Swift, one SwiftPM package, system frameworks only. No third-party packages.
- Rules decide first and act at once. A model is asked only when the rules are unsure, never for
  a command they settle (decision 0006). No new process between key release and the action.
- Clipboard text never leaves the machine and never reaches any model, local or hosted.
- Hark never deletes, moves, renames or overwrites the user's files, never empties the trash and
  never runs a command a model wrote (decision 0008). Do not add an action that can. Its actions
  are limited to things that can be reopened: switching, opening, hiding, closing tabs and
  windows, quitting apps, and pasting. Closing or quitting always asks first when a model chose it.
- The model key lives only in `~/.config/hark/config.json`. Never print it, log it or copy it into
  the project.
- Never claim a speed without a number from the timing log.
- When accuracy and speed pull apart, choose accuracy, up to about two seconds from key release
  to action (decision 0007). Past that, look for a faster way to be right, not a faster guess.

## UI work
- Load the `ui-ux-pro-max` skill before designing or changing anything the user sees (overlay,
  menu, settings window). Subagents cannot load it, so the main session briefs them with its
  guidance and reviews their UI afterwards.
- The UI must look good, be easy to understand for a non-technical person, and work in light and
  dark. Native look: system font, system materials, SF Symbols, no emoji as icons.
- Type sizes come from `OverlayStyle` (nothing under 12 pt). Never rely on colour alone; pair it
  with an icon or words. Respect Reduce Motion.
- Look at it before calling it done: render the view to an image or screenshot the running app.

## Commands
- Build: `swift build`
- Test: `scripts/test.sh` (plain `swift test` cannot find the Testing module on this Mac)
- Run the signed app: `scripts/run.sh` (always use this when a macOS permission is involved)
- Install for everyday use: `scripts/install.sh` (release build into `~/Applications`)
