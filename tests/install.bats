load helpers

setup() {
  setup_fake_home
  export DOT_HOSTNAME=testhost
  grep '^#' "$REPO_SRC/links.conf" >"$DOTFILES_DIR/links.conf"
  mkdir -p "$DOTFILES_DIR/core/x"
  echo a >"$DOTFILES_DIR/core/x/a.conf"
  echo 'core core/x/a.conf ~/.config/x/a.conf' >>"$DOTFILES_DIR/links.conf"
  # Never reach the network or real package managers from tests.
  stub mise 'echo "mise $*" >>"$BATS_TEST_TMPDIR/mise.calls"'
  stub curl 'echo "curl called" >>"$BATS_TEST_TMPDIR/curl.calls"; exit 99'
}

lib() { echo "source '$DOTFILES_DIR/lib/links.sh'; source '$DOTFILES_DIR/lib/install.sh'"; }

@test "pkg manager detection" {
  for pm in pacman apt-get dnf zypper apk; do
    rm -rf "$BATS_TEST_TMPDIR/only" && mkdir -p "$BATS_TEST_TMPDIR/only"
    printf '#!/bin/sh\n' >"$BATS_TEST_TMPDIR/only/$pm" && chmod +x "$BATS_TEST_TMPDIR/only/$pm"
    run env PATH="$BATS_TEST_TMPDIR/only" /bin/bash -c "$(lib); dot_pkg_manager"
    assert_success
    assert_output "${pm%-get}"
  done
  rm -rf "$BATS_TEST_TMPDIR/only" && mkdir -p "$BATS_TEST_TMPDIR/only"
  run env PATH="$BATS_TEST_TMPDIR/only" /bin/bash -c "$(lib); dot_pkg_manager"
  assert_output "none"
}

@test "priv: root without sudo is empty; non-root without sudo fails" {
  run env PATH="$STUB_BIN:/usr/bin:/bin" DOT_EUID=0 /bin/bash -c "$(lib); dot_priv"
  assert_success
  assert_output ""
  run env PATH="$STUB_BIN:/usr/bin:/bin" DOT_EUID=1000 /bin/bash -c "$(lib); dot_priv"
  assert_failure
  stub sudo 'if [[ "$1" == -n ]]; then shift; fi; exec "$@"'
  run env PATH="$STUB_BIN:/usr/bin:/bin" DOT_EUID=1000 /bin/bash -c "$(lib); dot_priv"
  assert_success
  assert_output "sudo"
}

@test "install with no priv skips packages with one message and still links" {
  fake_omarchy off
  run env DOT_EUID=1000 bash "$DOTFILES_DIR/install.sh" </dev/null
  assert_success
  assert_equal "$(grep -c 'skipping system packages' <<<"$output")" 1
  assert_link_exists "$HOME/.config/x/a.conf"
  assert_output --partial "dotfiles: 1 linked, 0 backed up, 0 skipped"
}

@test "bash hook appended once on omarchy" {
  fake_omarchy on
  echo '# omarchy template' >"$HOME/.bashrc"
  bash "$DOTFILES_DIR/install.sh" --no-packages </dev/null
  bash "$DOTFILES_DIR/install.sh" --no-packages </dev/null
  assert_equal "$(grep -c 'core/bash/personal.bash' "$HOME/.bashrc")" 1
  run head -1 "$HOME/.bashrc"
  assert_output '# omarchy template'
}

@test "rerun in non-git DOTFILES_DIR does no git ops and no prompts" {
  fake_omarchy off
  stub git 'echo "git $*" >>"$BATS_TEST_TMPDIR/git.calls"; exit 99'
  run bash "$DOTFILES_DIR/install.sh" --no-packages </dev/null
  assert_success
  run bash "$DOTFILES_DIR/install.sh" --no-packages </dev/null
  assert_success
  assert_output --partial "dotfiles: 0 linked, 0 backed up, 0 skipped"
  assert_file_not_exists "$BATS_TEST_TMPDIR/git.calls"
}

@test "omarchy: no mise install; non-omarchy: mise install invoked" {
  fake_omarchy on
  bash "$DOTFILES_DIR/install.sh" --no-packages </dev/null
  assert_file_not_exists "$BATS_TEST_TMPDIR/mise.calls"
  fake_omarchy off
  bash "$DOTFILES_DIR/install.sh" --no-packages </dev/null
  run cat "$BATS_TEST_TMPDIR/mise.calls"
  assert_output --partial "mise install"
  assert_file_not_exists "$BATS_TEST_TMPDIR/curl.calls"
}

@test "piped bootstrap clones the repo, then installs from the clone" {
  fake_omarchy off
  # Turn the fake checkout into a git repo to clone from, standing in for GitHub.
  # (Files copied into the container keep the host uid; tell git that's fine.)
  git config --global --add safe.directory '*'
  git -C "$DOTFILES_DIR" init -q -b main
  git -C "$DOTFILES_DIR" -c user.name=t -c user.email=t@t add -A
  git -C "$DOTFILES_DIR" -c user.name=t -c user.email=t@t commit -qm init
  export DOTFILES_REPO="$DOTFILES_DIR"
  export DOTFILES_DIR="$HOME/fresh-dotfiles"
  run bash -c "bash < '$DOTFILES_REPO/install.sh' -s -- --no-packages"
  assert_success
  assert_dir_exists "$HOME/fresh-dotfiles/.git"
  assert_equal "$(readlink "$HOME/.config/x/a.conf")" "$HOME/fresh-dotfiles/core/x/a.conf"
}

