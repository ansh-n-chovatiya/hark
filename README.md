<div align="center">

<img src="docs/banner.svg" alt="Hark: hold a key, say it, your Mac does it" width="100%">

<br>

![macOS](https://img.shields.io/badge/macOS-26%2B-black?logo=apple)
![Apple silicon](https://img.shields.io/badge/Apple%20silicon-M1%2B-555)
![Swift](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)
![Licence](https://img.shields.io/badge/licence-MIT-blue)
![Tests](https://img.shields.io/badge/tests-127%20passing-brightgreen)

**[Install](#-install-in-3-steps)** · **[What it can do](#-what-can-i-say)** · **[Safety](#-safety-first)** · **[Full guide](docs/GUIDE.md)** · **[Help](#-something-not-working)**

</div>

---

## 👋 What is Hark?

Hark is a tiny app that lives in the top bar of your Mac. **Press and hold a key, say what you want, let go**, and Hark does it. No clicking through windows, no hunting for that one browser tab.

> *"Switch to Chrome."* → Chrome comes to the front.
> *"Open the standup file in TextEdit."* → Done.
> *"Hide everything except Slack."* → Quiet desktop.

Prefer not to talk? **Tap the key and type** the same thing instead.

Want to write by voice? Choose a **dictation key** in Settings and Hark types what you say into any app, using the speech model on your Mac, so there is no limit on how much you dictate. Double-tap the key to keep talking hands-free.

Your voice is turned into text **on your Mac**. Your audio never leaves it.

## 🎙 How it works

| 1. Hold | 2. Speak | 3. Let go |
| :---: | :---: | :---: |
| Hold the **right Option** key | Say what you want | Hark shows what it heard and does it |

If it isn't sure which of several things you meant, it shows a numbered list. Press the number. If it is about to close or quit something, it **asks you first** (press **1** for yes, **2** for no).

## 💬 What can I say?

| You want to… | Say something like |
| --- | --- |
| Jump to an app, window or tab | "Switch to Chrome" · "Open the render logs tab" |
| Open files and folders | "Open the projects folder in VS Code" |
| Open several things at once | "Open Slack and Linear" |
| Tidy up | "Hide everything except Warp" |
| Close things (asks first) | "Quit Slack" · "Close the screen recorder tab" |
| Arrange windows | "Chrome on the left and the editor on the right" |
| Act in the app in front | "New window" · "Print this" · "Open my personal DM" |
| Do something in an app | "Open Notes and create a new note" · "Open Safari and new window" |
| Search the web | "Search for swift concurrency on Google" · "Open Chrome and search the weather in Pune" |
| Use menus and buttons | "Open a new window in Chrome" |
| Change settings | "Set the volume to 30 percent" · "Switch to dark mode" · "Lock the screen" |
| Copy and paste | "Copy the address of this tab" · "Paste the token I copied from the backend" |
| Save a workspace | "Save this setup as morning" → later, just say "morning" |
| Undo | "Undo that" |
| Local servers | "What's on 3000" · "Open localhost 5173" · "Tell me when 3000 is up" |
| Calendar (read-only) | "What's next" · "What's my day look like" · "Am I free at three" · "Join my next meeting" (asks first) |
| Quick answers | "What is 18 percent of 240" · "How many kilometres is 26 miles" · "Set a 10 minute timer" |
| Understand itself | "Why did you do that" · "That was wrong" · "Remember that as ..." · "What can I say" |
| Edit what you dictated | "Scratch that" · "Change their to there" · "Select last word" |
| Focus a project | "Focus on shop" (brings forward its windows and tabs) |
| Repeat | "Do that again" · "No, the other one" |

"This tab", "this app" and "that window" mean the one in front of you. Hark remembers your last three commands.

**Make it yours.** Give things your own names in Settings ("the task board" → your team's web page), and write **routines** for chores you repeat, like "pull all" or "is it up 5173". See the [full guide](docs/GUIDE.md#routines).

## 🛡 Safety first

Hark is built so that even if it misunderstands you, it **can't do real damage**. That's not a promise about behaviour; the abilities simply don't exist.

| Hark can never… | Hark always… |
| --- | --- |
| Delete, move, rename or overwrite your files | Shows what it's about to do before closing or quitting |
| Empty the trash | Asks before buttons that send, post, pay or submit |
| Run a terminal command without showing it to you and waiting for your yes (they run in a sandbox that cannot delete or move anything, and the switch is in Settings) | Keeps your clipboard on your Mac, away from every AI model |
| Read what's inside your files | Lets you say "undo that" where it can |
| Open a web address you didn't name | Locks your clipboard history with a key only your account can read |

**Hark learns your habits, on your Mac only.** It notices which apps and websites you use together and offers names and routines for you to accept. It is on by default and has one switch to turn it off: **Settings → Learning**.

Details: [SAFETY.md](SAFETY.md).

## 📦 Install in 2 steps

**You need:** a Mac with Apple silicon (M1 or newer), macOS 26, and about 1 GB of free space.

**1. Install Hark.** Open the **Terminal** app and paste:

```sh
curl -fsSL https://raw.githubusercontent.com/ansh-n-chovatiya/hark/main/scripts/get.sh | zsh
```

This downloads the latest release in seconds. No developer tools needed. Prefer a zip? Get `Hark-macos-arm64.zip` from the [latest release](https://github.com/ansh-n-chovatiya/hark/releases/latest), unzip it, move Hark to Applications, then right-click it and choose **Open** the first time.

<details>
<summary>Build it from source instead</summary>

```sh
xcode-select --install
git clone https://github.com/ansh-n-chovatiya/hark.git
cd hark
scripts/install.sh
```

</details>

**2. Say yes to the permission pop-ups.** Look for the waveform icon ⏺ in your menu bar.

| macOS asks for | Why |
| --- | --- |
| Microphone | To hear you while the key is held |
| Accessibility | To notice the key and read window titles |
1| Automation (your browser, System Events) | To switch browser tabs and change dark mode / lock screen |

> **First launch is slow.** Hark downloads its speech model (about 450 MB) once. It can take a few minutes; until then it uses Apple's built-in listening, which is less accurate with names and accents.
>
> **"Unidentified developer" warning?** Hark is signed with a certificate made on your own Mac, not by Apple. That is normal for free, self-built apps. Every step is readable in `scripts/bundle.sh`.

## 🗑 Uninstall

```sh
scripts/uninstall.sh            # removes the app, keeps your settings
scripts/uninstall.sh --purge    # removes everything, including what Hark learned and the model key
```

## 🧠 Does it need an AI model?

**No.** Most everyday commands are settled by built-in rules in a fraction of a second: opening and switching, search, volume, dark mode, window layout, "open an app and do something in it", lists like "open Slack and Linear". For harder, multi-step sentences Hark asks an AI model, and it keeps going if one fails. It tries, in this order (you can turn each off or move it, in **Settings → Understanding**):

1. **An online model** you set up: pick the service, enter your key, choose from the models it lists.
2. **An AI tool already on your Mac**, such as Claude Code, found automatically. It is used text-only, with all of its own tools off.
3. **A model on your own Mac**, through [Ollama](https://ollama.com). Nothing leaves your computer.

A model that fails, for example one out of quota, rests for a few minutes instead of making every command wait. Turn the model off and Hark still works for everyday commands. Your key is kept in the macOS Keychain.

## 🔧 Something not working?

| Problem | Try |
| --- | --- |
| Hark doesn't react to the key | **System Settings → Privacy & Security → Accessibility**, make sure Hark is on |
| It can't hear me | Same place, **Microphone** |
| Tabs aren't found | **Automation → Hark → your browser** must be on. Tabs work in browsers built on Chromium (Chrome, Brave, Edge, Arc and the like) |
| It misheard names | Wait for the speech model download to finish; add your own words in **Settings → Names** |
| It did the wrong thing | **Settings → History → "This was wrong"**, and tell us |
| macOS keeps asking for my password | When it asks to use the "Hark Dev" signing key (only while building from source) or the "model-key" Keychain item, choose **Always Allow** so it stops asking |
| I said it and nothing was typed | Dictation types only into a text box. With none selected, your words are copied: paste with ⌘V |

Hark is early software, English-only, and has so far been used on one Mac. Browser tabs are read in any Chromium-based browser (Hark finds the browsers on your Mac); Safari and Firefox tabs are not yet supported. Editor windows are found in any code editor that opens a folder as a project.

## 🧰 For developers

```sh
make build      # compile
make test       # run the 127 tests
make run        # build, sign and launch a debug copy
make eval       # score the 43-command evaluation set
```

Start with [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Changes are logged in [CHANGELOG.md](CHANGELOG.md). Security reports: [SECURITY.md](SECURITY.md).

## 📄 Licence and credits

MIT licensed: see [LICENSE](LICENSE). Speech recognition uses NVIDIA's Parakeet model (CC-BY-4.0) through the FluidAudio package (Apache 2.0). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
