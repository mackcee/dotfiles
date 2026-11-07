load helpers

@test "harness runs" {
  setup_fake_home
  assert_dir_exists "$DOTFILES_DIR/tests"
}
