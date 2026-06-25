# Contributing to multi-claude

Thanks for your interest in improving these tools! This is a small project, so
the process is light — but a few notes will keep things smooth.

## Scope

multi-claude is a set of **macOS** companion tools for Claude Code:
`claude-acct`, `claude-usage`, and the ClaudeUsage desktop widget. Contributions
that fit that scope are welcome; anything that pulls the project away from "small,
dependency-light, read-only against your own accounts" is likely out of scope —
open an issue to discuss before investing in it.

## Ground rules

- **No third-party dependencies.** `claude-usage` uses only the Python 3 standard
  library; `claude-acct` is plain zsh. Keep it that way — it's part of why these
  are trivial to install.
- **macOS-first.** The tools rely on the macOS Keychain (`security`) and a native
  SwiftUI app. PRs don't need to support other platforms, but shouldn't break the
  macOS path.
- **Never commit personal data.** No real emails, account labels, absolute home
  paths, or tokens. Accounts come from the user's config file
  (`~/.config/claude-acct/accounts`) — see `accounts.example`.
- **Keep the two tools in sync.** `claude-acct` and `claude-usage` read the *same*
  account file. A change to the config format must be made in both.

## Getting set up

1. Fork and clone the repo.
2. Copy the account config and add at least one account:
   ```sh
   mkdir -p ~/.config/claude-acct
   cp accounts.example ~/.config/claude-acct/accounts
   $EDITOR ~/.config/claude-acct/accounts
   ```
3. Symlink the scripts onto your `PATH` (or run them directly):
   ```sh
   ln -s "$PWD/claude-acct"  ~/.local/bin/claude-acct
   ln -s "$PWD/claude-usage" ~/.local/bin/claude-usage
   ```

## Before you open a PR

There's no test suite, so check your changes by hand:

```sh
zsh -n claude-acct                                            # shell syntax
python3 -c "import ast; ast.parse(open('claude-usage').read())"  # python syntax
claude-usage           # renders the terminal view
claude-usage --json    # valid JSON for the widget
./build-widget.sh      # if you touched the Swift widget (needs Xcode toolchain)
```

Point `$CLAUDE_ACCT_CONFIG` at a throwaway file to test config handling without
touching your real accounts.

## Style

- Match the surrounding code: the scripts favor short, commented blocks that
  explain *why*, not *what*.
- Keep commit messages and PRs focused — one logical change per PR.

## Reporting issues

Open a GitHub issue with your macOS version, the tool involved, what you expected,
and what happened. For `claude-usage`, the output of `claude-usage --json` (with
any tokens/emails redacted) is helpful.
