load helpers

setup() {
  setup_fake_home
  # shellcheck source=lib/links.sh
  source "$DOTFILES_DIR/lib/links.sh"
  CONF="$BATS_TEST_TMPDIR/links.conf"
  mkdir -p "$DOTFILES_DIR/core/nvim" "$DOTFILES_DIR/vm/tmux" "$DOTFILES_DIR/desktop/hypr" \
    "$DOTFILES_DIR/hosts/polaris/hypr"
  echo 'nvim' >"$DOTFILES_DIR/core/nvim/init.lua"
  echo 'tmux' >"$DOTFILES_DIR/vm/tmux/tmux.conf"
  echo 'desk' >"$DOTFILES_DIR/desktop/hypr/input.lua"
  echo 'host' >"$DOTFILES_DIR/hosts/polaris/hypr/input.lua"
  echo 'bind' >"$DOTFILES_DIR/desktop/hypr/bindings.lua"
}

write_conf() { printf '%s\n' "$@" >"$CONF"; }

@test "resolve: vm layer only without omarchy" {
  write_conf \
    "core     core/nvim/              ~/.config/nvim" \
    "vm       vm/tmux/tmux.conf       ~/.config/tmux/tmux.conf" \
    "desktop  desktop/hypr/bindings.lua ~/.config/hypr/bindings.lua"
  run dot_resolve_links "$CONF" 0 polaris
  assert_success
  assert_equal "${#lines[@]}" 2
  assert_line --partial "vm/tmux/tmux.conf"
  refute_line --partial "desktop/"
  assert_line "$DOTFILES_DIR/core/nvim"$'\t'"$HOME/.config/nvim"$'\t'"dir"

  run dot_resolve_links "$CONF" 1 polaris
  assert_success
  assert_equal "${#lines[@]}" 2
  assert_line --partial "desktop/hypr/bindings.lua"
  refute_line --partial "vm/"
}

@test "resolve: host entry overrides desktop for same target" {
  write_conf \
    "desktop       desktop/hypr/input.lua        ~/.config/hypr/input.lua" \
    "host:polaris  hosts/polaris/hypr/input.lua  ~/.config/hypr/input.lua"
  run dot_resolve_links "$CONF" 1 polaris
  assert_success
  assert_equal "${#lines[@]}" 1
  assert_line --partial "hosts/polaris/"

  run dot_resolve_links "$CONF" 1 aurora-2
  assert_success
  assert_equal "${#lines[@]}" 1
  assert_line --partial "desktop/hypr/input.lua"
}

@test "resolve: comment and blank lines ignored; malformed line errors with line number" {
  write_conf "# comment" "" "   " "core core/nvim/ ~/.config/nvim"
  run dot_resolve_links "$CONF" 0 polaris
  assert_success
  assert_equal "${#lines[@]}" 1

  write_conf "core core/nvim/ ~/.config/nvim" "core only-two-fields"
  run dot_resolve_links "$CONF" 0 polaris
  assert_failure
  assert_output --partial "line 2"

  write_conf "bogus core/nvim/ ~/.config/nvim"
  run dot_resolve_links "$CONF" 0 polaris
  assert_failure
  assert_output --partial "line 1"
}

@test "link: creates parent dirs and symlink" {
  run dot_link_one "$DOTFILES_DIR/vm/tmux/tmux.conf" "$HOME/.config/tmux/tmux.conf" 0
  assert_success
  assert_output --regexp '^linked'
  assert_link_exists "$HOME/.config/tmux/tmux.conf"
  assert_equal "$(readlink "$HOME/.config/tmux/tmux.conf")" "$DOTFILES_DIR/vm/tmux/tmux.conf"
}

@test "link: idempotent" {
  dot_link_one "$DOTFILES_DIR/vm/tmux/tmux.conf" "$HOME/.config/tmux/tmux.conf" 0
  run dot_link_one "$DOTFILES_DIR/vm/tmux/tmux.conf" "$HOME/.config/tmux/tmux.conf" 0
  assert_success
  assert_output --regexp '^ok'
  assert_dir_not_exists "$XDG_STATE_HOME/dotfiles/backup"
}

@test "link: real directory target is backed up whole" {
  mkdir -p "$HOME/.config/nvim/lua"
  echo 'old' >"$HOME/.config/nvim/init.lua"
  echo 'old' >"$HOME/.config/nvim/lua/x.lua"
  run dot_link_one "$DOTFILES_DIR/core/nvim" "$HOME/.config/nvim" 0
  assert_success
  assert_output --regexp '^backup\+linked'
  assert_link_exists "$HOME/.config/nvim"
  run bash -c "ls -d '$XDG_STATE_HOME'/dotfiles/backup/*/.config/nvim/lua/x.lua"
  assert_success
  assert_equal "$(cat "$HOME/.config/nvim/init.lua")" "nvim"
}

@test "link: missing source is skipped, no dangling link" {
  run dot_link_one "$DOTFILES_DIR/not/there.conf" "$HOME/.config/x/there.conf" 0
  assert_equal "$status" 3
  assert_output --regexp '^skip-missing'
  assert_not_exists "$HOME/.config/x/there.conf"
  [ ! -L "$HOME/.config/x/there.conf" ]
}

@test "link: foreign symlink skipped unless force" {
  mkdir -p "$HOME/.config/tmux" "$HOME/elsewhere"
  echo other >"$HOME/elsewhere/tmux.conf"
  ln -s "$HOME/elsewhere/tmux.conf" "$HOME/.config/tmux/tmux.conf"
  run dot_link_one "$DOTFILES_DIR/vm/tmux/tmux.conf" "$HOME/.config/tmux/tmux.conf" 0
  assert_equal "$status" 2
  assert_output --regexp '^skip-foreign'
  assert_equal "$(readlink "$HOME/.config/tmux/tmux.conf")" "$HOME/elsewhere/tmux.conf"

  run dot_link_one "$DOTFILES_DIR/vm/tmux/tmux.conf" "$HOME/.config/tmux/tmux.conf" 1
  assert_success
  assert_equal "$(readlink "$HOME/.config/tmux/tmux.conf")" "$DOTFILES_DIR/vm/tmux/tmux.conf"
}

@test "link: tilde expansion with HOME containing a space" {
  export HOME="$BATS_TEST_TMPDIR/my home"
  export XDG_STATE_HOME="$HOME/.local/state"
  mkdir -p "$HOME"
  write_conf "vm vm/tmux/tmux.conf ~/.config/tmux/tmux.conf"
  run dot_resolve_links "$CONF" 0 polaris
  assert_success
  assert_output "$DOTFILES_DIR/vm/tmux/tmux.conf"$'\t'"$HOME/.config/tmux/tmux.conf"$'\t'"file"
  run dot_link_all "$CONF" 0
  assert_success
  assert_link_exists "$HOME/.config/tmux/tmux.conf"
}

@test "link_all: returns non-zero when an entry is foreign, but links the rest" {
  write_conf \
    "core core/nvim/ ~/.config/nvim" \
    "vm   vm/tmux/tmux.conf ~/.config/tmux/tmux.conf"
  mkdir -p "$HOME/.config/tmux"
  ln -s /nonexistent "$HOME/.config/tmux/tmux.conf"
  run dot_link_all "$CONF" 0
  assert_failure
  assert_link_exists "$HOME/.config/nvim"
}
