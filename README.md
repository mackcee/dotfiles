# dotfiles

Charlie's config for Omarchy desktops and any Linux box: the same shell,
Neovim (LazyVim) and keybindings everywhere.

## New machine or VM (any distro, x86_64 or ARM)

    curl -fsSL https://raw.githubusercontent.com/mackcee/dotfiles/main/install.sh | bash

This installs the base tools, plus pinned Neovim, lazygit, starship, bat and
eza through mise. It links the shared config into place, backing up anything
it replaces to `~/.local/state/dotfiles/backup/`, and is safe to re-run.

## How it works

- `links.conf` lists what gets linked where, in layers:
  - `core`: every machine (Neovim, bash additions, git config)
  - `vm`: machines without Omarchy (Omarchy-style tmux, lazygit, starship)
  - `desktop`: Omarchy machines (only files changed from Omarchy's defaults)
  - `host:<name>`: one machine's own files (e.g. a laptop keyboard)
- The Omarchy desktops keep `~/dotfiles` in sync live through Syncthing, so an
  edit on one appears on the others within seconds. Theme changes follow too.
- An always-on Syncthing hub holds the only git copy. Once a day it commits
  any changes, runs a secret and privacy check, and pushes here.

## Everyday use

    dot track <path> [--layer core|desktop|host]   start syncing a config file or folder
    dot status                                     anything that needs attention
    dot link [--force]                             re-create links

Design: `docs/design.md`. Tests: `tests/run.sh` (bats + shellcheck in Docker) and
`tests/smoke.sh` (fresh Ubuntu, Debian, Fedora, Arch and Alpine containers).
