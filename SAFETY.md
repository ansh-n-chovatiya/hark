# What Hark can and cannot do

Hark hears a spoken command and acts on your Mac. A model reads the command and chooses the
actions, and models make mistakes: a word is misheard, a sentence is misread, a web page hides
text meant to mislead it. So Hark's safety does not rest on the model behaving. It rests on what
the tools are able to do, whatever the model asks for.

## Never
No tool exists for these, and none is to be added.

- Delete, move, rename or overwrite a file or folder, or empty the trash.
- Run a command, a script, an installer or a program that a model chose. Hark does not type, so
  it cannot type one either: it presses keyboard shortcuts only, and sends nothing at all to a
  terminal. It will not open a file that would run when opened. The one way Hark runs commands
  is a routine, and every command in a routine is one you wrote yourself in your settings file.
  The one routine Hark writes for you is a saved setup, and it holds only steps that open an
  app or a folder by name, built by fixed rules from what is open, never by a model.
  A model can pick which of your routines to run and pass along words you said. It cannot write
  or change a step.
- Read the contents of your files. It knows file names, not what is in them.
- Send what you copied to any model, local or hosted. Clipboard history stays on the Mac.
- Choose a menu item or press a shortcut that is about deleting, discarding, clearing or resetting.
- Type anything other than words you said. When Hark fills in a text box it uses your own words,
  never something it read elsewhere, and never into a password box.
- Open a web address you did not name. An address must match a site you said, carry only words
  you said, or already be open in a tab. This is what stops a page from tricking Hark into
  sending your data somewhere.

- Close, hide or quit itself. Hark is never on the list of things a command can act on, so
  "quit everything" leaves it running. Only you quit Hark, from its menu.

A spoken command that asks to delete something is refused before any model sees it. The one
exception is a routine you wrote and named that way yourself, such as one that empties the trash:
saying its name runs it, and it always asks first.

## Only after you say yes
Hark shows exactly what it is about to do and waits.

- Closing a window or a tab.
- Quitting an app.
- A menu item or shortcut that closes, quits, logs out, shuts down or restarts.
- Pressing a button inside an app that sends, posts, submits, pays, joins, merges, deploys or
  otherwise cannot simply be put back.
- A routine with a step you marked as destructive. The question quotes that step's command.
- Any routine a model picked for you, marked or not. A wrong pick then costs a keypress and
  nothing else.

This applies every time, including when you named the thing outright.

## Freely
These can be put back, usually with "undo that".

- Bring an app, window or tab to the front, or hide an app.
- Open an app, a file, a folder or a new tab.
- Choose any other menu item, press any other shortcut, or press any other button, in an app that
  is not a terminal.
- Change the volume, mute, and light or dark appearance. Lock the screen.
- Move and resize a window. Open a web page you saved under a name.
- Copy the name, address or path of something that is open, so you can paste it.
- Paste something you copied earlier.
- Run a routine you named outright, when none of its steps is marked as destructive. What a
  routine did is not put back by "undo that".

## Routines
A routine is a list of steps you wrote in your settings file under a name. It is the only way
Hark runs commands.

- Every command is your own text, run as you wrote it. No model writes, changes or adds to one.
- Words you say after a routine's name are handed to the command as plain words and numbers,
  kept apart from the command itself, so they are never read as part of it.
- A routine stops at the first step that fails or takes too long.
- A routine cannot answer a yes or no question for you. A step that would close or quit
  something stops the routine.
- A routine can do anything its author wrote, including deleting files. Read one before you add
  it, as you would any script, and mark each step that stops, changes or removes something as
  destructive so that Hark asks first.

## Limits on a single command
- At most twelve actions.
- At most six rounds of thinking by the model.

## What leaves your Mac
Speech is turned into text on the Mac. If you set up a hosted model, the text of your command
and the names of open apps, windows, tabs, your listed folders, matching file names, menu
items and your routines (their names, never their commands) go to that service so it can decide
what to do. Check that service's terms: a free tier
may use what it receives. With only a local model set up, nothing leaves the Mac.

## What this does not protect against
- An action that is allowed but not what you meant, such as opening the wrong file. The fix is
  "undo that".
- Unsaved work in an app you agreed to quit. The app's own save prompt is the last line there.
- A routine doing what its steps say. Hark does not judge the commands you put in one.
- Other software on your Mac. Hark's history and settings are files your account can read.

## Permissions Hark asks for, and why
- Microphone: to hear you while its key is held. Speech is turned into text on the Mac, so no separate speech permission is asked for.
- Accessibility: to notice its key, see window titles, and use menus and shortcuts.
- Automation for Google Chrome: to see and switch tabs.
- Automation for System Events: to change light and dark appearance and lock the screen.

If you find a way to make Hark do something on the Never list, that is a bug worth reporting.
