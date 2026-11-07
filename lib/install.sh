# shellcheck shell=bash
# Installer steps. Sourced by install.sh after lib/links.sh.

dot_pkg_manager() {
  local pm
  for pm in pacman apt-get dnf zypper apk; do
    if command -v "$pm" >/dev/null 2>&1; then
      echo "${pm%-get}"
      return 0
    fi
  done
  echo none
}

# Prints the privilege prefix to use ("" as root, "sudo" otherwise).
# Fails when not root and sudo is unavailable, or when there is no terminal to
# type a password into and sudo would need one.
dot_priv() {
  if [[ "${DOT_EUID:-$EUID}" == 0 ]]; then
    echo ""
  elif command -v sudo >/dev/null 2>&1 && { [[ -t 0 ]] || sudo -n true 2>/dev/null; }; then
    echo sudo
  else
    return 1
  fi
}

# True when everything the base package step would install is already here.
dot_base_tools_present() {
  local c
  local -a need=(git curl unzip tar gzip make cc rg tmux)
  dot_is_musl && need+=(nvim node)
  for c in "${need[@]}"; do command -v "$c" >/dev/null 2>&1 || return 1; done
  command -v fd >/dev/null 2>&1 || command -v fdfind >/dev/null 2>&1
}

# dot_install_packages <pm> <priv>
dot_install_packages() {
  local pm=$1 priv=$2
  local -a p=()
  [[ -n "$priv" ]] && p=("$priv")
  echo "dotfiles: installing base packages with $pm"
  case "$pm" in
    pacman)
      # Full sync: Arch doesn't support partial upgrades, and fresh images have no package lists.
      "${p[@]}" pacman -Syu --needed --noconfirm git curl unzip tar gzip gcc make ripgrep fd tmux bash-completion
      ;;
    apt)
      "${p[@]}" apt-get update -qq
      "${p[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        git curl ca-certificates unzip tar gzip xz-utils build-essential ripgrep fd-find tmux bash-completion
      if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
      fi
      ;;
    dnf)
      "${p[@]}" dnf install -y -q git curl unzip tar gzip xz gcc make ripgrep fd-find tmux bash-completion
      ;;
    zypper)
      "${p[@]}" zypper -n install git curl unzip tar gzip xz gcc make ripgrep fd tmux bash-completion
      ;;
    apk)
      # musl: upstream Neovim/Node builds are glibc-only, so take them from apk (mise skips them).
      "${p[@]}" apk add --no-cache git curl unzip tar gzip xz build-base ripgrep fd tmux bash bash-completion \
        neovim nodejs npm
      ;;
    *)
      echo "dotfiles: no known package manager; install git, curl, ripgrep, fd and tmux yourself"
      ;;
  esac
}

dot_is_musl() {
  compgen -G '/lib/ld-musl-*' >/dev/null
}

# Install mise (if needed) and the tools pinned in ~/.config/mise/config.toml.
dot_install_mise() {
  export PATH="$HOME/.local/bin:$PATH"
  # Upstream Neovim and Node builds don't run on musl; those come from apk instead.
  dot_is_musl && export MISE_DISABLE_TOOLS=neovim,node
  if ! command -v mise >/dev/null 2>&1; then
    echo "dotfiles: installing mise"
    mkdir -p "$HOME/.local/bin"
    curl -fsSL https://mise.run | MISE_INSTALL_PATH="$HOME/.local/bin/mise" sh
  fi
  echo "dotfiles: installing pinned tools with mise"
  MISE_YES=1 mise install
}

# Omarchy owns ~/.bashrc; add a single line that loads Charlie's additions.
dot_bash_hook() {
  local rc="$HOME/.bashrc" line
  line="[ -r $(printf '%q' "$DOTFILES_DIR/core/bash/personal.bash") ] && . $(printf '%q' "$DOTFILES_DIR/core/bash/personal.bash")"
  touch "$rc"
  grep -qxF "$line" "$rc" || printf '\n# dotfiles\n%s\n' "$line" >>"$rc"
}

# Watch the synced theme file and apply theme changes from other machines.
dot_theme_sync_enable() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload || true
    systemctl --user enable --now dotfiles-theme.path || echo "dotfiles: could not enable dotfiles-theme.path"
  fi
  "$DOTFILES_DIR/bin/dot" theme-apply || echo "dotfiles: could not apply the shared theme"
}

dot_install_main() {
  local force=0 packages=1 arg omarchy=0 link_rc=0 pm priv
  for arg in "$@"; do
    case "$arg" in
      --force) force=1 ;;
      --no-packages) packages=0 ;;
      *)
        echo "dotfiles: unknown option $arg" >&2
        return 1
        ;;
    esac
  done
  dot_is_omarchy && omarchy=1

  if ((packages && omarchy)); then
    echo "dotfiles: Omarchy provides the system packages; skipping"
  elif ((packages)) && dot_base_tools_present; then
    echo "dotfiles: base packages already present; skipping"
  elif ((packages)); then
    pm=$(dot_pkg_manager)
    if priv=$(dot_priv); then
      dot_install_packages "$pm" "$priv" ||
        echo "dotfiles: package install failed; continuing (install missing tools by hand)"
    else
      echo "dotfiles: not root and no usable sudo, skipping system packages"
    fi
  fi

  dot_link_all "$DOTFILES_DIR/links.conf" "$force" || link_rc=$?

  if ((omarchy)); then
    dot_bash_hook
    dot_theme_sync_enable
  else
    dot_install_mise
  fi

  echo "dotfiles: $DOT_N_LINKED linked, $DOT_N_BACKUP backed up, $DOT_N_SKIPPED skipped"
  if ((link_rc != 0)); then
    echo "dotfiles: some targets point somewhere else; review them, then run: dot link --force" >&2
    return "$link_rc"
  fi
}
