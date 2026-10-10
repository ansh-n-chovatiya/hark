# Architecture

One SwiftPM package, system frameworks only (plus FluidAudio for speech).

```
key held ─► MicrophoneInput ─► Parakeet / Apple recogniser ─► text
                                                               │
 typed command ────────────────────────────────────────────────┤
                                                               ▼
        Rules that decide alone (HarkCore): web search, system commands, window layout,
        open-an-app-and-act, app in front, lists, "this tab", Parser + Matcher
                                      │ settled                │ unsure
                                      ▼                        ▼
                                 Pipeline ◄──── Agent ◄── ModelChain
                                      │                    online model → AI tool on the Mac → model on this Mac
                         Safety (HarkCore) decides: run / ask first / refuse
                                      ▼
                          Sources and tools act on the Mac ─► Overlay + History + Undo

 dictation key ─► same speech path ─► Dictation.tidy ─► TextTyper (letters only, never Return)
                                                         └─ no text box ─► clipboard
 app activity + History ─► Learner (counting) ─► Suggestion ─► SuggestionProof (dry run) ─► Settings, Learning
```

## Targets

| Target | Path | Role |
| --- | --- | --- |
| `HarkCore` | `Sources/HarkCore` | No macOS dependence: config, parser, matcher, safety rules, routines, clipboard store, undo, timings, the rule layers (`WebSearch`, `SystemCommand`, `WindowLayout`, `AppAction`, `FrontAction`), `CLIToolProtocol`, learning (`Learner`, `LearningCenter`, `ActivityLog`), `ConfigSecrets`, `DictationTaps`. Fully unit tested. |
| `HarkMac` | `Sources/HarkMac` | Everything that touches the Mac: hotkey, speech, overlay, dictation pill, settings window, sources (apps, windows, Chrome tabs, files), model tools, `ModelChain` and the AI-tool adapter, Keychain, activity recorder, text typing. |
| `hark` | `Sources/Hark` | Entry point and command-line flags (see below). |
| `HarkCoreTests`, `HarkMacTests` | `Tests/` | Unit tests. `HarkMacTests` covers the model chain with fake models. |

## Where things live

- **Rules before models.** `Pipeline.run` tries, in order: a named routine, a refusal, web search, system
  commands (`SystemCommand`), window layout, open-an-app-and-act (`AppAction`), the parser's command, and for a
  command the rules are unsure about, the app in front (`FrontAction`) and only then the agent.
- **Models.** `ModelSetup.make` builds a `ModelChain` from the settings: the online model, AI command-line
  tools found by `ModelCLIs.discover` (Claude Code, text only through `CLIChatModel` and `CLIToolProtocol`),
  then the model on this Mac. `ModelHealth` rests a model that just failed. A model's reply is only ever a
  list of calls to Hark's own tools, checked against the tool list.
- **The model key** lives in the Keychain; everything that reads settings uses `ConfigStore`.
- **Learning** is counting and rules: `Learner` makes suggestions from `timings.jsonl` and `activity.jsonl`;
  `SuggestionProof` shows a name helps before it is offered; accepting only edits ordinary settings.
- **Dictation** types through `TextTyper` (key events, letters only) and falls back to the clipboard.

## Key decisions

- **Rules first, model second.** A model is asked only when the rules are unsure.
- **Safety by capability, not by trust.** The tools cannot delete or run model-written commands, so a
  misbehaving model has nothing to misuse. See [SAFETY.md](../SAFETY.md).
- **Accuracy over speed**, up to about two seconds from key release to action.
- **One stable signing identity** ("Hark Dev", created by `scripts/make-cert.sh`) so macOS keeps
  granted permissions and Keychain access across rebuilds.
- **Learning never adds an action.** It adds names, saved pages and open-only routines, after a tap.

## Command-line flags (development)

`--say "<command>" [--dry] [--trace]`, `--eval <file> [--rules-only [--min N]]`, `--models`, `--proof`,
`--review-failures`, `--permissions`, `--window-counts`, `--show-dictation`, `--render-settings <folder>`, `--tool`, `--wrong`.
Set `HARK_NO_KEYCHAIN=1` to run without reading the Keychain.

## Scripts

| Script | Purpose |
| --- | --- |
| `scripts/bundle.sh [debug\|release]` | Build and sign `build/Hark.app`. |
| `scripts/run.sh` | Bundle (debug) and launch. Use whenever a permission is involved. |
| `scripts/install.sh` | Release build into `~/Applications`, create default config, launch. |
| `scripts/get.sh` | Install the latest prebuilt release (what users run). |
| `scripts/release.sh vX.Y.Z` | Build, zip and publish a release with the changelog as notes. |
| `scripts/uninstall.sh [--purge]` | Remove the app; with `--purge` also settings, learned data, the Keychain key and permissions. |
| `scripts/test.sh` | Run tests with the Testing framework paths set. |
| `scripts/check-capabilities.sh` | Fail if a model tool is not on the approved list or looks destructive. |
| `scripts/package.sh` | Zip the source for publishing. |
