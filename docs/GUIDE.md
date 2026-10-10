# Hark full guide

Everything Hark can do, how to set it up, routines, models and developer notes. For the short version see the [README](../README.md).

Hark is a small macOS app that lives in your menu bar. Hold a key and say what you want, or tap the
key and type it, and Hark does it on your Mac.

Some commands it handles (these come from the included test set in `evals/developer-day.json`):

- "Switch to Chrome"
- "Open the projects folder"
- "Open Shop backend in VS Code"
- "Open the render logs tab"
- "Open the standup file in TextEdit"
- "Open Slack and Linear"
- "Hide everything except Warp"
- "Quit Slack and Linear" (Hark asks first)
- "Close the screen recorder tab" (Hark asks first)
- "Open a new window in Chrome"
- "Set the volume to 30 percent"
- "Switch to dark mode"

## What it can do

**Switch and open.** Bring an app, a window or a browser tab to the front. Open an app, a file, a
folder, a web address you named, or a new tab. Open a file or folder in a particular app. Hide an
app, or hide everything except the apps you name. You can name several things in one command.

**Close and quit.** Close a window or a browser tab, or quit an app. Hark always shows what it is
about to do and waits for your yes.

**Several steps in one command.** "Open the projects folder in VS Code and switch to dark mode" is
one command. Hark does at most twelve actions for one command.

