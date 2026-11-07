load helpers

# Fake secrets and addresses are assembled at runtime so this file itself
# never contains them (the check scans this repo too).
FAKE_TOKEN="ghp_""K8mP2vQ9rL5nW3sT7yB1cF6hJ4dG0aZ8eR2x"
FAKE_TS_IP="100.""99.183.7"
FAKE_TS_NAME="my-box.example-tailnet.ts"".net"
FAKE_TS_V6="fd7a:115c:""a1e0::1234"

setup() {
  setup_fake_home
  git config --global --add safe.directory '*'
  git config --global user.name t
  git config --global user.email t@t
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO/core"
  git -C "$REPO" init -q -b main
  echo 'alias n=nvim' >"$REPO/core/personal.bash"
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm init
  CHECK="$DOTFILES_DIR/hub/check-public.sh"
}

@test "clean repo passes" {
  echo 'set -o vi' >>"$REPO/core/personal.bash"
  git -C "$REPO" add -A
  run "$CHECK" "$REPO" --staged
  assert_success
}

@test "planted GitHub token fails" {
  echo "export GITHUB_TOKEN=$FAKE_TOKEN" >"$REPO/core/env.sh"
  git -C "$REPO" add -A
  run "$CHECK" "$REPO" --staged
  assert_failure
  assert_output --regexp $'^secret\tcore/env.sh'
  refute_output --partial "$FAKE_TOKEN"
}

@test "tailscale IP fails" {
  echo "ssh mackc@$FAKE_TS_IP" >"$REPO/core/hosts.txt"
  git -C "$REPO" add -A
  run "$CHECK" "$REPO" --staged
  assert_failure
  assert_output --regexp $'^private\tcore/hosts.txt\t1'
}

@test "ordinary 100.x version numbers are not flagged" {
  echo "version 100.2.3.4 and 10.64.1.1" >"$REPO/core/notes.txt"
  git -C "$REPO" add -A
  run "$CHECK" "$REPO" --staged
  assert_success
}

@test "denylist word fails" {
  mkdir -p "$REPO/hub"
  printf 'homelab-secret-path\n' >"$REPO/hub/local.denylist"
  echo "mount /srv/homelab-secret-path" >"$REPO/core/mounts.txt"
  git -C "$REPO" add core/mounts.txt
  run "$CHECK" "$REPO" --staged
  assert_failure
  assert_output --regexp $'^private\tcore/mounts.txt\t1'
}

@test "history mode finds token removed in a later commit" {
  echo "token=$FAKE_TOKEN" >"$REPO/core/old.sh"
  git -C "$REPO" add -A && git -C "$REPO" commit -qm oops
  git -C "$REPO" rm -q core/old.sh && git -C "$REPO" commit -qm fix
  run "$CHECK" "$REPO" --staged
  assert_success
  run "$CHECK" "$REPO" --history
  assert_failure
  assert_output --partial "core/old.sh"
}

@test "history mode finds a private address removed later" {
  echo "host $FAKE_TS_IP" >"$REPO/core/old.txt"
  git -C "$REPO" add -A && git -C "$REPO" commit -qm oops
  git -C "$REPO" rm -q core/old.txt && git -C "$REPO" commit -qm fix
  run "$CHECK" "$REPO" --history
  assert_failure
  assert_output --partial "core/old.txt"
}

@test "this repository's own tracked files pass" {
  rm -rf "$BATS_TEST_TMPDIR/self"
  cp -r "$DOTFILES_DIR" "$BATS_TEST_TMPDIR/self"
  git -C "$BATS_TEST_TMPDIR/self" init -q -b main
  git -C "$BATS_TEST_TMPDIR/self" add -A
  run "$CHECK" "$BATS_TEST_TMPDIR/self" --staged
  assert_success
}

@test "fails closed when the target is not a git repository" {
  mkdir -p "$BATS_TEST_TMPDIR/notgit"
  run "$CHECK" "$BATS_TEST_TMPDIR/notgit" --staged
  assert_equal "$status" 2
}

@test "range mode checks commits that are already committed" {
  echo "host $FAKE_TS_IP" >"$REPO/core/hosts.txt"
  git -C "$REPO" add -A && git -C "$REPO" commit -qm "hand commit"
  run "$CHECK" "$REPO" --range HEAD~1..HEAD
  assert_failure
  assert_output --partial "core/hosts.txt"
  # A range that excludes the commit is clean.
  run "$CHECK" "$REPO" --range HEAD~1..HEAD~1
  assert_success
}

@test "range mode catches a committed secret" {
  echo "token=$FAKE_TOKEN" >"$REPO/core/t.sh"
  git -C "$REPO" add -A && git -C "$REPO" commit -qm "hand commit"
  run "$CHECK" "$REPO" --range HEAD~1..HEAD
  assert_failure
  assert_output --regexp $'^secret\tcore/t.sh'
}

@test "tailnet names and Tailscale IPv6 addresses are private" {
  echo "ssh $FAKE_TS_NAME" >"$REPO/core/a.txt"
  echo "addr $FAKE_TS_V6" >"$REPO/core/b.txt"
  git -C "$REPO" add -A
  run "$CHECK" "$REPO" --staged
  assert_failure
  assert_output --partial "core/a.txt"
  assert_output --partial "core/b.txt"
}

@test "denylist matching ignores case" {
  mkdir -p "$REPO/hub"
  printf 'HomeLab-Secret\n' >"$REPO/hub/local.denylist"
  echo "see homelab-secret" >"$REPO/core/m.txt"
  git -C "$REPO" add core/m.txt
  run "$CHECK" "$REPO" --staged
  assert_failure
}
