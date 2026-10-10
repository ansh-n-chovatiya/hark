# Hark learns from how you use your Mac

## Why
A new user meets four empty screens (Folders, Projects, Names, Web pages, Routines) and has to fill
them in by hand. Hark should set most of that up itself, and keep improving, without ever doing
anything the user did not allow.

## Decisions (agreed with the user)
- On by default, with one switch to turn it off (Settings, Learning).
- Hybrid: finding folders at setup happens silently; names, web pages and routines are suggestions
  the user accepts with one tap.
- It watches Hark's own history, and which apps and websites (names only) the user switches between.
  Not file or folder names, page titles or contents, keystrokes or the clipboard.
- Everything stays on the Mac. No model reads it. Plain counting and rules.

## What is recorded
`~/Library/Application Support/Hark/activity.jsonl` (mode 0600), one line per event:
`{at, kind: "app" | "site", name}`. Apps come from the system's "app came to the front" notice; sites
come from the host name of Chrome's front tab (never the title or full address), only while Chrome is
in front. Records older than 90 days are removed. Nothing is recorded while learning is off.

The existing `timings.jsonl` supplies what was said and what happened.

## What it produces
| Goal | Rule | Result |
| --- | --- | --- |
| Setup | First run, config has no folders: look in ~/Developer, ~/Projects, ~/Code, ~/dev, ~/src, ~/Sites, ~/Workspace; read folder names only | Adds those roots to `searchFolders` and up to 12 most recently changed git projects to `repos`. Silent, once. |
| Misheard words | A command fails, then within 90 s a differently worded one succeeds and the two are alike | Suggests an alias `heard -> meant` after 2 sightings, or 1 when the two are very alike |
| Web pages | A site visited on 3 or more different days | Suggests a saved web page (`links`), named after the site |
| Repeated chores | The same 2+ apps or sites start the day (first 10 min of a session) on 3 or more days | Suggests a routine of `open <app>` / `open <page>` steps; never close, quit or shell steps |
| Dead ends | Commands that failed, grouped by wording | A list "Asked for, could not do", shown only to the user |

Suggestions the user dismisses are not offered again ("Not now" waits 14 days; "Never" is forever).
Accepting writes ordinary config entries (aliases, links, routines), so they can be edited or removed
in the existing screens; accepted items are also listed under Learning with a Remove button.

## Safety
- Learning only ever adds names, saved pages and open-only routines. It cannot add an action, touch
  files, close, quit, delete or run a command (decisions 0006 to 0009 still hold).
- Suggestions never run by themselves.
- Pause switch, "Delete what Hark learned", and 90-day expiry.
- Nothing leaves the Mac; the log is not sent to any model, local or hosted.

## Units
1. HarkCore `ActivityLog`: the event file, retention, deletion.
2. HarkCore `Learner`: pure functions from events and history to suggestions (tested).
3. HarkCore `LearningState`: what was dismissed, accepted, or already set up (`learning.json`).
4. HarkCore `ProjectFinder`: first-run folder discovery.
5. HarkMac `ActivityRecorder`: app and Chrome-host observation.
6. Config: `learns` (default true).
7. Settings, Learning tab: switch, suggestion cards, accepted list, dead ends, delete.
8. App wiring: record, run setup once, refresh suggestions, menu hint.

## Not in this version
Ordering choices by how often they are used (the matcher already prefers recent items), learning from
file names, and any sharing between Macs.