**Menus and shortcuts.** Hark can read the menus of a running app, choose a menu item ("open a new
window in Chrome") and press a keyboard shortcut. Menu items and shortcuts about deleting,
discarding, clearing or resetting are blocked. Items that close, quit, log out, shut down or
restart ask first.

**What you are looking at, and what you just did.** "Close this tab", "hide this app" and "that
window" mean the one in front. Hark also keeps your last three commands in mind, so "do that again"
and "no, the other one" work.

**Saved setups.** Say "save this setup as morning" and Hark writes a routine that reopens the apps
and project folders you have open now. Say "morning" to open them again. It saves apps and editor
folders, not browser tabs or window positions.

**Web pages by name.** Give a page a name once in Settings, under Names, and "open the task board"
goes straight to it.

**Arranging windows.** "Chrome on the left and the editor on the right", "make this full size",
"move this to the next screen", "centre this window". Halves, quarters and thirds are understood.

**Answers.** A routine that prints something is treated as a question: "branches", "is it up 8002",
"my reviews". The answer stays on screen long enough to read.

**In the background.** "Open Slack in the background" starts the app hidden: no window comes up and
you stay where you are.

**Tell me when.** Add "and tell me when it finishes" or "in the background" to a routine's name and
Hark starts it, lets you carry on, and shows the result with a sound when it is done.

**Copying.** "Copy the address of this tab", "copy the path of the projects folder".

**Inside an app.** Hark can read the buttons, links, tabs and text boxes in an app's front window
and press one ("open the calculator and press eight plus four equals"). It can fill in a text box,
using only words you said. Buttons that send, post, submit, pay, join, merge or deploy ask first.
Buttons about deleting are blocked, and so are terminals and password boxes. This is the newest
part and has been tried on few apps.

**System settings.** Set the volume, mute or unmute, switch between light and dark appearance, and
lock the screen.

**Clipboard memory.** Hark remembers what you copy, up to 5000 entries by default. You can say
"paste the token I copied from the backend". The history is encrypted on disk with a key kept in a file only your
account can read. Clipboard text is never sent to any model.

**Routines.** Chores you do often, saved under a name and run by saying it: "stop port 8002",
"pull all", "is it up 5173". You write the steps yourself. See [Routines](#routines).

**Typing instead of speaking.** Tap the typing key (right Command unless you change it) and a small
bar opens where you type the same commands. It is a different key from the one you hold to speak,
so the two never get mixed up.

**Lists and "this".** "Open Slack and Linear", "hide Safari and Notes" and "quit Slack and Linear" are done by rule
when each name matches clearly (quitting and closing ask once for the whole list). "Close this tab", "close this
window" and "hide this app" mean the one in front. Anything less certain goes to the model as before.

**Window layout.** "Put Chrome on the left and VS Code on the right", "snap this window to the left",
"put Safari on the right third" and "make this window full size" move windows by rule, with "undo that" putting
them back. Halves, corners, thirds, centre and full are understood; an app that is not running goes to the model.

**Doing something in an app.** Say "open Notes and create a new note", "open Safari and new window" or
"open Finder and new window". Hark opens the app, reads its menu bar and chooses the one item that fits
what you said ("create a note" finds File, New Note), all by rule, so it needs no model and takes a
fraction of a second after the app is open. If nothing fits it says so; if two fit it lists them; if the
item is greyed out it tells you. It never chooses items about closing, quitting or deleting, and never
in a terminal. Only what is in the app's menus is reachable this way; a button that exists only inside a
window still goes to the model.

**Working in the app in front.** With an app already open you do not need to name it. "New window",
"print this" or "zoom in" choose the matching menu item. "Click send", "open my personal DM" or "go to
the calendar" press the button, tab or list item whose label fits. Hark does this by rule and only
when one thing clearly fits; otherwise it falls back to the model as before. Anything about sending,
posting, paying or leaving asks first, and anything about deleting is refused. How much of a window Hark
can see depends on the app: Mac apps show everything, while apps built on web technology (Teams, Slack,
VS Code) show what they choose to, and some show little.

**Backup models.** Hark does not stop when one model fails. It tries, in order, the online model you set
up, then an AI tool already on your Mac (Claude Code is found automatically), then the model on this
Mac. A model that is out of quota rests for a few minutes instead of making every command wait, and
Settings, Understanding, "Order Hark tries" shows which are ready and which are resting. Each command in
History says which model answered. An AI tool on the Mac is started when you press the key and kept running, so a
command that needs it takes a couple of seconds once it is warm (measured: about 1.9 s on one Mac, against 7 to 10 s
when a new program was started for each question). Under Understanding you can choose which of its models
Hark asks (Haiku, the fastest, is the default), and turn any model off or move it in the order.

**Learning.** Hark sets itself up and offers shortcuts so you do not have to fill in the Folders, Names,
Web pages and Routines screens by hand. On the first run it looks for your project folders. After
that it notices which apps and websites you open together, which sites you visit on many days, and
commands it misheard that you then said another way, and offers each as a card in Settings, Learning:
Add, Not now (asks again in two weeks) or Never. It remembers names only, on this Mac, and you can turn
it off or delete what it noted there. When a command fails, the model you set up can also guess what
you meant; Hark tries the guess out first and shows it only if it works. A "This was wrong" report in
History that says what you wanted becomes a suggestion too. See [SAFETY.md](../SAFETY.md).

**Dictation.** Choose a key under Settings, General, "Key to hold for dictation" (it is off until you
do). Click where you want text, hold the key, say what you want written, and let go: Hark types your
words where the cursor is, in any app, using the speech model on your Mac, so there is no limit on how
much you dictate. It removes "um" and "uh", flattens line breaks and capitalises the first letter, and
that is all: no model rewrites your words. It only presses letter keys: never Return, so nothing is
sent or run. It refuses when a password field is selected. If nothing that takes text is selected (or the page
in front has no text box), the words are copied to the clipboard instead of being lost: the pill says so, and
you paste them with ⌘V. "Copy last dictation" in the menu bar menu copies the last one again.
To keep talking with no key held, tap the dictation key twice quickly: a stop button appears next to the
waveform, and one more tap of the key (or the stop button) types what you said. The ✕ cancels either way.
While you hold the key a small pill with a waveform shows in the top-right corner, so it stays out of
the way of what you are writing. Drag it anywhere and Hark remembers the spot; the ✕ cancels.

## Safety

- Hark cannot delete, move, rename or overwrite files, and cannot empty the trash.
- It does not run commands, scripts or programs a model chose. The only commands it runs are the routines you wrote yourself. It presses shortcuts and buttons, never in a terminal, and types only words you said.
- It never reads the contents of your files, and your clipboard never goes to a model.
- It will not open a web address you did not name or that is not already open in a tab.
- Closing, quitting, and buttons that send, pay or submit always ask first.

Read [SAFETY.md](../SAFETY.md) for the full list.

## Requirements

- A Mac with Apple silicon (M1 or newer)
- macOS 26
- Apple's Command Line Tools (this gives you the Swift compiler). Install them with
  `xcode-select --install`. Full Xcode is not needed.
- About 1 GB of free disk space for the speech model
- Google Chrome and Visual Studio Code, for the browser tab and editor window features. Hark works
  without them, but those parts will not.

## Install

```sh
git clone <this repository's address>
cd hark
scripts/install.sh
```

The script builds Hark, signs it, copies it to `~/Applications/Hark.app` and starts it. Look for the
waveform icon in the menu bar. If you have no settings file yet, it creates
`~/.config/hark/config.json` from `examples/config.json`.

### Permissions

macOS asks for these. You can change them later in System Settings, and the Permissions tab of
Hark's settings window shows which are on.

- **Microphone**: to hear you while you hold the key. Speech is turned into text on your Mac.
- **Accessibility**: to notice the key you hold, read window titles, and use menus and shortcuts.
- **Automation for Google Chrome**: to see and switch your browser tabs.
- **Automation for System Events**: to change light and dark appearance and to lock the screen.

### First run

- The first time Hark starts, it downloads its speech model (Parakeet, about 450 MB) and prepares it
  for your Mac. This can take several minutes. Until it is ready, Hark uses Apple's own speech
  recogniser, which is less accurate with names and accents.
- Hark is signed with a certificate that `scripts/make-cert.sh` creates on your own Mac, named
  "Hark Dev". It is not signed by Apple. There is no paid Apple developer account behind this
  project, and only a paid account can sign an app in a way macOS trusts by default. So macOS may
  warn you the first time you open Hark. The same certificate is used for every build, which is what
  lets macOS keep the permissions you gave. You can read the build steps in `scripts/bundle.sh`.

## Using Hark

- **Speak**: hold the key (right Option by default), say the command, release. You see what Hark
  heard and what it did in a small overlay.
- **Type**: tap the key quickly (under a quarter of a second) or choose "Type a command" in the
  menu bar menu.
- **Yes or no questions**: when Hark asks, press 1 for yes or 2 for no. Escape cancels. When Hark is
  not sure which of several things you meant, it lists them with numbers, and you press the number.
- **Undo**: say "undo that" to put back the last thing Hark did, where it can be put back.
- **Menu bar icon**: shows how to use Hark or what it is waiting for, your last command, "Type a
  command", Settings and Quit.
- **Settings window**, with five tabs:
  - General: the key to hold, the key to tap for typing and the key to hold for dictation (fn, left and right Option, Command and Control, right Shift and F13 to F15 are offered, apart from right Control, which Apple keyboards lack; a key already used by one of the three is greyed out in the others), starting
    Hark when you log in, the folders Hark can open by name, and projects you name often.
  - Permissions: which permissions are on, with buttons that open System Settings.
  - Understanding: the AI model, see below.
  - Names: your own words, such as "the backend" for a folder.
  - History: the commands you have run, with a filter for the ones that had problems.

You can also set any other modifier or function key by editing the settings file (`hotkey`).
The allowed names are `rightOption`, `leftOption`, `rightCommand`, `leftCommand`, `rightControl`,
`leftControl`, `rightShift`, `leftShift` and `f13` to `f20`.

## Routines

A routine is a chore you do often, saved under a name. Say or type the name, with or without
"run" in front, and Hark does its steps in order. You write routines yourself in
`~/.config/hark/config.json`:

```json
"routines": [
  {
    "name": "stop port",
    "steps": [
      { "shell": "lsof -ti :{arg} | xargs kill", "destructive": true }
    ]
  }
]
```

With this, "stop port 8002" asks "Run “stop port” (lsof -ti :8002 | xargs kill)?" and runs it
when you say yes. `examples/config.json` has three more: "branches", "pull all" and "is it up".

- A step is either `"shell"`, a command run by zsh in your home folder, or `"say"`, a Hark command
  done as if you had spoken it (`{ "say": "open the projects folder in VS Code" }`).
- `{arg}` in a shell step stands for the words you say after the name. They arrive as plain words
  and numbers, without punctuation. Do not put quotes around `{arg}`: Hark hands it over in a
  way that keeps it from being read as part of the command. A routine that uses `{arg}` and is
  named without one does nothing and says so.
- `{repo}` in a shell step repeats the step for each folder in `repos`, and the result has one
  short part for each.
- `"destructive": true` on a step makes Hark show that command and wait for your yes before the
  routine starts. Mark every step that stops, changes or removes something.
- `"timeout"` on a shell step is how many seconds it may take. Left out, it is 30.
- The steps run in order and stop at the first one that fails. Hark shows the routine's name and
  the last line the last command printed, such as "is it up: 200", or which step stopped and why.
- If you word it loosely ("can you stop whatever is on port 8002"), the model may pick the routine
  for you. Hark then always asks first. The model picks a routine by name and never sees or
  writes its steps.
- A `say` step can run another routine, up to three deep. A `say` step that needs a yes, such as
  quitting an app, stops the routine, because a routine cannot answer for you.
- After changing the file by hand, quit and reopen Hark so it reads the file again.

A routine can do anything you write in it, so treat one with the same care as any script.

## Choosing a model

Hark's built-in rules settle simple commands at once, with no model. When the rules are unsure, or a
command has several steps, Hark asks an AI model to work out what you meant and which tools to use.

It works with any OpenAI-compatible chat endpoint (the same kind of address many services and local
tools offer). Two common choices:

- **A model on your Mac through [Ollama](https://ollama.com).** This is the default:
  `qwen2.5:3b` at `http://127.0.0.1:11434/v1`. Install Ollama and run `ollama pull qwen2.5:3b`.
  Nothing leaves your Mac.
- **An online model with a key.** In Settings, Understanding, enter the address, model name and key
  of the service you use. Hark can also keep the local model as a backup for when the online one is
  slow or cannot be reached.

What is sent to an online model: the text of your command, and the names of open apps, windows and
tabs, your listed folders, matching file names and menu items. Check that service's terms, because
a free tier may use what it receives. Audio never leaves your Mac and neither does your clipboard.
Leave the model off (the toggle in Understanding) and Hark uses only its built-in rules.

Your settings are in `~/.config/hark/config.json`. Hark makes that file readable only by you,
because it can hold your model key. Never share or commit it. The key is stored there and nowhere
else.

## For developers

```sh
swift build                                  # build
scripts/test.sh                              # run the tests
scripts/run.sh                               # build, sign and start the app (debug)
.build/debug/hark --say "open Chrome" --dry  # work out a command, change nothing
.build/debug/hark --eval evals/developer-day.json
```

- Use `scripts/test.sh`, not plain `swift test`. With only the Command Line Tools installed, plain
  `swift test` cannot find Apple's Testing framework. The script adds the paths for it.
- Use `scripts/run.sh` (not the bare binary) whenever a macOS permission is involved, because
  permissions are tied to the app's signature.
- `--say "<command>" --dry` prints what Hark would do and the time each step took. Add `--yes` to
  answer a yes or no question as yes.
- `--eval <file>` runs a set of commands against a made-up desk and prints how many came out right.
  Add `--local` to use only the model on your Mac, and `--model <name>` to try a different one.
- `--say "<command>" --trace` also prints what the model and the tools said to each other, which is
  the quickest way to see why a command went wrong.
- `--tool <name> '<JSON>'` calls one of the model's tools directly, for example
  `--tool look_at_app '{"app":"Calculator"}'`.
- To try a routine without touching your own settings, point Hark at another home folder:
  `CFFIXED_USER_HOME=/some/folder .build/debug/hark --say "branches"` reads
  `/some/folder/.config/hark/config.json` and keeps its history there too. With `--dry` a routine
  runs nothing and prints "Would run" and each command.

Folder layout:

- `Sources/HarkCore`: the parts with no macOS dependence: settings, command parser, matcher,
  safety rules, clipboard store, undo.
- `Sources/HarkMac`: everything that touches the Mac: hotkey, speech, overlay, settings window,
  sources of apps, windows, Chrome tabs and files, and the tools the model can call.
- `Sources/Hark`: the program entry point and command-line flags.
- `Tests/HarkCoreTests`: unit tests.
- `scripts`: build, sign, install and test scripts. `examples`: a sample settings file.
  `evals`: the evaluation set.

## Limits

- English only.
- Tabs and editor windows work in Google Chrome and Visual Studio Code only.
- It is early software and has been used by one person on one Mac.
- A command with a deletion word in it (delete, erase, wipe, shred, trash, bin, uninstall, format)
  is refused before anything else, unless it is the name of a routine you wrote. Such a routine
  always asks before it runs.
- The evaluation set is 43 commands run against an invented desk, so it checks whether Hark picks
  the right action, not how it does with your voice, your accent or your apps. On 10 October 2026 an
  online model (two Gemini Flash-Lite models asked together) got 42 of the 43 right, and two models
  small enough to run beside everything else on a 16 GB Mac (qwen2.5 3b and 7b through Ollama) each
  got 34. The set was written after those phrasings had been fixed, so read these as "nothing has
  regressed", not as how often Hark is right. Run `hark --eval` to see the score for your model.
  Later the same day the set had grown to 51 commands. With no model at all (`--rules-only`) the rules
  alone settled 39 of them (76 percent). With Claude Code (Haiku) as the only working model it was 51 of
  51, with a median of 0.0 s because most are settled by rule, and a slowest of 6.7 s for one that needed
  the model. One run on one Mac, so a guide to what changed, not a promise.
- Understanding hard commands needs a capable model. The small local models tested misread
  commands with "all" and "except" badly enough that Hark does not let a local stand-in propose
  anything that closes or quits. Simple commands work with no model at all.
- Ready-made routines: Settings, under Routines, offers a starter set (branches, changes, pull all,
  is it up, what is on port, stop port, containers, my reviews, my pull requests, build status, and
  "ask claude", which hands your words to the Claude Code command-line tool). The GitHub ones need
  the `gh` tool and "ask claude" needs `claude`, each signed in already. A tool started this way
  acts with its own permissions, not Hark's.
- When a command goes wrong, mark it in Settings under History with "This was wrong". The marked
  commands are listed by `hark --wrong`, so they can be turned into test cases.
- A model can still misread a command. SAFETY.md lists what Hark does not protect against.

## Licence and credits

Hark is released under the MIT licence: see [LICENSE](../LICENSE).

Speech recognition uses the Parakeet model from NVIDIA (CC-BY-4.0) through the FluidAudio package
(Apache License 2.0). See [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
