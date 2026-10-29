<p align="center">
  <img src="assets/multiclaude_icon_mark.svg" alt="multi-claude" width="420">
</p>

# MultiClaude

A small set of macOS companion tools for [Claude Code](https://claude.com/claude-code):
run it under multiple accounts, keep an eye on each account's subscription
usage from the terminal or the desktop, and name every session so a wall of
terminal splits is readable.

| Tool | What it does |
| --- | --- |
| [`claude-acct`](#claude-acct) | Launch Claude Code under a chosen account (separate logins, shared skills). |
| [`claude-usage`](#claude-usage) | Show subscription usage (session / weekly / extra) for each account. |
| [`claude-statusline`](#claude-statusline) | Name each session after its repo, so a wall of terminal splits is readable. |
| [ClaudeUsage widget](#claudeusage-widget) | A translucent always-on-desktop panel rendering `claude-usage`. |

All three are read-only against your own Claude accounts. They read the OAuth
tokens Claude Code already stores in the macOS **Keychain** - nothing is sent
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
never drift. You don't have to create it yourself - the installer seeds it from
`accounts.example`, and `claude-acct` writes a starter on first run if it's
still missing. Either way, the file lands at
`~/.config/claude-acct/accounts`; open it and fill in your accounts:

```sh
$EDITOR ~/.config/claude-acct/accounts
```

One account per line - `<label>  <config_dir>  [email]`:

```
work       ~/.claude            you@work.example
personal   ~/.claude-personal   you@personal.example
```

- `label` - the short name you type (`claude-acct work`).
- `config_dir` - that account's `CLAUDE_CONFIG_DIR` (`~` and `$HOME` expand).
- `email` - optional, shown for context only.

The **first** account listed is the "primary": its `<config_dir>/skills` folder
is symlinked into the other accounts' config dirs, so every account sees the
same skills.

Override the location with `$CLAUDE_ACCT_CONFIG` if you don't want
`~/.config/claude-acct/accounts`.

### Single-account setup

You don't need multiple accounts (or `claude-acct` at all) to use
`claude-usage` and the widget. They read the OAuth token Claude Code already
stores when you run `/login` normally, so a regular single-account install works
fine. All you have to do is list that one account so `claude-usage` knows which
config dir to look up:

```
default  ~/.claude   you@example.com
```

Then log in with plain `claude` as usual and run `claude-usage` (or launch the
widget). `claude-acct` is only needed if you want to switch between several
logins; for one account it's optional.

## Install

`claude-usage` needs only Python 3 from the system - no third-party packages;
the widget build additionally needs the Xcode toolchain (`swiftc`).

### Automatic install

Run the interactive installer:

```sh
./install.sh
```

It links the two scripts onto your `PATH`, seeds the accounts config from
`accounts.example`, and (optionally) builds the desktop widget. It's
**idempotent** - safe to re-run; each step checks current state and only does
what's needed, and nothing is overwritten without asking. Useful flags:

```sh
./install.sh --yes            # non-interactive, accept defaults
./install.sh --bindir DIR     # link into DIR instead of ~/.local/bin
./install.sh --no-widget      # skip the widget build
./install.sh --uninstall      # remove the links it created
```

### Manual install

Prefer to do it by hand? The installer just automates these steps:

1. **Link the scripts onto your `PATH`** (any directory on `PATH` works;
   `~/.local/bin` is a common one):

   ```sh
   ln -s "$PWD/claude-acct"       ~/.local/bin/claude-acct
   ln -s "$PWD/claude-usage"      ~/.local/bin/claude-usage
   ln -s "$PWD/claude-statusline" ~/.local/bin/claude-statusline
   ```

2. **Seed the accounts config** - copy the example and edit it (see
   [Configuring accounts](#configuring-accounts)):

   ```sh
   mkdir -p ~/.config/claude-acct
   cp accounts.example ~/.config/claude-acct/accounts
   ```

3. **Point the status line at it** (optional - see
   [`claude-statusline`](#claude-statusline)) by adding this to each account's
   `<config_dir>/settings.json`:

   ```json
   "statusLine": { "type": "command", "command": "~/.local/bin/claude-statusline", "padding": 0 }
   ```

4. **Build the widget** (optional - see [ClaudeUsage widget](#claudeusage-widget)):

   ```sh
   ./build-widget.sh
   ```

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
claude-usage                 # colored bars in the terminal
claude-usage --json          # machine-readable, used by the widget
claude-usage --watch [SECS]  # full-screen view, refetches every SECS (default 300)
claude-usage --line [LABEL]  # one compact line, for a Claude Code status line
```

### In the terminal

`--line` prints one line for the current account (picked from
`$CLAUDE_CONFIG_DIR`, so it follows `claude-acct`) and caches results in
`~/.cache/claude-usage` for `$CLAUDE_USAGE_TTL` seconds (default 300). To show it
at the bottom of every Claude Code session, add this to each account's
`<config_dir>/settings.json`:

```json
"statusLine": { "type": "command", "command": "~/.local/bin/claude-usage --line", "padding": 0 }
```

Or use [`claude-statusline`](#claude-statusline) instead, which puts the
session's name in front of the same numbers.

Each account shows its session (5h), weekly, and (if enabled) extra-usage
limits with reset times. An account that isn't logged in, has an expired
session, or can't reach the API shows a warning with a hint instead of numbers.

## claude-statusline

A tab full of terminal splits all looks the same. This names each one:

```
▌ zng-api ⎇ main · work · 5h 12% ↻4h36m · wk 9% ↻2d
▌ zng-api/apps/core ⎇ release/4.2 · work · 5h 12% ↻4h36m · wk 9% ↻2d
▌ ontopo-crm ⎇ main · personal · 5h 3% ↻4h36m · wk 7% ↻2d
```

The name is the session's git repository, plus the path below its root when
the session sits in a subdirectory, followed by whatever `claude-usage --line`
prints. Nothing to configure - the installer offers to set it for every account
in your accounts file, keeping a `.bak` of each `settings.json`.

Why a status line rather than a terminal feature: no terminal will put a title
on a split. Ghostty has the actions for it - a split is a "surface" and
`prompt_surface_title` renames one - but a surface title only reaches the
window and tab title, and only while that split has focus. In a tab of four
splits you'd see one name: the one you're already looking at. A status line is
content *inside* the split, so every split shows its own, focused or not.

### Renaming a session

The repository is the right name almost always. When it isn't - two sessions in
one repo - rename one from inside it. `!` runs a shell command without spending
a model turn:

```
! claude-statusline -l payments hotfix   # rename this session
! claude-statusline -l                   # back to the repository name
! claude-statusline --show-label         # what's overriding it, if anything
```

The override is keyed by session id, so it reaches that session only, and never
leaks into another split. `CLAUDE_SPLIT_LABEL=payments claude` works too, if
you'd rather decide before you start.

### Appending something else

The trailing numbers are just whatever `claude-usage --line` prints. Point that
at something else, or switch it off:

```sh
export CLAUDE_STATUSLINE_SUFFIX_CMD="my-token-counter --compact"
export CLAUDE_STATUSLINE_SUFFIX_CMD=/dev/null   # name and branch only
```

A suffix command that's missing, slow or failing is left out rather than
breaking the line.

## ClaudeUsage widget

A borderless, translucent panel that sits on the desktop (no Dock icon),
shells out to `claude-usage --json` every 5 minutes, and renders the result.
It's draggable and account-agnostic - it just displays whatever
`claude-usage` reports.

To launch it at login, add `ClaudeUsage.app` to **System Settings → General →
Login Items**. The app looks for `claude-usage` on a standard `PATH`
(`~/.local/bin`, Homebrew, `/usr/bin`) or beside the app bundle.

## Contributing

Contributions are welcome - see [CONTRIBUTING.md](CONTRIBUTING.md) for scope,
ground rules, and how to test changes.

## License

[MIT](LICENSE)
