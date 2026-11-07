load helpers

setup() {
  setup_fake_home
  export DOT_HOSTNAME=polaris
  DOT="$DOTFILES_DIR/bin/dot"
  # Start every test from an empty links.conf (header only) and no hub status.
  grep '^#' "$REPO_SRC/links.conf" >"$DOTFILES_DIR/links.conf"
  rm -f "$DOTFILES_DIR/.hub-status"
}

@test "track moves file and links it" {
  fake_omarchy on
  mkdir -p "$HOME/.config/hypr"
  echo 'gaps' >"$HOME/.config/hypr/looknfeel.lua"
  run "$DOT" track hypr/looknfeel.lua
  assert_success
  assert_link_exists "$HOME/.config/hypr/looknfeel.lua"
  assert_file_exists "$DOTFILES_DIR/desktop/hypr/looknfeel.lua"
  assert_equal "$(cat "$HOME/.config/hypr/looknfeel.lua")" "gaps"
  run grep -E '^desktop[[:space:]]+desktop/hypr/looknfeel.lua[[:space:]]+~/.config/hypr/looknfeel.lua$' "$DOTFILES_DIR/links.conf"
  assert_success
}

@test "track --layer host uses hostname" {
  fake_omarchy on
  mkdir -p "$HOME/.config/hypr"
  echo 'mon' >"$HOME/.config/hypr/monitors.lua"
  run "$DOT" track "$HOME/.config/hypr/monitors.lua" --layer host
  assert_success
  assert_file_exists "$DOTFILES_DIR/hosts/polaris/hypr/monitors.lua"
  run grep -E '^host:polaris[[:space:]]+hosts/polaris/hypr/monitors.lua[[:space:]]+~/.config/hypr/monitors.lua$' "$DOTFILES_DIR/links.conf"
  assert_success
}

@test "track a folder links it as a folder; default layer is core without omarchy" {
  fake_omarchy off
  mkdir -p "$HOME/.config/btop/themes"
  echo 'x' >"$HOME/.config/btop/btop.conf"
  run "$DOT" track btop
  assert_success
  assert_link_exists "$HOME/.config/btop"
  run grep -E '^core[[:space:]]+core/btop/[[:space:]]+~/.config/btop$' "$DOTFILES_DIR/links.conf"
  assert_success
}

@test "track refuses gh/hosts.yml" {
  mkdir -p "$HOME/.config/gh"
  echo 'token: x' >"$HOME/.config/gh/hosts.yml"
  run "$DOT" track gh/hosts.yml
  assert_failure
  assert_output --partial "secret"
  [ ! -L "$HOME/.config/gh/hosts.yml" ]
}

@test "track twice refuses" {
  fake_omarchy on
  mkdir -p "$HOME/.config/hypr"
  echo 'a' >"$HOME/.config/hypr/autostart.lua"
  "$DOT" track hypr/autostart.lua
  run "$DOT" track hypr/autostart.lua
  assert_failure
  assert_output --partial "already"
  assert_equal "$(grep -c autostart "$DOTFILES_DIR/links.conf")" 1
}

@test "status flags stock-identical linked file" {
  fake_omarchy on
  mkdir -p "$HOME/.config/hypr" "$DOTFILES_OMARCHY_ROOT/config/hypr"
  echo 'stock' >"$DOTFILES_OMARCHY_ROOT/config/hypr/windows.lua"
  echo 'mine' >"$HOME/.config/hypr/windows.lua"
  "$DOT" track hypr/windows.lua
  run "$DOT" status
  assert_success
  echo 'stock' >"$DOTFILES_DIR/desktop/hypr/windows.lua"
  run "$DOT" status
  assert_failure
  assert_output --partial "identical to Omarchy stock"
  assert_output --partial "hypr/windows.lua"
}

@test "status lists sync-conflict files" {
  touch "$DOTFILES_DIR/links.sync-conflict-20261107-120000-ABCDEFG.conf"
  run "$DOT" status
  assert_failure
  assert_output --partial "sync-conflict-20261107"
}

@test "status reports hub failure" {
  printf 'last_run=2026-11-07T03:00:00+01:00\nresult=fail\nmessage=gitleaks found 1 secret\n' >"$DOTFILES_DIR/.hub-status"
  run "$DOT" status
  assert_failure
  assert_output --partial "gitleaks"
}

@test "status reports missing and foreign links" {
  fake_omarchy off
  mkdir -p "$DOTFILES_DIR/core/x"
  echo a >"$DOTFILES_DIR/core/x/a.conf"
  echo b >"$DOTFILES_DIR/core/x/b.conf"
  printf 'core core/x/a.conf ~/.config/x/a.conf\ncore core/x/b.conf ~/.config/x/b.conf\n' >>"$DOTFILES_DIR/links.conf"
  mkdir -p "$HOME/.config/x"
  ln -s /elsewhere "$HOME/.config/x/b.conf"
  run "$DOT" status
  assert_failure
  assert_output --partial "not linked: $HOME/.config/x/a.conf"
  assert_output --partial "points elsewhere: $HOME/.config/x/b.conf"
}

@test "status clean" {
  printf 'last_run=2026-11-07T03:00:00+01:00\nresult=ok\nmessage=pushed 1 commit\n' >"$DOTFILES_DIR/.hub-status"
  run "$DOT" status
  assert_success
}

@test "link subcommand links everything" {
  fake_omarchy off
  mkdir -p "$DOTFILES_DIR/core/x"
  echo a >"$DOTFILES_DIR/core/x/a.conf"
  printf 'core core/x/a.conf ~/.config/x/a.conf\n' >>"$DOTFILES_DIR/links.conf"
  run "$DOT" link
  assert_success
  assert_link_exists "$HOME/.config/x/a.conf"
}

@test "unknown subcommand prints usage and fails" {
  run "$DOT" frobnicate
  assert_failure
  assert_output --partial "usage"
}

@test "track refuses paths with spaces (links.conf can't hold them)" {
  mkdir -p "$HOME/.config/My App"
  echo x >"$HOME/.config/My App/x.conf"
  run "$DOT" track "My App/x.conf"
  assert_failure
  assert_output --partial "spaces"
  [ ! -L "$HOME/.config/My App/x.conf" ]
  run "$DOT" link
  assert_success
}

@test "track refuses a browser profile folder" {
  mkdir -p "$HOME/.config/chromium/Default"
  echo cookie >"$HOME/.config/chromium/Default/Cookies"
  run "$DOT" track chromium
  assert_failure
  assert_output --partial "secret"
  assert_dir_exists "$HOME/.config/chromium/Default"
}

@test "track refuses a folder that contains a secret file" {
  mkdir -p "$HOME/.config/gh"
  echo 'git_protocol: ssh' >"$HOME/.config/gh/config.yml"
  echo 'oauth_token: x' >"$HOME/.config/gh/hosts.yml"
  run "$DOT" track gh
  assert_failure
  assert_output --partial "secret"
  [ ! -L "$HOME/.config/gh" ]
}

@test "track refuses whole top-level folders" {
  mkdir -p "$HOME/.config/x" "$HOME/.local/share"
  for p in "$HOME/.config" "$HOME/.local" "$HOME/dotfiles" "$HOME"; do
    run "$DOT" track "$p"
    assert_failure
  done
  assert_dir_exists "$HOME/.config/x"
  [ ! -L "$HOME/.config" ]
}
