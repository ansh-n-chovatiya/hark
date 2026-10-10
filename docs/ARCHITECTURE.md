# Architecture

One SwiftPM package, system frameworks only (plus FluidAudio for speech).

```
key held ─► MicrophoneInput ─► Parakeet / Apple recogniser ─► text
                                                               │
 typed command ────────────────────────────────────────────────┤
                                                               ▼
                                   Parser + Matcher (rules, HarkCore)
                                      │ settled                │ unsure
                                      ▼                        ▼
                                 Pipeline ◄──── Agent (OpenAI-compatible model + tools)
                                      │
                         Safety (HarkCore) decides: run / ask first / refuse
                                      ▼
                          Sources and tools act on the Mac ─► Overlay + History + Undo
```

## Targets

| Target | Path | Role |
| --- | --- | --- |
| `HarkCore` | `Sources/HarkCore` | No macOS dependence: config, parser, matcher, safety rules, routines, clipboard store, undo, timings. Fully unit tested. |
| `HarkMac` | `Sources/HarkMac` | Everything that touches the Mac: hotkey, speech, overlay, settings window, sources (apps, windows, Chrome tabs, files), model tools. |
| `hark` | `Sources/Hark` | Entry point and command-line flags (`--say`, `--eval`, `--tool`, `--wrong`). |
| `HarkCoreTests` | `Tests/HarkCoreTests` | Unit tests for `HarkCore`. |

## Key decisions

- **Rules first, model second.** A model is asked only when the rules are unsure.
- **Safety by capability, not by trust.** The tools cannot delete or run model-written commands, so a
  misbehaving model has nothing to misuse. See [SAFETY.md](../SAFETY.md).
- **Accuracy over speed**, up to about two seconds from key release to action.
- **One stable signing identity** ("Hark Dev", created by `scripts/make-cert.sh`) so macOS keeps
  granted permissions across rebuilds.

## Scripts

| Script | Purpose |
| --- | --- |
| `scripts/bundle.sh [debug\|release]` | Build and sign `build/Hark.app`. |
| `scripts/run.sh` | Bundle (debug) and launch. Use whenever a permission is involved. |
| `scripts/install.sh` | Release build into `~/Applications`, create default config, launch. |
| `scripts/test.sh` | Run tests with the Testing framework paths set. |
| `scripts/package.sh` | Zip the source for publishing. |
