# Contributing to Hark

Read [CLAUDE.md](CLAUDE.md) first: it holds the project rules, and this file assumes them.

## Setup

Requirements: Apple silicon Mac, macOS 26, Apple's Command Line Tools (`xcode-select --install`).

```sh
git clone <repository address>
cd Hark
swift build
scripts/test.sh
```

## The gates

A change is done when all of these pass:

1. `swift build` has no warnings from your files.
2. `scripts/test.sh` passes. Use the script, not plain `swift test` (see the README for why).
3. If you touched parsing, matching or the tools: `.build/debug/hark --eval evals/developer-day.json`
   scores no lower than before. State both numbers in the PR.
4. If you touched anything the user sees: run `scripts/run.sh` and look at it in light and dark.
5. `CHANGELOG.md` has a line under **Unreleased**.

## Rules that are not negotiable

These are the project's safety and privacy rules; a PR that breaks one will not be merged.

- No action that deletes, moves, renames or overwrites a user's files, or empties the trash.
- No running of commands a model wrote. Routines the user wrote are the only commands Hark runs.
- Clipboard text never reaches a model.
- No third-party Swift packages beyond those already in `Package.swift` without an issue first.
- Nothing personal in the repo: no real names, employers, home paths or keys.
- Never claim a speed without a number from the timing log.

## Layout

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Pull requests

- One change per PR, with tests in `Tests/HarkCoreTests` for anything in `HarkCore`.
- Keep `HarkCore` free of macOS-only APIs; anything that touches the Mac goes in `HarkMac`.
- When a command was misread, add it to the evaluation set rather than special-casing it.
- Use the PR template and explain what could go wrong, not only what changed.

By contributing you agree your work is released under the [MIT licence](LICENSE).
