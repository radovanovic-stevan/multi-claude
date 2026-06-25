# multi-claude

A small set of macOS companion tools for [Claude Code](https://claude.com/claude-code):
run it under multiple accounts and keep an eye on each account's subscription
usage from the terminal or the desktop.

| Tool | What it does |
| --- | --- |
| [`claude-acct`](#claude-acct) | Launch Claude Code under a chosen account (separate logins, shared skills). |
| [`claude-usage`](#claude-usage) | Show subscription usage (session / weekly / extra) for each account. |
| [ClaudeUsage widget](#claudeusage-widget) | A translucent always-on-desktop panel rendering `claude-usage`. |

All three are read-only against your own Claude accounts. They read the OAuth
tokens Claude Code already stores in the macOS **Keychain** — nothing is sent
anywhere except Anthropic's own usage endpoint, the same one behind `/usage`.

> **Platform:** macOS only. The tools rely on the macOS Keychain (`security`)
> and the widget is a native AppKit/SwiftUI app.

## How it works

Claude Code keeps a separate login per `CLAUDE_CONFIG_DIR`, storing each in a
Keychain slot named `Claude Code-credentials-<sha256(config_dir)[:8]>`. So
"switching account" is just pointing `CLAUDE_CONFIG_DIR` at a different
directory. `claude-acct` does that, and also mirrors each login into a stable,
human-named slot (`Claude Code-credentials-<label>`) so `claude-usage` can find
it without depending on Claude's internal hashing.

## Configuring accounts

Both `claude-acct` and `claude-usage` read the **same** account file, so they
never drift. Copy the example and edit it:

```sh
mkdir -p ~/.config/claude-acct
cp accounts.example ~/.config/claude-acct/accounts
$EDITOR ~/.config/claude-acct/accounts
```

One account per line — `<label>  <config_dir>  [email]`:

```
work       ~/.claude            you@work.example
personal   ~/.claude-personal   you@personal.example
```

- `label` — the short name you type (`claude-acct work`).
- `config_dir` — that account's `CLAUDE_CONFIG_DIR` (`~` and `$HOME` expand).
- `email` — optional, shown for context only.

The **first** account listed is the "primary": its `<config_dir>/skills` folder
is symlinked into the other accounts' config dirs, so every account sees the
same skills.

Override the location with `$CLAUDE_ACCT_CONFIG` if you don't want
`~/.config/claude-acct/accounts`. If the file is missing, `claude-acct` writes a
starter for you on first run.

## Install

Put the two scripts on your `PATH`:

```sh
ln -s "$PWD/claude-acct"  ~/.local/bin/claude-acct
ln -s "$PWD/claude-usage" ~/.local/bin/claude-usage
```

(Any directory on your `PATH` works; `~/.local/bin` is just a common one.)
`claude-usage` needs only Python 3 from the system — no third-party packages.

## claude-acct

Launch Claude Code under a chosen account:

```sh
claude-acct work            # launch directly under "work"
claude-acct personal --foo  # any extra args are passed through to claude
claude-acct                 # no label → interactive menu
```

It exports `CLAUDE_CONFIG_DIR`, mirrors the login slot before and after the
session (to capture token refreshes), and shares the primary account's skills.

## claude-usage

Print usage for every configured account:

```sh
claude-usage           # colored bars in the terminal
claude-usage --json    # machine-readable, used by the widget
```

Each account shows its session (5h), weekly, and (if enabled) extra-usage
limits with reset times. An account that isn't logged in, has an expired
session, or can't reach the API shows a warning with a hint instead of numbers.

## ClaudeUsage widget

A borderless, translucent panel that sits on the desktop (no Dock icon),
shells out to `claude-usage --json` every 5 minutes, and renders the result.
It's draggable and account-agnostic — it just displays whatever
`claude-usage` reports.

Build it (requires the Xcode toolchain / `swiftc`):

```sh
./build-widget.sh        # compiles widget/ClaudeUsageWidget.swift -> ClaudeUsage.app
open ClaudeUsage.app
```

To launch it at login, add `ClaudeUsage.app` to **System Settings → General →
Login Items**. The app looks for `claude-usage` on a standard `PATH`
(`~/.local/bin`, Homebrew, `/usr/bin`) or beside the app bundle.

## License

[MIT](LICENSE)
