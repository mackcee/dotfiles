load helpers

setup() {
  setup_fake_home
  git config --global --add safe.directory '*'
  git config --global user.name hub
  git config --global user.email hub@test
  git config --global init.defaultBranch main
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  HUB="$BATS_TEST_TMPDIR/hub"
  VM="$BATS_TEST_TMPDIR/vm"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$HUB" 2>/dev/null
  cp -r "$DOTFILES_DIR/hub" "$HUB/hub"
  # The timer runs pinned copies installed outside the synced repo.
  PINNED="$BATS_TEST_TMPDIR/pinned"
  mkdir -p "$PINNED" && cp "$DOTFILES_DIR/hub/autocommit.sh" "$DOTFILES_DIR/hub/check-public.sh" "$PINNED/"
  cp "$DOTFILES_DIR/.gitignore" "$HUB/.gitignore"
  echo 'alias n=nvim' >"$HUB/personal.bash"
  git -C "$HUB" add -A && git -C "$HUB" commit -qm init && git -C "$HUB" push -q origin main
  git clone -q "$ORIGIN" "$VM"
  AUTO="$PINNED/autocommit.sh"
}

status_val() { sed -n "s/^$1=//p" "$HUB/.hub-status"; }
origin_count() { git -C "$ORIGIN" rev-list --count main; }

@test "noop when nothing changed" {
  run "$AUTO" "$HUB"
  assert_success
  assert_equal "$(origin_count)" 1
  assert_equal "$(status_val result)" noop
}

@test "commits and pushes local change" {
  echo 'set -o vi' >>"$HUB/personal.bash"
  run "$AUTO" "$HUB"
  assert_success
  assert_equal "$(origin_count)" 2
  run git -C "$ORIGIN" log -1 --format=%B main
  assert_output --regexp '^auto: 1 files changed'
  assert_output --partial 'personal.bash'
  assert_equal "$(status_val result)" ok
  assert_equal "$(status_val last_push)" "$(git -C "$ORIGIN" rev-parse main)"
}

@test "status file itself is never committed" {
  echo 'x' >>"$HUB/personal.bash"
  "$AUTO" "$HUB"
  run git -C "$ORIGIN" ls-tree -r --name-only main
  refute_output --partial '.hub-status'
}

@test "secret blocks commit" {
  echo "export GITHUB_TOKEN=ghp_""K8mP2vQ9rL5nW3sT7yB1cF6hJ4dG0aZ8eR2x" >"$HUB/env.sh"
  before=$(git -C "$HUB" rev-parse HEAD)
  run "$AUTO" "$HUB"
  assert_failure
  assert_equal "$(git -C "$HUB" rev-parse HEAD)" "$before"
  assert_equal "$(origin_count)" 1
  assert_equal "$(status_val result)" fail
  assert_output --partial "check-public"
  [[ "$(status_val message)" == *check-public* ]]
  # Left as it was: still present, not staged.
  assert_file_exists "$HUB/env.sh"
  run git -C "$HUB" diff --cached --name-only
  assert_output ""
}

@test "remote ahead, no local change: working tree fast-forwarded" {
  echo 'from the vm' >"$VM/vm.txt"
  git -C "$VM" add -A && git -C "$VM" commit -qm "vm change" && git -C "$VM" push -q origin main
  run "$AUTO" "$HUB"
  assert_success
  assert_equal "$(cat "$HUB/vm.txt")" "from the vm"
  assert_equal "$(status_val result)" ok
}

@test "remote ahead plus local change: rebased and pushed, history linear" {
  echo 'from the vm' >"$VM/vm.txt"
  git -C "$VM" add -A && git -C "$VM" commit -qm "vm change" && git -C "$VM" push -q origin main
  echo 'set -o vi' >>"$HUB/personal.bash"
  run "$AUTO" "$HUB"
  assert_success
  assert_equal "$(origin_count)" 3
  assert_equal "$(git -C "$ORIGIN" rev-list --merges --count main)" 0
  assert_equal "$(cat "$HUB/vm.txt")" "from the vm"
}

