#!/bin/zsh
# install.sh — interactive, idempotent installer for MultiClaude.
#
# Sets up the macOS companion tools for Claude Code:
#   1. links `claude-acct` and `claude-usage` onto your PATH
#   2. seeds the accounts config (~/.config/claude-acct/accounts)
#   3. optionally builds the ClaudeUsage desktop widget
#
# Safe to run repeatedly: every step checks current state first and only does
# work that's actually needed. Nothing is overwritten without asking.
#
# Usage:
#   ./install.sh                 # interactive
#   ./install.sh --yes           # non-interactive, accept all defaults
#   ./install.sh --bindir DIR    # install links into DIR (default ~/.local/bin)
#   ./install.sh --no-widget     # skip the widget build
#   ./install.sh --uninstall     # remove what this installer created
#   ./install.sh --help

# Guard: this script uses zsh-only syntax. The shebang runs it under zsh, but
# catch the case where someone invokes it as `bash install.sh` / `sh install.sh`
# and bail with a clear message instead of a cryptic parse error. (POSIX-only
# syntax here so bash 3.2 reaches this check before hitting any zsh-isms.)
if [ -z "${ZSH_VERSION:-}" ]; then
  echo "install.sh must run under zsh (it's the macOS default)." >&2
  echo "Run it directly:  ./install.sh   (not 'bash install.sh')." >&2
  echo "Or explicitly:    zsh install.sh" >&2
  exit 1
fi

set -e
emulate -L zsh
setopt no_unset pipe_fail

SELF="${0:A}"             # absolute path of this script
REPO="${SELF:h}"          # absolute dir of this script (the repo root)

# ---- options ---------------------------------------------------------------
BINDIR_DEFAULT="$HOME/.local/bin"
BINDIR="$BINDIR_DEFAULT"
ASSUME_YES=0
DO_WIDGET=auto            # auto | yes | no
UNINSTALL=0

usage() {
  sed -n '2,20p' "$SELF" | sed 's/^# \{0,1\}//'
  exit 0
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes|-y)      ASSUME_YES=1 ;;
    --bindir)      shift; BINDIR="${1:?--bindir needs a directory}" ;;
    --bindir=*)    BINDIR="${1#--bindir=}" ;;
    --widget)      DO_WIDGET=yes ;;
    --no-widget)   DO_WIDGET=no ;;
    --uninstall)   UNINSTALL=1 ;;
    --help|-h)     usage ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done
BINDIR="${BINDIR/#\~/$HOME}"

# ---- output helpers --------------------------------------------------------
if [ -t 1 ]; then
  C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'
  C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_BLUE=$'\e[34m'; C_RED=$'\e[31m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_RED=""
fi

info()  { print -r -- "${C_BLUE}•${C_RESET} $*"; }
ok()    { print -r -- "${C_GREEN}✓${C_RESET} $*"; }
warn()  { print -r -- "${C_YELLOW}!${C_RESET} $*" >&2; }
err()   { print -r -- "${C_RED}✗${C_RESET} $*" >&2; }
head()  { print; print -r -- "${C_BOLD}$*${C_RESET}"; }

# ask "Question?" default(y/n) -> returns 0 for yes, 1 for no
ask() {
  local prompt="$1" def="${2:-y}" reply
  if [ "$ASSUME_YES" -eq 1 ] || [ ! -t 0 ]; then
    [ "$def" = "y" ]; return
  fi
  local hint="[Y/n]"; [ "$def" = "n" ] && hint="[y/N]"
  read -r "reply?${prompt} ${hint} "
  reply="${reply:-$def}"
  [[ "$reply" == [Yy]* ]]
}

# ask_value "Prompt" "default" -> echoes chosen value
ask_value() {
  local prompt="$1" def="$2" reply
  if [ "$ASSUME_YES" -eq 1 ] || [ ! -t 0 ]; then
    print -r -- "$def"; return
  fi
  read -r "reply?${prompt} [${def}]: "
  print -r -- "${reply:-$def}"
}

# ---- platform / prereq checks ---------------------------------------------
preflight() {
  head "Checking prerequisites"
  if [ "$(uname -s)" != "Darwin" ]; then
    err "MultiClaude is macOS-only (it relies on the macOS Keychain). Aborting."
    exit 1
  fi
  ok "macOS detected"

  if command -v python3 >/dev/null 2>&1; then
    ok "python3 found ($(command -v python3)) — required by claude-usage"
  else
    err "python3 not found. Install it (e.g. \`xcode-select --install\`) and re-run."
    exit 1
  fi

  if command -v swiftc >/dev/null 2>&1; then
    ok "swiftc found — widget build available"
  else
    warn "swiftc not found — the desktop widget can't be built (Xcode toolchain needed)."
    [ "$DO_WIDGET" = "auto" ] && DO_WIDGET=no
    [ "$DO_WIDGET" = "yes" ] && { err "--widget requested but swiftc is missing."; exit 1; }
  fi
}

