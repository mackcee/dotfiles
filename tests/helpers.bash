# Shared bats helpers. Load with:  load helpers
bats_load_library bats-support
bats_load_library bats-assert
bats_load_library bats-file

REPO_SRC="${BATS_TEST_DIRNAME}/.."

# Fresh fake $HOME with a writable copy of the repo at $HOME/dotfiles.
setup_fake_home() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_STATE_HOME="$HOME/.local/state"
  export DOTFILES_DIR="$HOME/dotfiles"
  mkdir -p "$HOME"
  mkdir -p "$DOTFILES_DIR"
  (cd "$REPO_SRC" && tar --exclude=.git --exclude=.superpowers --exclude=hub/local.denylist --exclude=hub/local.env --exclude=.hub-status --exclude=tests/.smoke -cf - .) | tar -xf - -C "$DOTFILES_DIR"
  export STUB_BIN="$BATS_TEST_TMPDIR/stubbin"
  mkdir -p "$STUB_BIN"
  export PATH="$STUB_BIN:$PATH"
}

# Write an executable stub command into $STUB_BIN. Usage: stub NAME 'body'
stub() {
  printf '#!/usr/bin/env bash\n%s\n' "$2" >"$STUB_BIN/$1"
  chmod +x "$STUB_BIN/$1"
}

# fake_omarchy on|off — a stub `omarchy` plus a fake /usr/share/omarchy root.
fake_omarchy() {
  export DOTFILES_OMARCHY_ROOT="$BATS_TEST_TMPDIR/omarchy-root"
  if [[ "$1" == on ]]; then
    mkdir -p "$DOTFILES_OMARCHY_ROOT/config"
    stub omarchy 'echo "omarchy $*" >>"$BATS_TEST_TMPDIR/omarchy.calls"'
  else
    rm -rf "$DOTFILES_OMARCHY_ROOT" "$STUB_BIN/omarchy"
  fi
}