@test "conflict: aborted, working tree byte-identical to before, result=fail" {
  echo 'vm version' >"$VM/personal.bash"
  git -C "$VM" add -A && git -C "$VM" commit -qm "vm edit" && git -C "$VM" push -q origin main
  echo 'hub version' >"$HUB/personal.bash"
  run "$AUTO" "$HUB"
  assert_failure
  assert_equal "$(cat "$HUB/personal.bash")" "hub version"
  assert_equal "$(status_val result)" fail
  [[ "$(status_val message)" == *conflict* ]]
  [ ! -d "$HUB/.git/rebase-merge" ] && [ ! -d "$HUB/.git/rebase-apply" ]
  assert_equal "$(origin_count)" 2
}

@test "DOTFILES_NO_PUSH commits locally but does not push" {
  echo 'x' >>"$HUB/personal.bash"
  run env DOTFILES_NO_PUSH=1 "$AUTO" "$HUB"
  assert_success
  assert_equal "$(origin_count)" 1
  assert_equal "$(git -C "$HUB" rev-list --count main)" 2
}

@test "unreachable origin is a recorded failure, not silent" {
  git -C "$HUB" remote set-url origin "$BATS_TEST_TMPDIR/missing.git"
  run "$AUTO" "$HUB"
  assert_failure
  assert_equal "$(status_val result)" fail
  [[ "$(status_val message)" == *fetch* ]]
}

@test "timer runs daily at 03:00 Amsterdam time and catches up after downtime" {
  run cat "$DOTFILES_DIR/hub/systemd/dotfiles-autocommit.timer"
  assert_output --partial "OnCalendar=*-*-* 03:00:00 Europe/Amsterdam"
  assert_output --partial "Persistent=true"
  run cat "$DOTFILES_DIR/hub/systemd/dotfiles-autocommit.service"
  assert_output --partial "Type=oneshot"
}

@test "commits made by hand on the hub are checked before pushing" {
  echo "host 100.""99.183.7" >"$HUB/hosts.txt"
  git -C "$HUB" add -A && git -C "$HUB" commit -qm "made by hand"
  run "$AUTO" "$HUB"
  assert_failure
  assert_equal "$(origin_count)" 1
  assert_equal "$(status_val result)" fail
  [[ "$(status_val message)" == *push* ]]
}

@test "refuses to run its own copy from inside the synced repo" {
  run "$HUB/hub/autocommit.sh" "$HUB"
  assert_failure
  assert_output --partial "pinned"
}

@test "a broken checker is reported as a tool failure, not as findings" {
  printf '#!/bin/sh\nexit 2\n' >"$PINNED/check-public.sh"
  echo x >>"$HUB/personal.bash"
  run "$AUTO" "$HUB"
  assert_failure
  [[ "$(status_val message)" == *"check could not run"* ]]
}

@test "service runs the pinned copy with hardening" {
  run cat "$DOTFILES_DIR/hub/systemd/dotfiles-autocommit.service"
  assert_output --partial "ExecStart=/usr/local/lib/dotfiles-hub/autocommit.sh /srv/dotfiles"
  assert_output --partial "ProtectSystem=strict"
  assert_output --partial "ReadWritePaths=/srv/dotfiles"
  assert_output --partial "NoNewPrivileges=yes"
  # Root system services get no $HOME; git needs it for the deploy key and identity.
  assert_output --partial "Environment=HOME=/root"
}

@test "refuses to run when the repo doesn't ignore the hub's private files" {
  git -C "$HUB" rm -q --cached .gitignore && rm "$HUB/.gitignore"
  git -C "$HUB" commit -qm "no gitignore"
  git -C "$HUB" push -q origin main
  printf 'private-word\n' >"$HUB/hub/local.denylist"
  run "$AUTO" "$HUB"
  assert_failure
  assert_output --partial "not git-ignored"
  run git -C "$ORIGIN" ls-tree -r --name-only main
  refute_line "hub/local.denylist"
}
