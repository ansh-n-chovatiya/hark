# Security Policy

Hark acts on your Mac from a spoken or typed command, so security reports are taken seriously.
What Hark is designed never to do is in [SAFETY.md](SAFETY.md); a way around any of it is a
vulnerability.

## Reporting a vulnerability

Report privately through GitHub: **Security tab → "Report a vulnerability"**. Do not put exploit
details, keys or clipboard contents in a public issue or pull request.

Useful reports include:

- What an attacker can do (which action, with what input) and the preconditions.
- Steps to reproduce, ideally with `hark --say "<command>" --dry --trace`.
- The commit or version (`CFBundleShortVersionString` in the built app).

## In scope

- Any path that deletes, moves, renames or overwrites files, empties the trash, or runs a command
  a model wrote (SAFETY.md, "Never").
- Prompt injection through window titles, tab titles, file names or page text that makes Hark act
  without the confirmation it should have asked for.
- Clipboard text reaching any model, or the clipboard history being readable without the key.
- The model key leaking out of `~/.config/hark/config.json` (logs, history, overlays, crash output).

## Supported versions

Only the latest release on `main` is supported.

## Secrets

Never commit `~/.config/hark/config.json` or any model key. If one leaks, revoke it with the
provider first, then report it.
