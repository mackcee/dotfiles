load helpers

setup() {
  setup_fake_home
  export DOT_HOSTNAME=testhost
  HOOK="$DOTFILES_DIR/desktop/omarchy/hooks/theme-set.d/dotfiles-record-theme"
  THEME_FILE="$DOTFILES_DIR/desktop/omarchy/theme"
  echo tokyo-night >"$THEME_FILE"
  mkdir -p "$HOME/.local/state/omarchy/current"
  stub omarchy 'echo "$*" >>"$BATS_TEST_TMPDIR/omarchy.calls"'
  export DOTFILES_OMARCHY_ROOT="$BATS_TEST_TMPDIR/omarchy-root"
  mkdir -p "$DOTFILES_OMARCHY_ROOT/config"
}

@test "hook writes slug when different" {
  run "$HOOK" catppuccin
  assert_success
  assert_equal "$(cat "$THEME_FILE")" "catppuccin"
}

@test "hook leaves file untouched when same (loop guard)" {
  touch -d '2020-01-01 00:00' "$THEME_FILE"
  before=$(stat -c %Y "$THEME_FILE")
  run "$HOOK" tokyo-night
  assert_success
  assert_equal "$(stat -c %Y "$THEME_FILE")" "$before"
}

@test "hook works when called through a symlink, as Omarchy does" {
  mkdir -p "$HOME/.config/omarchy/hooks/theme-set.d"
  ln -s "$HOOK" "$HOME/.config/omarchy/hooks/theme-set.d/dotfiles-record-theme"
  run "$HOME/.config/omarchy/hooks/theme-set.d/dotfiles-record-theme" gruvbox
  assert_success
  assert_equal "$(cat "$THEME_FILE")" "gruvbox"
}

@test "theme-apply calls omarchy theme set only on difference" {
  echo tokyo-night >"$HOME/.local/state/omarchy/current/theme.name"
  run "$DOTFILES_DIR/bin/dot" theme-apply
  assert_success
  assert_file_not_exists "$BATS_TEST_TMPDIR/omarchy.calls"

  echo catppuccin >"$THEME_FILE"
  run "$DOTFILES_DIR/bin/dot" theme-apply
  assert_success
  run cat "$BATS_TEST_TMPDIR/omarchy.calls"
  assert_output "theme set catppuccin"
}

@test "slug with spaces from 'theme current' is normalised" {
  # No theme.name state file: fall back to `omarchy theme current` ("Tokyo Night").
  stub omarchy 'if [[ "$*" == "theme current" ]]; then echo "Tokyo Night"; else echo "$*" >>"$BATS_TEST_TMPDIR/omarchy.calls"; fi'
  run "$DOTFILES_DIR/bin/dot" theme-apply
  assert_success
  assert_file_not_exists "$BATS_TEST_TMPDIR/omarchy.calls"
}

@test "theme-apply does nothing on a machine without Omarchy" {
  rm -rf "$DOTFILES_OMARCHY_ROOT"
  echo catppuccin >"$THEME_FILE"
  run "$DOTFILES_DIR/bin/dot" theme-apply
  assert_success
  assert_file_not_exists "$BATS_TEST_TMPDIR/omarchy.calls"
}

@test "install on omarchy enables the theme path unit and applies the theme" {
  stub systemctl 'echo "systemctl $*" >>"$BATS_TEST_TMPDIR/systemctl.calls"'
  echo tokyo-night >"$HOME/.local/state/omarchy/current/theme.name"
  echo catppuccin >"$THEME_FILE"
  run bash "$DOTFILES_DIR/install.sh" --no-packages </dev/null
  assert_success
  run cat "$BATS_TEST_TMPDIR/systemctl.calls"
  assert_output --partial "--user daemon-reload"
  assert_output --partial "--user enable --now dotfiles-theme.path"
  run cat "$BATS_TEST_TMPDIR/omarchy.calls"
  assert_output --partial "theme set catppuccin"
  assert_link_exists "$HOME/.config/systemd/user/dotfiles-theme.path"
  assert_link_exists "$HOME/.config/omarchy/hooks/theme-set.d/dotfiles-record-theme"
}

@test "path unit watches the synced theme file and runs theme-apply" {
  run cat "$DOTFILES_DIR/desktop/systemd/user/dotfiles-theme.path"
  assert_output --partial "PathChanged=%h/dotfiles/desktop/omarchy/theme"
  run cat "$DOTFILES_DIR/desktop/systemd/user/dotfiles-theme.service"
  assert_output --partial "ExecStart=%h/dotfiles/bin/dot theme-apply"
}
