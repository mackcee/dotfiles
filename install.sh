#!/usr/bin/env bash
# Set up Charlie's dotfiles on this machine.
#
# Fresh machine (any Linux, no login needed):
#   curl -fsSL https://raw.githubusercontent.com/mackcee/dotfiles/main/install.sh | bash
# Machine that already has ~/dotfiles (e.g. via Syncthing):
#   ~/dotfiles/install.sh [--force] [--no-packages]
#
#   --force         replace links that point somewhere else (old ones are backed up)
#   --no-packages   don't install system packages
#
# Safe to re-run: it only changes what isn't already set up.
# Everything runs inside main(), so a partially downloaded script does nothing.

set -euo pipefail

_bootstrap_git() {
  command -v git >/dev/null 2>&1 && return 0
  local priv=""
  if [[ "${DOT_EUID:-$EUID}" != 0 ]]; then
    command -v sudo >/dev/null 2>&1 || { echo "dotfiles: git is missing and there is no sudo to install it" >&2; return 1; }
    priv=sudo
  fi
  if command -v pacman >/dev/null; then $priv pacman -Syu --needed --noconfirm git
  elif command -v apt-get >/dev/null; then $priv apt-get update -qq && $priv env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git ca-certificates
  elif command -v dnf >/dev/null; then $priv dnf install -y -q git
  elif command -v zypper >/dev/null; then $priv zypper -n install git
  elif command -v apk >/dev/null; then $priv apk add --no-cache git
  else echo "dotfiles: please install git first" >&2; return 1
  fi
}

main() {
  local self="${BASH_SOURCE[0]:-}" self_dir=""
  if [[ -n "$self" && -f "$self" ]]; then
    self_dir="$(cd "$(dirname "$self")" && pwd)"
  fi
  : "${DOTFILES_REPO:=https://github.com/mackcee/dotfiles.git}"
  : "${DOTFILES_DIR:=${self_dir:-$HOME/dotfiles}}"
  export DOTFILES_DIR DOTFILES_REPO

  if [[ ! -f "$DOTFILES_DIR/lib/install.sh" ]]; then
    if [[ -e "$DOTFILES_DIR" && -n "$(ls -A "$DOTFILES_DIR" 2>/dev/null)" ]]; then
      echo "dotfiles: $DOTFILES_DIR exists but isn't a dotfiles checkout; move it aside and re-run" >&2
      return 1
    fi
    _bootstrap_git
    echo "dotfiles: cloning $DOTFILES_REPO into $DOTFILES_DIR"
    git clone -q "$DOTFILES_REPO" "$DOTFILES_DIR"
    exec bash "$DOTFILES_DIR/install.sh" "$@"
  fi

  # shellcheck source=lib/links.sh
  source "$DOTFILES_DIR/lib/links.sh"
  # shellcheck source=lib/install.sh
  source "$DOTFILES_DIR/lib/install.sh"
  dot_install_main "$@"
}

main "$@"