# ---- step: link scripts onto PATH -----------------------------------------
SCRIPTS=(claude-acct claude-usage)

link_one() {
  local name="$1"
  local target="$REPO/$name"
  local link="$BINDIR/$name"

  if [ ! -f "$target" ]; then
    err "missing source script: $target"; return 1
  fi
  [ -x "$target" ] || chmod +x "$target"

  if [ -L "$link" ]; then
    local cur; cur="$(readlink "$link")"
    if [ "$cur" = "$target" ] || [ "${link:A}" = "$target" ]; then
      ok "$name already linked"
      return 0
    fi
    warn "$link is a symlink to: $cur"
    ask "  Repoint it at this repo?" y || { info "left $name unchanged"; return 0; }
    rm -f "$link"
  elif [ -e "$link" ]; then
    warn "$link exists and is not a symlink."
    ask "  Replace it with a link into this repo?" n || { info "left $name unchanged"; return 0; }
    rm -f "$link"
  fi

  ln -s "$target" "$link"
  ok "linked $name -> $link"
}

install_links() {
  head "Linking scripts onto PATH"
  BINDIR="$(ask_value "Install directory for the scripts" "$BINDIR")"
  BINDIR="${BINDIR/#\~/$HOME}"
  mkdir -p "$BINDIR"

  local s
  for s in "${SCRIPTS[@]}"; do link_one "$s"; done

  # PATH hint
  case ":$PATH:" in
    *":$BINDIR:"*) ok "$BINDIR is already on your PATH" ;;
    *)
      warn "$BINDIR is not on your PATH."
      local rc="$HOME/.zshrc"
      info "Add it with:"
      print -r -- "    ${C_DIM}echo 'export PATH=\"$BINDIR:\$PATH\"' >> $rc${C_RESET}"
      ;;
  esac
}

# ---- step: accounts config -------------------------------------------------
accounts_setup() {
  head "Accounts configuration"
  local cfg="${CLAUDE_ACCT_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/claude-acct/accounts}"

  if [ -f "$cfg" ]; then
    ok "accounts file already exists: $cfg (left untouched)"
    return 0
  fi

  mkdir -p "${cfg:h}"
  cp "$REPO/accounts.example" "$cfg"
  ok "created $cfg from accounts.example"
  info "Edit it to list your accounts: ${C_DIM}<label>  <config_dir>  [email]${C_DIM}"

  if ask "Open it in \$EDITOR now?" n; then
    "${EDITOR:-vi}" "$cfg"
  fi
}

# ---- step: widget ----------------------------------------------------------
widget_build() {
  head "Desktop widget"
  if [ "$DO_WIDGET" = "no" ]; then
    info "skipping widget build"
    return 0
  fi
  if [ "$DO_WIDGET" = "auto" ]; then
    ask "Build the ClaudeUsage desktop widget now?" y || { info "skipping widget build"; return 0; }
  fi

  "$REPO/build-widget.sh"
  ok "built $REPO/ClaudeUsage.app"
  info "Launch it with: ${C_DIM}open '$REPO/ClaudeUsage.app'${C_RESET}"
  info "Run at login: add it under System Settings → General → Login Items"
}

# ---- uninstall -------------------------------------------------------------
do_uninstall() {
  head "Uninstalling MultiClaude"
  local s link
  for s in "${SCRIPTS[@]}"; do
    link="$BINDIR/$s"
    if [ -L "$link" ] && [ "${link:A}" = "$REPO/$s" ]; then
      rm -f "$link"; ok "removed link $link"
    else
      info "no link to remove for $s in $BINDIR"
    fi
  done

  if [ -d "$REPO/ClaudeUsage.app" ] && ask "Remove the built widget ($REPO/ClaudeUsage.app)?" n; then
    rm -rf "$REPO/ClaudeUsage.app"; ok "removed ClaudeUsage.app"
  fi

  local cfg="${CLAUDE_ACCT_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/claude-acct/accounts}"
  if [ -f "$cfg" ]; then
    info "left accounts file in place: $cfg"
    info "remove it manually if you want a clean slate."
  fi
  ok "Done."
  exit 0
}

# ---- main ------------------------------------------------------------------
print -r -- "${C_BOLD}MultiClaude installer${C_RESET}  ${C_DIM}($REPO)${C_RESET}"

[ "$UNINSTALL" -eq 1 ] && { BINDIR="${BINDIR/#\~/$HOME}"; do_uninstall; }

preflight
install_links
accounts_setup
widget_build

head "All set."
ok  "Try it:  ${C_DIM}claude-usage${C_RESET}   then   ${C_DIM}claude-acct${C_RESET}"