@test "foreign link makes install exit non-zero but still prints the summary" {
  fake_omarchy off
  mkdir -p "$HOME/.config/x"
  ln -s /elsewhere "$HOME/.config/x/a.conf"
  run bash "$DOTFILES_DIR/install.sh" --no-packages </dev/null
  assert_failure
  assert_output --partial "dotfiles: 0 linked, 0 backed up, 1 skipped"
  assert_output --partial "dot link --force"
}

@test "omarchy machines skip system packages entirely" {
  fake_omarchy on
  stub pacman 'echo "pacman $*" >>"$BATS_TEST_TMPDIR/pacman.calls"'
  run env DOT_EUID=0 bash "$DOTFILES_DIR/install.sh" </dev/null
  assert_success
  assert_file_not_exists "$BATS_TEST_TMPDIR/pacman.calls"
  assert_output --partial "Omarchy provides the system packages"
}

@test "pacman refreshes package lists with a full sync (-Syu) on non-Omarchy Arch" {
  fake_omarchy off
  stub pacman 'echo "pacman $*" >>"$BATS_TEST_TMPDIR/pacman.calls"'
  run env DOT_EUID=0 bash "$DOTFILES_DIR/install.sh" </dev/null
  assert_success
  run cat "$BATS_TEST_TMPDIR/pacman.calls"
  assert_output --partial "pacman -Syu --needed --noconfirm"
}

@test "on musl (Alpine) neovim and node come from apk, and mise skips them" {
  fake_omarchy off
  [[ -n "$(ls /lib/ld-musl-* 2>/dev/null)" ]] || skip "test container is not musl"
  stub mise 'echo "mise $* DISABLE=${MISE_DISABLE_TOOLS:-}" >>"$BATS_TEST_TMPDIR/mise.calls"'
  stub apk 'echo "apk $*" >>"$BATS_TEST_TMPDIR/apk.calls"'
  run env DOT_EUID=0 bash "$DOTFILES_DIR/install.sh" </dev/null
  assert_success
  run cat "$BATS_TEST_TMPDIR/mise.calls"
  assert_output --partial "install DISABLE=neovim,node"
  run cat "$BATS_TEST_TMPDIR/apk.calls"
  assert_output --regexp "apk add .*neovim"
  assert_output --regexp "apk add .*nodejs"
}

@test "vm bashrc hides mise neovim/node on musl" {
  run grep -F 'MISE_DISABLE_TOOLS=neovim,node' "$DOTFILES_DIR/vm/bash/bashrc"
  assert_success
}

@test "unusable sudo (non-interactive) skips packages and still links" {
  fake_omarchy off
  stub sudo 'if [[ "$1" == -n ]]; then exit 1; fi; echo "sudo $*" >>"$BATS_TEST_TMPDIR/sudo.calls"; exit 1'
  run env DOT_EUID=1000 bash "$DOTFILES_DIR/install.sh" </dev/null
  assert_success
  assert_output --partial "skipping system packages"
  assert_link_exists "$HOME/.config/x/a.conf"
  assert_file_not_exists "$BATS_TEST_TMPDIR/sudo.calls"
}

@test "a failing package manager is a warning; linking still happens" {
  fake_omarchy off
  stub pacman 'exit 1'
  run env DOT_EUID=0 bash "$DOTFILES_DIR/install.sh" </dev/null
  assert_success
  assert_output --partial "package install failed"
  assert_link_exists "$HOME/.config/x/a.conf"
}

@test "re-run skips the package manager when the base tools are present" {
  fake_omarchy off
  for c in git curl unzip tar gzip make cc rg fd tmux nvim node; do stub "$c" 'exit 0'; done
  stub pacman 'echo "pacman $*" >>"$BATS_TEST_TMPDIR/pacman.calls"'
  run env DOT_EUID=0 bash "$DOTFILES_DIR/install.sh" </dev/null
  assert_success
  assert_output --partial "base packages already present"
  assert_file_not_exists "$BATS_TEST_TMPDIR/pacman.calls"
}

@test "bootstrap installs git with a full sync on Arch when git is missing" {
  # A PATH with a shell and core utils but no git, plus a logging pacman.
  nogit="$BATS_TEST_TMPDIR/nogit"; mkdir -p "$nogit"
  for c in bash sh ls cat dirname mkdir rm env grep sed tr head; do ln -sf "$(command -v $c)" "$nogit/$c"; done
  printf '#!/bin/sh\necho "pacman $*" >>"%s/pacman.calls"; exit 1\n' "$BATS_TEST_TMPDIR" >"$nogit/pacman"; chmod +x "$nogit/pacman"
  run env PATH="$nogit" DOT_EUID=0 DOTFILES_DIR="$HOME/fresh" /bin/bash -c "bash < '$DOTFILES_DIR/install.sh'"
  assert_failure
  run cat "$BATS_TEST_TMPDIR/pacman.calls"
  assert_output --partial "-Syu --needed --noconfirm git"
}
