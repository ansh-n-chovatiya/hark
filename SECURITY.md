# Security Policy

Hark acts on your Mac from a spoken or typed command, so security reports are taken seriously.
What Hark is designed never to do is in [SAFETY.md](SAFETY.md); a way around any of it is a
vulnerability.

## Reporting a vulnerability

Report privately through GitHub: **Security tab → "Report a vulnerability"**. Do not put exploit
details, keys or clipboard contents in a public issue or pull request.

What to expect: an acknowledgement within 3 days, a first assessment within 7 days, and a fix or a clear
plan within 90 days. Reporters are credited in the release notes unless they ask not to be.

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
- The model key leaking out of the macOS Keychain or `~/.config/hark/config.json` (logs, history, overlays, crash output, the settings file).

## Supply chain

Hark has one third-party package, FluidAudio, pinned to an exact version (see `THIRD_PARTY_NOTICES.md`). Each
release lists it in a CycloneDX software bill of materials (`hark-sbom.cdx.json`), and the source zip built by
the release workflow carries a build provenance attestation: `gh attestation verify hark-source.zip --repo
ansh-n-chovatiya/hark`. The prebuilt app comes with a SHA-256 checksum and is signed with a certificate made on
the maintainer's Mac, not by Apple (see README).

## Supported versions

Only the latest release on `main` is supported.

## Secrets

The model key is kept in the macOS login Keychain (service `dev.hark.app`, account `model-key`), not in
the settings file. A key typed into `~/.config/hark/config.json` by hand is moved into the Keychain the next
time Hark starts, and the file is rewritten with an empty key. Never commit the settings file or any key. If
one leaks, revoke it with the provider first, then report it.
