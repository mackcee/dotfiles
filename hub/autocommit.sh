#!/usr/bin/env bash
# autocommit.sh <repo-dir>
#
# Runs once a day on the Syncthing hub, the only copy of ~/dotfiles that is a
# git repository:
#   1. fetch GitHub
#   2. if files changed locally: secret/privacy check, then commit
#   3. if GitHub is ahead (a push from a VM): rebase onto it; Syncthing then
#      carries those changes to the desktops. On conflict: abort, change nothing.
#   4. push whatever is new
# The outcome goes to <repo>/.hub-status (git-ignored, synced), which
# `dot status` shows on every machine.
#
# Env: DOTFILES_BRANCH (default main), DOTFILES_NO_PUSH=1 to skip the push.
#
# Must run from a pinned copy OUTSIDE the repo (/usr/local/lib/dotfiles-hub/):
# the repo is writable by every Syncthing peer, so a copy inside it could be
# edited to disable its own safety check.
set -euo pipefail

repo=${1:?usage: autocommit.sh <repo-dir>}
branch=${DOTFILES_BRANCH:-main}
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
status_file="$repo/.hub-status"
g() { git -C "$repo" "$@"; }
repo_abs="$(cd "$repo" && pwd -P)"

write_status() {
  local result=$1 message=$2 push=${3:-} prev=""
  [[ -f "$status_file" ]] && prev=$(sed -n 's/^last_push=//p' "$status_file")
  printf 'last_run=%s\nresult=%s\nmessage=%s\nlast_push=%s\n' \
    "$(date -Iseconds)" "$result" "$message" "${push:-$prev}" >"$status_file.tmp"
  mv "$status_file.tmp" "$status_file"
}

fail() {
  write_status fail "$1"
  echo "autocommit: $1" >&2
  exit 1
}

case "$here/" in
  "$repo_abs"/*) fail "refusing to run from inside the repo; run the pinned copy in /usr/local/lib/dotfiles-hub" ;;
esac

# check <mode...>: run the pinned checker; fail with a clear reason if blocked.
check() {
  local what=$1 out rc=0 n first
  shift
  out=$("$here/check-public.sh" "$repo" "$@") || rc=$?
  if ((rc == 2)); then
    [[ "$what" == commit ]] && g reset -q
    fail "safety check could not run (gitleaks or git missing/broken); nothing was ${what}ed"
  elif ((rc != 0)); then
    [[ "$what" == commit ]] && g reset -q
    n=$(printf '%s\n' "$out" | grep -c . || true)
    first=$(printf '%s\n' "$out" | head -3 | awk -F'\t' '{ printf "%s %s:%s; ", $1, $2, $3 }')
    fail "check-public blocked the $what: $n finding(s): ${first%; }"
  fi
}

# The hub's own private files must never be committable. check-public skips
# hub/local.denylist on purpose, so .gitignore is what keeps it out of git.
for f in hub/local.denylist hub/local.env .hub-status; do
  g check-ignore -q --no-index "$f" ||
    fail "$f is not git-ignored in this repo; refusing to commit anything"
done

g fetch -q origin "$branch" 2>/dev/null || fail "fetch from origin failed"

did=()

# --- 2. local changes ----------------------------------------------------------
if [[ -n "$(g status --porcelain)" ]]; then
  g add -A
  check commit --staged
  files=$(g diff --cached --name-only)
  count=$(printf '%s\n' "$files" | grep -c .)
  g commit -q -m "auto: $count files changed" -m "$files"
  did+=("committed $count file(s)")
fi

# --- 3. GitHub ahead -----------------------------------------------------------
behind=$(g rev-list --count "HEAD..origin/$branch")
if ((behind > 0)); then
  ahead=$(g rev-list --count "origin/$branch..HEAD")
  if ((ahead == 0)); then
    g merge -q --ff-only "origin/$branch" || fail "fast-forward from origin failed"
  elif ! g rebase -q "origin/$branch" >/dev/null 2>&1; then
    g rebase --abort >/dev/null 2>&1 || true
    fail "conflict: GitHub has $behind commit(s) that clash with local changes; resolve by hand in $repo"
  fi
  did+=("pulled $behind commit(s) from GitHub")
fi

# --- 4. push -------------------------------------------------------------------
push_sha=""
if (($(g rev-list --count "origin/$branch..HEAD") > 0)); then
  if [[ "${DOTFILES_NO_PUSH:-}" == 1 ]]; then
    did+=("push skipped (DOTFILES_NO_PUSH)")
  else
    # Every commit about to go public is checked, not just today's auto-commit.
    check push --range "origin/$branch..HEAD"
    g push -q origin "HEAD:$branch" 2>/dev/null || fail "push to origin failed"
    push_sha=$(g rev-parse HEAD)
    did+=("pushed")
  fi
fi

if ((${#did[@]} == 0)); then
  write_status noop "nothing changed"
else
  msg=$(printf '%s, ' "${did[@]}")
  write_status ok "${msg%, }" "$push_sha"
fi
