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
| Repeat | "Do that again" · "No, the other one" |

"This tab", "this app" and "that window" mean the one in front of you. Hark remembers your last three commands.

**Make it yours.** Give things your own names in Settings ("the task board" → your team's web page), and write **routines** for chores you repeat, like "pull all" or "is it up 5173". See the [full guide](docs/GUIDE.md#routines).

## 🛡 Safety first

Hark is built so that even if it misunderstands you, it **can't do real damage**. That's not a promise about behaviour; the abilities simply don't exist.

| Hark can never… | Hark always… |
| --- | --- |
| Delete, move, rename or overwrite your files | Shows what it's about to do before closing or quitting |
| Empty the trash | Asks before buttons that send, post, pay or submit |
| Run commands an AI wrote | Keeps your clipboard on your Mac, away from every AI model |
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
| Automation (Chrome, System Events) | To switch browser tabs and change dark mode / lock screen |

> **First launch is slow.** Hark downloads its speech model (about 450 MB) once. It can take a few minutes; until then it uses Apple's built-in listening, which is less accurate with names and accents.
>
> **"Unidentified developer" warning?** Hark is signed with a certificate made on your own Mac, not by Apple. That is normal for free, self-built apps. Every step is readable in `scripts/bundle.sh`.

## 🧠 Does it need an AI model?

**No.** Simple commands are handled by built-in rules instantly. For harder, multi-step sentences Hark can ask an AI model:

- **Private (default):** a model on your own Mac through [Ollama](https://ollama.com). Nothing leaves your computer.
- **Online:** enter a service's address, model name and key in **Settings → Understanding**.

Turn the model off and Hark still works for everyday commands.

## 🔧 Something not working?

| Problem | Try |
| --- | --- |
| Hark doesn't react to the key | **System Settings → Privacy & Security → Accessibility**, make sure Hark is on |
| It can't hear me | Same place, **Microphone** |
| Tabs aren't found | **Automation → Hark → Google Chrome** must be on. Tabs work in Chrome only |
| It misheard names | Wait for the speech model download to finish; add your own words in **Settings → Names** |
| It did the wrong thing | **Settings → History → "This was wrong"**, and tell us |

Hark is early software, English-only, and has so far been used on one Mac. Browser tabs and editor windows work with Google Chrome and Visual Studio Code only.

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
