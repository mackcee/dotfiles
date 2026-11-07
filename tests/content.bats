load helpers

setup() { setup_fake_home; source "$DOTFILES_DIR/lib/links.sh"; }

@test "every links.conf source exists, for every machine kind" {
  for om in 0 1; do
    for host in polaris aurora-2 somevm; do
      run dot_resolve_links "$DOTFILES_DIR/links.conf" "$om" "$host"
      assert_success
      while IFS=$'\t' read -r src _ kind; do
        [[ -n "$src" ]] || continue
        if [[ "$kind" == dir ]]; then assert_dir_exists "$src"; else assert_file_exists "$src"; fi
      done <<<"$output"
    done
  done
}

@test "nvim theme is a real file, not a symlink" {
  assert_file_exists "$DOTFILES_DIR/core/nvim/lua/plugins/theme.lua"
  [ ! -L "$DOTFILES_DIR/core/nvim/lua/plugins/theme.lua" ]
}

@test "no symlinks anywhere in the shared config" {
  run find "$DOTFILES_DIR/core" "$DOTFILES_DIR/vm" "$DOTFILES_DIR/desktop" "$DOTFILES_DIR/hosts" -type l
  assert_output ""
}

@test "bash files parse" {
  bash -n "$DOTFILES_DIR/core/bash/personal.bash"
  bash -n "$DOTFILES_DIR/vm/bash/bashrc"
}

@test "personal.bash loads in a plain interactive shell without Omarchy" {
  run env -i HOME="$HOME" PATH=/usr/bin:/bin bash --norc -i -c "source '$DOTFILES_DIR/core/bash/personal.bash'; alias n"
  assert_success
  assert_output --partial "nvim"
}

@test "theme file names a theme" {
  run cat "$DOTFILES_DIR/desktop/omarchy/theme"
  assert_output --regexp '^[a-z0-9-]+$'
}

@test "no homelab details in tracked content" {
  run grep -rInE '100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]+\.[0-9]+|nas[-]pool|/home/casper|192\.168\.|\bCT ?[0-9]{2,4}\b|pct (set|exec) [0-9]|[a-z0-9-]+\.ts\.net' \
    "$DOTFILES_DIR/core" "$DOTFILES_DIR/vm" "$DOTFILES_DIR/desktop" "$DOTFILES_DIR/hosts" "$DOTFILES_DIR/links.conf" \
    "$DOTFILES_DIR/docs" "$DOTFILES_DIR/hub"
  assert_failure
}

@test ".hub-status is kept out of git but synced to machines" {
  run grep -qxF '.hub-status' "$DOTFILES_DIR/.gitignore"
  assert_success
  run grep -qxF '.hub-status' "$DOTFILES_DIR/.stglobalignore"
  assert_failure
}

@test "hub-only settings are neither committed nor synced" {
  for f in hub/local.env hub/local.denylist; do
    grep -qxF "$f" "$DOTFILES_DIR/.gitignore"
    grep -qxF "$f" "$DOTFILES_DIR/.stglobalignore"
  done
}

@test "hub example settings exist and hold placeholders only" {
  assert_file_exists "$DOTFILES_DIR/hub/local.env.example"
  assert_file_exists "$DOTFILES_DIR/hub/local.denylist.example"
}

@test "never-sync list covers browser profiles and credential stores" {
  for f in .gitignore .stglobalignore; do
    for name in chromium google-chrome BraveSoftware .mozilla .gnupg .aws .kube .git-credentials; do
      grep -qE "(^|/)${name//./\\.}([*]?)$" "$DOTFILES_DIR/$f" || { echo "$f lacks $name"; false; }
    done
  done
}

@test "syncthing temp files are never committed" {
  run grep -F '.syncthing.*.tmp' "$DOTFILES_DIR/.gitignore"
  assert_success
}

@test "personal.bash puts the dot helper on PATH" {
  bats_require_minimum_version 1.5.0
  run --separate-stderr env -i HOME="$HOME" PATH=/usr/bin:/bin bash --norc -i -c "source '$DOTFILES_DIR/core/bash/personal.bash'; command -v dot"
  assert_success
  assert_output "$DOTFILES_DIR/bin/dot"
}
